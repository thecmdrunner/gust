import Foundation
import GustCore

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
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
// Reproduce the first preset after the hidden app's helper session expired.
var alive = false
var starts = 0
var refuse = false
let sessionModel = FanModel(smc: smc, polling: false, authorize: { alive = true; starts += 1 }, request: { command in
    guard alive else { throw HelperConnectionError() }
    if refuse && command == "ping" { throw GustError("Mac is hot. Keep Auto enabled.") }
    if command.hasPrefix("set ") {
        smc.values["F0Md"] = fixtureNumber(1)
        smc.values["F0Tg"] = fixtureNumber(6000)
    } else if command == "auto" || command == "quit" {
        smc.values["F0Md"] = fixtureNumber(0)
    }
    return "OK"
})
sessionModel.refresh(); waitFor { sessionModel.fresh }
sessionModel.choose("Max"); waitFor { !sessionModel.busy }
sessionModel.choose("Auto"); waitFor { !sessionModel.busy }
if CommandLine.arguments.contains("--heartbeat") {
    let heartbeatSMC = FixtureSMC(); heartbeatSMC.values = smc.values
    let lock = NSLock()
    var pings = 0
    let backgroundModel = FanModel(smc: heartbeatSMC, authorize: {}, request: { command in
        if command == "ping" { lock.lock(); pings += 1; lock.unlock() }
        if command.hasPrefix("set ") { heartbeatSMC.values["F0Md"] = fixtureNumber(1) }
        if command == "auto" || command == "quit" { heartbeatSMC.values["F0Md"] = fixtureNumber(0) }
        return "OK"
    })
    waitFor { backgroundModel.fresh }
    backgroundModel.choose("Max"); waitFor { !backgroundModel.busy }
    lock.lock(); let before = pings; lock.unlock()
    // No window or running UI loop: the safety heartbeat must still make progress.
    Thread.sleep(forTimeInterval: 2.2)
    lock.lock(); let after = pings; lock.unlock()
    expect(after > before, "Hidden-window heartbeat must not depend on the main run loop")
    var stopped = false
    backgroundModel.shutdown { stopped = true }; waitFor { stopped }
    print("PASS heartbeat continues without the UI run loop")
}
alive = false // watchdog expired while the panel was hidden; physical fans are stopped.
sessionModel.choose("Max"); waitFor { !sessionModel.busy }
if let error = sessionModel.error { fputs("REPRO: hidden-window Max -> \(error)\n", stderr) }
expect(sessionModel.error == nil && sessionModel.mode == "Max" && starts == 2,
       "First Max after an expired helper must reconnect and apply, not leave stopped fans and a disconnect error")
print("PASS first Max after an expired hidden session reconnects")
sessionModel.choose("Auto"); waitFor { !sessionModel.busy }
refuse = true
sessionModel.refresh()
waitFor { sessionModel.error != nil }
expect(sessionModel.fresh && sessionModel.canControlFans && sessionModel.readError == nil, "Helper safety refusal must not hide Auto or invalidate fan readings")
sessionModel.choose("Max"); waitFor { !sessionModel.busy }
expect(starts == 2 && sessionModel.error == "Mac is hot. Keep Auto enabled.", "A safety refusal must not restart the helper")
print("PASS safety refusal is surfaced without reconnecting")
sessionModel.choose("Auto"); waitFor { !sessionModel.busy }
expect(sessionModel.error == nil && sessionModel.mode == "Auto", "Auto must remain available after a safety refusal")
print("PASS Auto remains available after a safety refusal")
