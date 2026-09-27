import AppKit
import SwiftUI
import GustCore

func authorizeHelper() throws {
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/GustHelper").path
    guard FileManager.default.isExecutableFile(atPath: helper) else { throw GustError("GustHelper is missing. Reinstall Gust.") }
    let quote = "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "'"
    // Retire the v1.0.x LaunchDaemon before starting the session-scoped helper.
    let migration = """
    if /bin/launchctl print system/com.thecmdrunner.gust.helper >/dev/null 2>&1; then
        /bin/launchctl bootout system/com.thecmdrunner.gust.helper || exit 1
    fi
    /bin/rm -f /Library/LaunchDaemons/com.thecmdrunner.gust.helper.plist /Library/PrivilegedHelperTools/com.thecmdrunner.gust.helper || exit 1
    """
    let command = migration + "\n\(quote) --serve \(getuid()) \(getpid()) </dev/null >/dev/null 2>&1 &"
    let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges with prompt \"Gust needs permission to control your fans.\""]
    let output = Pipe(); process.standardError = output
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw GustError("Fan control wasn’t authorized. Auto is still available.")
    }
    for _ in 0..<30 {
        if (try? HelperClient.request("ping")) != nil { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw GustError("Helper did not start. Close other Gust windows, then try again.")
}

final class FanModel: ObservableObject {
    @Published var fans: [Fan] = []
    @Published var mode = "Auto"
    @Published var fraction = 0.5
    @Published var slider = 0.5
    @Published var busy = false
    @Published var error: String?
    @Published var readError: String?
    @Published var fresh = false
    @Published var temperature: TemperatureReading?
    @Published var maxBaseline: TemperatureReading?
    @Published var showDetails = false
    private let queue = DispatchQueue(label: "com.thecmdrunner.gust.smc", qos: .userInitiated)
    private var controller: FanController?
    private var temperatureReader: TemperatureReader?
    private var connected = false
    private var timer: DispatchSourceTimer?
    private var overrideActivity: NSObjectProtocol?
    private let authorize: () throws -> Void
    private let request: (String) throws -> String
    var isFanless: Bool { fresh && fans.isEmpty }
    var canControlFans: Bool { fresh && !fans.isEmpty }
    var statusChanged: (()->Void)?
    var actionFailed: (()->Void)?
    init(smc: SMCTransport? = nil, polling: Bool = true, authorize: @escaping () throws -> Void = authorizeHelper, request: @escaping (String) throws -> String = HelperClient.request) {
        self.authorize = authorize
        self.request = request
        if let smc {
            controller = FanController(smc: smc)
            temperatureReader = TemperatureReader(smc: smc)
        }
        guard polling else { return }
        refresh()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer
    }
    // Confined to the SMC queue. An active override must not be App Napped.
    private func keepOverrideAwake(_ active: Bool) {
        if active && overrideActivity == nil {
            overrideActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Maintain the fan override safety heartbeat")
        } else if !active, let activity = overrideActivity {
            ProcessInfo.processInfo.endActivity(activity); overrideActivity = nil
        }
    }
    deinit {
        timer?.cancel()
        if let activity = overrideActivity { ProcessInfo.processInfo.endActivity(activity) }
    }
    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if self.controller == nil {
                    let smc = try AppleSMC()
                    self.controller = FanController(smc: smc)
                    self.temperatureReader = TemperatureReader(smc: smc)
                }
                let temperature = self.temperatureReader?.read()
                DispatchQueue.main.async { self.temperature = temperature }
                var helperIssue: String?
                if self.connected {
                    do { _ = try self.request("ping") }
                    catch is HelperConnectionError {
                        self.connected = false; self.keepOverrideAwake(false)
                    }
                    catch { helperIssue = error.localizedDescription }
                }
                let fans = try self.controller!.fans()
                if !fans.contains(where: { $0.manual }) { self.keepOverrideAwake(false) }
                let connected = self.connected
                DispatchQueue.main.async {
                    self.fans = fans; self.fresh = true; self.readError = nil
                    if let helperIssue { self.error = helperIssue }
                    if !connected { self.mode = fans.contains(where: { $0.manual }) ? "External" : "Auto" }
                    else if !fans.contains(where: { $0.manual }) { self.mode = "Auto" }
                    if self.mode != "Max" { self.maxBaseline = nil }
                    self.statusChanged?()
                }
            } catch {
                self.connected = false
                self.keepOverrideAwake(false)
                DispatchQueue.main.async { self.fresh = false; self.maxBaseline = nil; self.readError = error.localizedDescription; self.mode = "Checking"; self.statusChanged?() }
            }
        }
    }
    func choose(_ mode: String, fraction: Double? = nil) {
        // Gate before authorization, including calls from menus or stale UI actions.
        guard mode == "Auto" || canControlFans else { return }
        if mode == "Auto" && fans.isEmpty { return }
        if isFanless { return }
        guard !busy || mode == "Auto" else { return }
        busy = true; error = nil
        statusChanged?()
        let value = fraction ?? (mode == "Min" ? 0 : mode == "Max" ? 1 : self.fraction)
        queue.async {
            do {
                if mode != "Auto" { self.keepOverrideAwake(true) }
                if self.connected {
                    do { _ = try self.request("ping") }
                    catch is HelperConnectionError { self.connected = false }
                    catch { if mode != "Auto" { throw error } }
                }
                if mode != "Auto", !self.connected { try self.authorize(); self.connected = true }
                if self.connected { _ = try self.request(mode == "Auto" ? "auto" : "set \(value)") }
                else if try self.controller?.fans().contains(where: { $0.manual }) == true {
                    throw GustError("Another app controls these fans. Set that app to Auto first.")
                }
                let current = try self.controller?.fans() ?? []
                let temperature = self.temperatureReader?.read()
                if mode == "Auto", current.contains(where: { $0.manual }) {
                    throw GustError("A fan is still in manual mode. Close other fan utilities and retry Auto.")
                }
                if mode == "Auto" { self.keepOverrideAwake(false) }
                DispatchQueue.main.async {
                    if mode != "Max" { self.maxBaseline = nil }
                    else if self.mode != "Max" { self.maxBaseline = temperature }
                    self.temperature = temperature
                    self.mode = mode; self.fraction = value; self.slider = value; self.fans = current; self.fresh = true; self.busy = false
                    self.statusChanged?()
                }
            } catch {
                if error is HelperConnectionError { self.connected = false }
                let current = (try? self.controller?.fans()) ?? []
                self.keepOverrideAwake(self.connected && current.contains(where: { $0.manual }))
                DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false; self.statusChanged?(); self.actionFailed?() }
            }
        }
    }
    func shutdown(_ completion: @escaping ()->Void) {
        timer?.cancel()
        queue.async { if self.connected { _ = try? self.request("quit") }; self.keepOverrideAwake(false); DispatchQueue.main.async(execute: completion) }
    }
}
