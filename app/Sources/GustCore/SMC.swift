import Foundation
import CSMC

public struct GustError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct SMCValue {
    public let type: String
    public let bytes: [UInt8]
    public init(type: String, bytes: [UInt8]) { self.type = type; self.bytes = bytes }
    public func number() throws -> Double {
        let n: Double
        switch (type, bytes.count) {
        case ("flt ", 4):
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            n = Double(Float(bitPattern: bits))
        case ("fpe2", 2): n = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case ("sp78", 2): n = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case ("ui8 ", 1): n = Double(bytes[0])
        case ("ui16", 2): n = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default: throw GustError("Unsupported SMC value: \(type)")
        }
        guard n.isFinite else { throw GustError("SMC returned an invalid number.") }
        return n
    }
    public func encoding(_ number: Double) throws -> SMCValue {
        guard number.isFinite, number >= 0 else { throw GustError("Invalid fan target.") }
        let data: [UInt8]
        switch (type, bytes.count) {
        case ("flt ", 4):
            guard number <= Double(Float.greatestFiniteMagnitude) else { throw GustError("Value too large.") }
            let bits = Float(number).bitPattern
            data = (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        case ("fpe2", 2):
            guard number < 16384 else { throw GustError("RPM out of range.") }
            let bits = UInt16((number * 4).rounded()); data = [UInt8(bits >> 8), UInt8(truncatingIfNeeded: bits)]
        case ("ui8 ", 1):
            guard number <= 255 else { throw GustError("Value out of range.") }; data = [UInt8(number)]
        case ("ui16", 2):
            guard number <= 65535 else { throw GustError("Value out of range.") }
            let bits = UInt16(number); data = [UInt8(bits >> 8), UInt8(truncatingIfNeeded: bits)]
        default: throw GustError("Unsupported writable SMC type: \(type)")
        }
        return SMCValue(type: type, bytes: data)
    }
}

public protocol SMCTransport: AnyObject {
    func read(_ key: String) throws -> SMCValue
    func write(_ key: String, value: SMCValue) throws
}
extension SMCTransport {
    public func number(_ key: String) throws -> Double { try read(key).number() }
    public func set(_ key: String, _ number: Double) throws { try write(key, value: read(key).encoding(number)) }
}

public final class AppleSMC: SMCTransport {
    private var connection: UInt32 = 0
    public init() throws {
        let result = gust_smc_open(&connection)
        guard result == 0 else { throw GustError("Cannot open AppleSMC (\(result)).") }
    }
    deinit { gust_smc_close(connection) }
    public func read(_ key: String) throws -> SMCValue {
        var value = GustValue()
        let result = gust_smc_read(connection, key, &value)
        guard result == 0 else { throw GustError("Cannot read \(key) (\(result)).") }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(value.size))) }
        let type = String(bytes: [24,16,8,0].map { UInt8(truncatingIfNeeded: value.type >> $0) }, encoding: .ascii) ?? "????"
        return SMCValue(type: type, bytes: bytes)
    }
    public func write(_ key: String, value: SMCValue) throws {
        guard key.utf8.count == 4, value.bytes.count <= 32 else { throw GustError("Invalid SMC write.") }
        var raw = GustValue(); raw.size = UInt32(value.bytes.count)
        raw.type = value.type.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
        withUnsafeMutableBytes(of: &raw.bytes) { $0.copyBytes(from: value.bytes) }
        let result = gust_smc_write(connection, key, &raw)
        guard result == 0 else { throw GustError("Firmware rejected \(key) (\(result)).") }
    }
}

public struct Fan: Identifiable, Codable {
    public var id: Int
    public var actual: Double
    public var minimum: Double
    public var maximum: Double
    public var target: Double
    public var manual: Bool
    public var modeKey: String?
    public var name: String { "Fan \(id + 1)" }
    public func rpm(at fraction: Double) throws -> Double {
        guard fraction.isFinite, (0...1).contains(fraction), minimum.isFinite, maximum.isFinite,
              minimum >= 0, maximum > minimum, maximum < 20000 else { throw GustError("Invalid fan limits or target.") }
        return minimum + fraction * (maximum - minimum)
    }
}

public final class FanController {
    public let smc: SMCTransport
    private var controlled = Set<Int>()
    private var modeKeys: [Int: String] = [:]
    private var unlocked = false
    private let wait: (Double) -> Void
    public var hasOverride: Bool { !controlled.isEmpty || unlocked }
    public init(smc: SMCTransport, wait: @escaping (Double)->Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.smc = smc; self.wait = wait
    }
    public func fans() throws -> [Fan] {
        let count = try smc.number("FNum")
        guard count >= 0, count <= 10, count.rounded() == count else { throw GustError("Unsupported fan count.") }
        return try (0..<Int(count)).map { id in
            let prefix = "F\(id)"
            let key = [prefix + "Md", prefix + "md"].first { (try? smc.read($0)) != nil }
            let manual: Bool
            if let key { manual = try smc.number(key) == 1 }
            else { manual = Int(try smc.number("FS! ")) & (1 << id) != 0 }
            return Fan(id: id, actual: try smc.number(prefix + "Ac"), minimum: try smc.number(prefix + "Mn"),
                       maximum: try smc.number(prefix + "Mx"), target: try smc.number(prefix + "Tg"), manual: manual, modeKey: key)
        }
    }
    public func set(fraction: Double) throws {
        let all = try fans()
        guard !all.isEmpty else { throw GustError("This Mac has no fans.") }
        let targets = try all.map { try $0.rpm(at: fraction) }
        guard all.allSatisfy({ !$0.manual || controlled.contains($0.id) }) else {
            throw GustError("Another app controls the fans. Set it to Auto first.")
        }
        do {
            for (fan, rpm) in zip(all, targets) {
                // Record ownership before the first write, including failed/partial writes.
                controlled.insert(fan.id)
                if let key = fan.modeKey {
                    modeKeys[fan.id] = key
                    do {
                        try smc.set(key, 1)
                        wait(0.15)
                        guard try smc.number(key) == 1 else { throw GustError("macOS retained fan control.") }
                    }
                    catch {
                        guard let unlock = try? smc.number("Ftst"), unlock == 0 || unlocked else { throw error }
                        unlocked = true; try smc.set("Ftst", 1)
                        wait(3)
                        var accepted = false
                        for _ in 0..<50 {
                            wait(0.1)
                            if (try? smc.set(key, 1)) != nil, (try? smc.number(key)) == 1 { accepted = true; break }
                        }
                        guard accepted else { throw GustError("This firmware did not allow manual fan control.") }
                    }
                    guard try smc.number(key) == 1 else { throw GustError("macOS retained fan control.") }
                } else {
                    let bits = Int(try smc.number("FS! ")) | (1 << fan.id)
                    try smc.set("FS! ", Double(bits))
                }
                try smc.set("F\(fan.id)Tg", rpm)
                wait(0.2)
                guard abs(try smc.number("F\(fan.id)Tg") - rpm) < 2 else { throw GustError("Fan target was not accepted.") }
            }
        } catch {
            let original = error
            do { try restore() } catch { throw GustError("\(original.localizedDescription) Auto restore also failed: \(error.localizedDescription)") }
            throw original
        }
    }
    public func restore() throws {
        var failures = [String]()
        if unlocked {
            do { try smc.set("Ftst", 0); wait(0.2); unlocked = false }
            catch { failures.append(error.localizedDescription) }
        }
        for id in controlled.sorted() {
            do {
                if let key = modeKeys[id] {
                    if try smc.number(key) == 1 { try smc.set(key, 0); wait(0.2) }
                    guard try smc.number(key) != 1 else { throw GustError("Fan \(id + 1) is still manual.") }
                } else {
                    let bits = Int(try smc.number("FS! ")) & ~(1 << id)
                    try smc.set("FS! ", Double(bits))
                    guard Int(try smc.number("FS! ")) & (1 << id) == 0 else { throw GustError("Fan mode did not reset.") }
                }
                controlled.remove(id)
            } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { throw GustError(failures.joined(separator: " ")) }
    }
}

public enum HelperCommand: Equatable {
    case ping, auto, quit, set(Double)
    public static func parse(_ value: String) throws -> Self {
        switch value {
        case "ping": return .ping
        case "auto": return .auto
        case "quit": return .quit
        default:
            let parts = value.split(separator: " ", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "set", let n = Double(parts[1]), n.isFinite, (0...1).contains(n) else {
                throw GustError("Invalid command.")
            }
            return .set(n)
        }
    }
}

public enum HelperClient {
    public static func request(_ command: String) throws -> String {
        var response = [CChar](repeating: 0, count: 2048)
        guard gust_request(getuid(), getpid(), command, &response, response.count) == 0 else {
            throw GustError("Fan helper disconnected. macOS control restores after the safety timeout.")
        }
        let reply = String(cString: response)
        guard reply.hasPrefix("OK") else { throw GustError(String(reply.dropFirst(4))) }
        return reply
    }
}
