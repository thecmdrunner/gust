import Foundation
import Darwin

public struct TemperatureReading: Codable {
    public let celsius: Double
    public let source: String
    public let sensorKeys: [String]
    public let hottestSensor: String
    public func change(since baseline: TemperatureReading) -> Double? {
        // A disappearing sensor must not look like successful cooling.
        guard source == baseline.source, sensorKeys == baseline.sensorKeys else { return nil }
        return celsius - baseline.celsius
    }
}

/// Read-only SMC temperature sampling; never requires the privileged fan helper.
public final class TemperatureReader {
    private let smc: SMCTransport
    private let candidates: [String]
    private let fallback: [String]
    private var supported: [String] = []
    private var supportedFallback: [String] = []
    private var nextDiscovery: TimeInterval = 0
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
    // Known CPU/GPU keys, adapted from the MIT-licensed Stats sensor catalog.
    // Names vary by chip generation. Read only keys actually present on the host.
    // See Resources/ThirdPartyNotices.txt.
    public init(smc: SMCTransport, appleSilicon: Bool = TemperatureReader.isAppleSilicon) {
        self.smc = smc
        if appleSilicon {
            candidates = Array(Set([
                "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
                "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
                "Te05", "Te0L", "Te0P", "Te0S", "Te09", "Te0H",
                "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
                "Tp0V", "Tp0Y", "Tp0e", "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0a", "Tp0d", "Tp0g", "Tp0m", "Tp0p", "Tp0u", "Tp0y",
                "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j", "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",
                "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0d", "Tg0e", "Tg0k", "Tg0U", "Tg0X", "Tg0g", "Tg1Y", "Tg1c", "Tg1g"
            ])).sorted()
            fallback = []
        } else {
            candidates = (["TC0D", "TC0E", "TC0F", "TCAD", "TCGC", "TG0D", "TGDD"] +
                Array("0123456789ABCDEF").flatMap { ["TC\($0)C", "TC\($0)c"] }).sorted()
            fallback = ["TC0P"]
        }
    }
    private func temperature(_ key: String) -> Double? {
        guard let raw = try? smc.read(key), ["flt ", "sp78"].contains(raw.type),
              let value = try? raw.number(), value > 0, value <= 150 else { return nil }
        return value
    }
    public func read(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TemperatureReading? {
        if now >= nextDiscovery {
            supported = candidates.filter { temperature($0) != nil }
            supportedFallback = fallback.filter { temperature($0) != nil }
            nextDiscovery = now + 30
        }
        func reading(_ keys: [String], source: String) -> TemperatureReading? {
            let values = keys.compactMap { key -> (String, Double)? in temperature(key).map { (key, $0) } }
            guard let hottest = values.max(by: { $0.1 < $1.1 }) else { return nil }
            return TemperatureReading(celsius: hottest.1, source: source, sensorKeys: values.map { $0.0 }, hottestSensor: hottest.0)
        }
        return reading(supported, source: "Chip") ?? reading(supportedFallback, source: "CPU proximity")
    }
}
