import Foundation
import GustCore

var passed = 0
func check(_ name: String, _ block: () throws -> Void) {
    do { try block(); passed += 1; print("PASS \(name)") }
    catch { fputs("FAIL \(name): \(error)\n", stderr); exit(1) }
}
func expect(_ condition: @autoclosure () throws -> Bool) throws {
    if try !condition() { throw GustError("Assertion failed") }
}
func rejects(_ block: () throws -> Void) throws {
    do { try block() } catch { return }; throw GustError("Expected rejection")
}
func float(_ n: Double) -> SMCValue { try! SMCValue(type: "flt ", bytes: [0,0,0,0]).encoding(n) }
func byte(_ n: UInt8) -> SMCValue { SMCValue(type: "ui8 ", bytes: [n]) }
final class MockSMC: SMCTransport {
    var values: [String: SMCValue] = ["FNum": byte(2), "Ftst": byte(0)]
    var writes: [String] = []
    var fail: String?
    var rejectRestore = false
    var needsUnlock = false
    init(lowercase: Bool = false, intel: Bool = false) {
        for id in 0..<2 {
            for (suffix, n) in [("Ac", 1600.0), ("Mn", 1350.0), ("Mx", 5777.0), ("Tg", 1600.0)] {
                values["F\(id)\(suffix)"] = intel ? try! SMCValue(type: "fpe2", bytes: [0,0]).encoding(n) : float(n)
            }
            if !intel { values["F\(id)\(lowercase ? "md" : "Md")"] = byte(0) }
        }
        if intel { values["FS! "] = SMCValue(type: "ui16", bytes: [0, 128]) }
    }
    func read(_ key: String) throws -> SMCValue {
        guard let value = values[key] else { throw GustError("Missing \(key)") }; return value
    }
    func write(_ key: String, value: SMCValue) throws {
        writes.append(key)
        if fail == key { throw GustError("Injected failure") }
        let n = try value.number()
        let unlocked = try values["Ftst"]!.number() != 0
        if rejectRestore && key.hasSuffix("Md") && n == 0 { throw GustError("Restore failed") }
        if needsUnlock && key.hasSuffix("Md") && n == 1 && !unlocked { return }
        values[key] = value
    }
}

check("float codec and fixed-point codec") {
    for n in [0.0, 1350, 5777, 16383.5] {
        try expect(float(n).number() == n)
        try expect(SMCValue(type: "fpe2", bytes: [0,0]).encoding(n).number() == n)
    }
    try expect(SMCValue(type: "fpe2", bytes: [0x15,0x18]).number() == 1350)
}
check("reject nonfinite and unsupported encodings") {
    try rejects { _ = try float(1).encoding(.nan) }
    try rejects { _ = try float(1).encoding(.infinity) }
    try rejects { _ = try SMCValue(type: "flt ", bytes: [0,0,128,127]).number() }
    try rejects { _ = try SMCValue(type: "xxxx", bytes: [0]).number() }
    try rejects { _ = try SMCValue(type: "fpe2", bytes: [0,0]).encoding(16384) }
}
check("all fans max, min, custom, auto") {
    let mock = MockSMC(); let c = FanController(smc: mock)
    for (fraction, rpm) in [(1.0,5777.0),(0.0,1350.0),(0.5,3563.5)] {
        try c.set(fraction: fraction)
        try expect(c.fans().allSatisfy { $0.manual && $0.target == rpm })
    }
    try c.restore(); try expect(c.fans().allSatisfy { !$0.manual }); try expect(!c.hasOverride)
}
check("invalid targets cause zero writes") {
    for n in [-0.1, 1.1, Double.nan, Double.infinity] {
        let mock = MockSMC(); let c = FanController(smc: mock)
        try rejects { try c.set(fraction: n) }; try expect(mock.writes.isEmpty)
    }
}
check("invalid firmware limits fail closed") {
    let mock = MockSMC(); mock.values["F1Mx"] = float(1000)
    try rejects { try FanController(smc: mock).set(fraction: 1) }; try expect(mock.writes.isEmpty)
}
check("second fan failure rolls both fans back") {
    let mock = MockSMC(); mock.fail = "F1Tg"; let c = FanController(smc: mock)
    try rejects { try c.set(fraction: 1) }
    try expect(c.fans().allSatisfy { !$0.manual }); try expect(!c.hasOverride)
}
check("restore failure remains owned and can be retried") {
    let mock = MockSMC(); let c = FanController(smc: mock); try c.set(fraction: 1)
    mock.rejectRestore = true; try rejects { try c.restore() }; try expect(c.hasOverride)
    mock.rejectRestore = false; try c.restore(); try expect(!c.hasOverride)
}
check("silent mode refusal triggers unlock and resets Ftst") {
    let mock = MockSMC(); mock.needsUnlock = true
    let c = FanController(smc: mock, wait: { _ in }); try c.set(fraction: 1)
    try expect(mock.number("Ftst") == 1); try expect(c.fans().allSatisfy { $0.manual })
    try c.restore(); try expect(mock.number("Ftst") == 0)
}
check("lowercase Apple Silicon keys") {
    let mock = MockSMC(lowercase: true); let c = FanController(smc: mock)
    try c.set(fraction: 0); try expect(c.fans().allSatisfy { $0.manual }); try c.restore()
}
check("Intel force mask preserves unrelated bits") {
    let mock = MockSMC(intel: true); let c = FanController(smc: mock)
    try c.set(fraction: 1); try expect(mock.number("FS! ") == 131)
    try c.restore(); try expect(mock.number("FS! ") == 128)
}
check("another fan utility is not overwritten") {
    let mock = MockSMC(); mock.values["F0Md"] = byte(1)
    try rejects { try FanController(smc: mock).set(fraction: 1) }; try expect(mock.writes.isEmpty)
}
check("fanless Mac makes no writes") {
    let mock = MockSMC(); mock.values["FNum"] = byte(0); let c = FanController(smc: mock)
    try expect(c.fans().isEmpty); try rejects { try c.set(fraction: 1) }; try expect(mock.writes.isEmpty)
}
check("helper rejects malformed or arbitrary operations") {
    for input in ["set nan", "set inf", "set -1", "set 1.1", "set 0.5 extra", "set  1", "write F0Tg 9000", "quit; whoami", ""] {
        try rejects { _ = try HelperCommand.parse(input) }
    }
    try expect(HelperCommand.parse("set 0.5") == .set(0.5)); try expect(HelperCommand.parse("auto") == .auto)
}

check("signed temperature codec is read-only") {
    try expect(SMCValue(type: "sp78", bytes: [0x3f, 0x80]).number() == 63.5)
    try expect(SMCValue(type: "sp78", bytes: [0xff, 0x80]).number() == -0.5)
    try rejects { _ = try SMCValue(type: "sp78", bytes: [0x3f]).number() }
    try rejects { _ = try SMCValue(type: "sp78", bytes: [0, 0]).encoding(50) }
}
check("peak chip temperature tracks cooling without SMC writes") {
    let mock = MockSMC()
    mock.values["Tp01"] = float(82); mock.values["Tg0D"] = float(76)
    let reader = TemperatureReader(smc: mock, appleSilicon: true)
    let baseline = reader.read(now: 0)!
    try expect(baseline.celsius == 82 && baseline.hottestSensor == "Tp01")
    mock.values["Tp01"] = float(68); mock.values["Tg0D"] = float(70)
    let cooled = reader.read(now: 1)!
    try expect(cooled.celsius == 70 && cooled.hottestSensor == "Tg0D")
    try expect(cooled.change(since: baseline) == -12)
    try expect(mock.writes.isEmpty)
}
check("sensor loss never appears as cooling and discovery recovers") {
    let mock = MockSMC(); mock.values["Tp01"] = float(85); mock.values["Tg0D"] = float(60)
    let reader = TemperatureReader(smc: mock, appleSilicon: true), baseline = reader.read(now: 0)!
    mock.values["Tp01"] = nil
    try expect(reader.read(now: 1)!.change(since: baseline) == nil)
    mock.values["Tg0D"] = nil
    try expect(reader.read(now: 2) == nil)
    mock.values["Te05"] = float(55)
    try expect(reader.read(now: 31)?.celsius == 55)
    try expect(mock.writes.isEmpty)
}
check("unsupported or invalid temperatures remain unavailable") {
    let mock = MockSMC()
    mock.values["Tp01"] = float(0); mock.values["Tp05"] = float(200)
    mock.values["Tp09"] = SMCValue(type: "flt ", bytes: [0,0,128,127])
    mock.values["Tp0D"] = byte(75)
    mock.values["Te05"] = SMCValue(type: "sp78", bytes: [255,128])
    try expect(TemperatureReader(smc: mock, appleSilicon: true).read(now: 0) == nil)
    try expect(mock.writes.isEmpty)
}
check("Intel proximity fallback is labeled and never mixed with chip data") {
    let mock = MockSMC(); mock.values["TC0P"] = SMCValue(type: "sp78", bytes: [50,128])
    mock.values["Tp0P"] = float(90) // Intel powerboard, not CPU.
    let reader = TemperatureReader(smc: mock, appleSilicon: false)
    let proximity = reader.read(now: 0)!
    try expect(proximity.source == "CPU proximity" && proximity.celsius == 50.5)
    mock.values["TCAD"] = SMCValue(type: "sp78", bytes: [70,0])
    let chip = reader.read(now: 31)!
    try expect(chip.source == "Chip" && chip.celsius == 70)
    try expect(chip.change(since: proximity) == nil)
}
print("\(passed) native tests passed")
