import CSMC
import Foundation

/// Thin Swift wrapper over the AppleSMC user client. Reads work unprivileged; writes need root.
enum SMC {
    static func read(_ key: String) -> [UInt8]? {
        var v = SMCVal()
        guard smc_read(key, &v) == 0 else { return nil }
        return withUnsafeBytes(of: v.bytes) { Array($0.prefix(Int(v.size))) }
    }

    static func readFloat(_ key: String) -> Float? {
        guard let b = read(key), b.count == 4 else { return nil }
        return b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    static func readUInt8(_ key: String) -> UInt8? { read(key)?.first }

    @discardableResult
    static func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        smc_write(key, bytes, UInt32(bytes.count)) == 0
    }

    @discardableResult
    static func writeFloat(_ key: String, _ value: Float) -> Bool {
        write(key, withUnsafeBytes(of: value) { Array($0) })
    }
}

struct FanInfo: Equatable {
    var index: Int
    var rpm: Double
    var min: Double
    var max: Double
    var target: Double
    var forced: Bool
}

enum Fans {
    static var count: Int { Int(SMC.readUInt8("FNum") ?? 0) }

    static func info(_ i: Int) -> FanInfo? {
        guard let rpm = SMC.readFloat("F\(i)Ac"),
              let mn = SMC.readFloat("F\(i)Mn"),
              let mx = SMC.readFloat("F\(i)Mx") else { return nil }
        return FanInfo(index: i, rpm: Double(max(rpm, 0)), min: Double(mn), max: Double(mx),
                       target: Double(SMC.readFloat("F\(i)Tg") ?? 0),
                       forced: (SMC.readUInt8("F\(i)Md") ?? 0) == 1)
    }

    static func all() -> [FanInfo] { (0..<count).compactMap(info) }
}

enum Gust {
    static let helperLabel = "com.thecmdrunner.gust.helper"
    static let socketPath = "/var/run/gust.sock"
    static let helperVersion = "1"
}
