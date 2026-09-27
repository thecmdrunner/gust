import Foundation
import GustCore

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}
func waitFor(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    expect(condition(), "Timed out waiting for model")
}
func fixtureNumber(_ value: Double) -> SMCValue { try! SMCValue(type: "flt ", bytes: [0,0,0,0]).encoding(value) }
final class FixtureSMC: SMCTransport {
    var values: [String: SMCValue] = ["FNum": fixtureNumber(0), "Tp09": fixtureNumber(46), "TC0D": fixtureNumber(46)]
    var writes = 0
    func read(_ key: String) throws -> SMCValue {
        guard let value = values[key] else { throw GustError("Missing fixture key") }; return value
    }
    func write(_ key: String, value: SMCValue) throws { writes += 1 }
}

let smc = FixtureSMC()
var authorizations = 0
let model = FanModel(smc: smc, polling: false, authorize: { authorizations += 1 })
expect(!model.isFanless && !model.canControlFans, "Initial empty data must mean checking, not fanless")
for mode in ["Auto", "Min", "Max", "Manual"] { model.choose(mode) }
expect(!model.fresh && !model.busy && authorizations == 0, "Unknown hardware must not authorize or become fanless")
print("PASS checking state cannot authorize or claim fanless")

model.refresh()
waitFor { model.fresh }
expect(model.isFanless && !model.canControlFans, "Confirmed zero fans must enter monitor mode")
expect(model.temperature?.celsius == 46, "Fanless temperature should remain available without a helper")
for mode in ["Auto", "Min", "Max", "Manual"] { model.choose(mode) }
expect(!model.busy && authorizations == 0 && smc.writes == 0, "No fanless preset may prompt or write")
print("PASS fanless monitoring never authorizes or writes fan commands")

smc.values.removeValue(forKey: "FNum")
model.refresh()
waitFor { model.readError != nil }
expect(!model.fresh && !model.isFanless && !model.canControlFans, "Read failure is not proof of a fanless Mac")
expect(model.temperature?.celsius == 46, "Independent temperature reading should survive fan read failure")
model.choose("Max")
expect(authorizations == 0, "Unavailable fan data must block authorization")
print("PASS missing fan count is unavailable, not fanless")

smc.values["FNum"] = fixtureNumber(0)
smc.values["Tp09"] = fixtureNumber(0); smc.values["TC0D"] = fixtureNumber(0)
model.refresh()
waitFor { model.fresh }
expect(model.isFanless && model.temperature == nil && model.readError == nil, "Missing temperature remains a valid fanless state")
print("PASS fanless Mac handles unavailable temperature and read recovery")

smc.values["FNum"] = fixtureNumber(1)
for (key, value) in [("F0Ac",0.0),("F0Mn",0.0),("F0Mx",6000.0),("F0Tg",0.0),("F0Md",0.0)] {
    smc.values[key] = fixtureNumber(value)
}
model.refresh()
waitFor { model.fans.count == 1 }
expect(!model.isFanless && model.canControlFans, "A stopped physical fan still supports fan control")
expect(authorizations == 0 && smc.writes == 0, "Capability detection must be read-only")
print("PASS zero RPM is still active cooling hardware")
print("5 fan availability/model tests passed")
