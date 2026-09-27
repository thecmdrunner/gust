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
    @Published var fresh = false
    @Published var temperature: TemperatureReading?
    @Published var maxBaseline: TemperatureReading?
    @Published var showDetails = false
    private let queue = DispatchQueue(label: "com.thecmdrunner.gust.smc")
    private var controller: FanController?
    private var temperatureReader: TemperatureReader?
    private var connected = false
    private var timer: Timer?
    var statusChanged: (()->Void)?
    var actionFailed: (()->Void)?
    init() {
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        // Keep telemetry and the helper heartbeat alive while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
                if self.connected { _ = try HelperClient.request("ping") }
                let fans = try self.controller!.fans()
                DispatchQueue.main.async {
                    self.fans = fans; self.fresh = true
                    if !self.connected { self.mode = fans.contains(where: { $0.manual }) ? "External" : "Auto" }
                    else if !fans.contains(where: { $0.manual }) { self.mode = "Auto" }
                    if self.mode != "Max" { self.maxBaseline = nil }
                    self.statusChanged?()
                }
            } catch {
                self.connected = false
                DispatchQueue.main.async { self.fresh = false; self.temperature = nil; self.maxBaseline = nil; self.error = error.localizedDescription; self.mode = "Checking"; self.statusChanged?() }
            }
        }
    }
    func choose(_ mode: String, fraction: Double? = nil) {
        guard !busy || mode == "Auto" else { return }
        busy = true; error = nil
        statusChanged?()
        let value = fraction ?? (mode == "Min" ? 0 : mode == "Max" ? 1 : self.fraction)
        queue.async {
            do {
                if mode != "Auto", !self.connected { try authorizeHelper(); self.connected = true }
                if self.connected { _ = try HelperClient.request(mode == "Auto" ? "auto" : "set \(value)") }
                else if try self.controller?.fans().contains(where: { $0.manual }) == true {
                    throw GustError("Another app controls these fans. Set that app to Auto first.")
                }
                let current = try self.controller?.fans() ?? []
                let temperature = self.temperatureReader?.read()
                if mode == "Auto", current.contains(where: { $0.manual }) {
                    throw GustError("A fan is still in manual mode. Close other fan utilities and retry Auto.")
                }
                DispatchQueue.main.async {
                    if mode != "Max" { self.maxBaseline = nil }
                    else if self.mode != "Max" { self.maxBaseline = temperature }
                    self.temperature = temperature
                    self.mode = mode; self.fraction = value; self.slider = value; self.fans = current; self.fresh = true; self.busy = false
                    self.statusChanged?()
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false; self.statusChanged?(); self.actionFailed?() }
            }
        }
    }
    func shutdown(_ completion: @escaping ()->Void) {
        timer?.invalidate()
        queue.async { if self.connected { _ = try? HelperClient.request("quit") }; DispatchQueue.main.async(execute: completion) }
    }
}

struct ThermalPalette {
    var celsius: Double?
    var dark: Bool
    var progress: Double { min(1, max(0, ((celsius ?? 35) - 35) / 65)) }
    var ice: Color { dark ? Color(red: 0.38, green: 0.77, blue: 1) : Color(red: 0.05, green: 0.44, blue: 0.77) }
    var heat: Color { dark ? Color(red: 1, green: 0.50, blue: 0.37) : Color(red: 0.77, green: 0.23, blue: 0.12) }
    var tint: Color {
        guard celsius != nil else { return .secondary }
        let stops: [(Double, Double, Double)] = dark
            ? [(0.38,0.77,1), (0.32,0.83,0.83), (1,0.73,0.34), (1,0.50,0.37)]
            : [(0.05,0.44,0.77), (0.02,0.48,0.51), (0.68,0.40,0.06), (0.77,0.23,0.12)]
        let position = progress * 3, index = min(2, Int(position)), t = position - Double(index)
        let a = stops[index], b = stops[index + 1]
        return Color(red: a.0 + (b.0-a.0)*t, green: a.1 + (b.1-a.1)*t, blue: a.2 + (b.2-a.2)*t)
    }
    var gradient: LinearGradient { LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

struct ThermalScale: View {
    var celsius: Double?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = ThermalPalette(celsius: celsius, dark: scheme == .dark)
        HStack(spacing: 10) {
            Image(systemName: "snowflake").foregroundStyle(palette.ice)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [palette.ice, .cyan, .orange, palette.heat], startPoint: .leading, endPoint: .trailing)).opacity(0.45).frame(height: 4)
                    if celsius != nil {
                        Circle().fill(palette.tint).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                            .offset(x: max(0, geometry.size.width - 9) * palette.progress)
                    }
                }.frame(height: geometry.size.height)
            }.frame(height: 16)
            Image(systemName: "thermometer.high").foregroundStyle(palette.heat)
        }.font(.system(size: 14)).frame(width: 226).accessibilityHidden(true)
    }
}

struct Rotor: View {
    var speed: Double
    var temperature: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = ThermalPalette(celsius: temperature, dark: scheme == .dark)
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || speed == 0)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120) * (speed > 4000 ? 140 : 50)
            ZStack {
                Circle().fill(.linearGradient(colors: [.gray.opacity(0.13), .gray.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().stroke(.gray.opacity(0.2), lineWidth: 1).padding(6)
                ZStack {
                    ForEach(0..<32) { i in
                        Capsule().fill(.linearGradient(colors: [.gray.opacity(0.65), .gray.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 15, height: 74).rotationEffect(.degrees(32)).offset(y: -55).rotationEffect(.degrees(Double(i) * 11.25))
                    }
                }.rotationEffect(.degrees(angle))
                Circle().fill(scheme == .dark ? Color(white: 0.16) : Color(white: 0.94)).frame(width: 76, height: 76)
                    .overlay(Circle().stroke(.gray.opacity(0.2)))
                Circle().fill(palette.gradient).opacity(temperature == nil ? 0 : 0.13).frame(width: 74, height: 74)
                Image(systemName: temperature == nil ? "wind" : (temperature! < 60 ? (NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: nil) == nil ? "snowflake" : "mountain.2.fill") : "thermometer.medium"))
                    .font(.system(size: 25, weight: .light)).foregroundStyle(palette.gradient)
            }
        }.frame(width: 210, height: 210).accessibilityHidden(true)
    }
}

struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: FanModel
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var scheme
    private var coolingText: String {
        guard let reading = model.temperature else { return "Temperature unavailable" }
        guard model.mode == "Max", let baseline = model.maxBaseline, let delta = reading.change(since: baseline) else { return "" }
        let change = Int(delta.rounded())
        return change == 0 ? "0°C since Max" : "\(change < 0 ? "↓" : "↑") \(abs(change))°C since Max"
    }
    var body: some View {
        let palette = ThermalPalette(celsius: model.temperature?.celsius, dark: scheme == .dark)
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "wind").foregroundStyle(Color.accentColor)
                Text("Gust").font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    Divider()
                    Button("Quit Gust") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Appearance and settings")
            }
            Rotor(speed: model.fresh ? (model.fans.first?.actual ?? 0) : 0, temperature: model.temperature?.celsius)
            VStack(spacing: 7) {
                HStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text(model.temperature.map { "\(Int($0.celsius.rounded()))°C" } ?? "—")
                            .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(palette.gradient)
                        Text(model.temperature?.source ?? "Chip").font(.system(size: 13)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .help(model.temperature?.source == "CPU proximity" ? "Temperature near the CPU; not its die temperature." : "Hottest available CPU or GPU sensor. Not the temperature of the case.")
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1, height: 39)
                    VStack(spacing: 4) {
                        Text(model.fresh ? model.fans.first.map { String(Int($0.actual)) } ?? "—" : "—")
                            .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("RPM").font(.system(size: 13)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
                }
                ThermalScale(celsius: model.temperature?.celsius).padding(.top, 6)
                Text(coolingText).font(.system(size: 13)).foregroundStyle(.secondary).frame(height: 17)
            }
            HStack(spacing: 6) {
                ForEach(["Auto", "Min", "Max"], id: \.self) { mode in
                    Button { model.choose(mode) } label: {
                        HStack(spacing: 4) {
                            Text(mode)
                        }.frame(maxWidth: .infinity).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .background(model.mode == mode ? Color.accentColor : Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundColor(model.mode == mode ? .white : .primary)
                    .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                }
            }.disabled(model.busy || model.fans.isEmpty || !model.fresh)
            VStack(spacing: 8) {
                Slider(value: $model.slider, in: 0...1, onEditingChanged: { editing in
                    if !editing { model.choose("Manual", fraction: model.slider) }
                }).accessibilityLabel("Manual fan speed").disabled(model.busy || model.fans.isEmpty || !model.fresh)
                HStack { Text("Minimum"); Spacer(); Text("Maximum") }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            DisclosureGroup("Fan details", isExpanded: $model.showDetails) {
                VStack(spacing: 9) {
                    ForEach(model.fans) { fan in
                        HStack {
                            Text(fan.name)
                            Spacer()
                            Text(model.fresh ? "\(Int(fan.actual)) RPM" : "Unavailable").monospacedDigit()
                        }
                        .help("Hardware range: \(Int(fan.minimum))–\(Int(fan.maximum)) RPM")
                    }
                }.padding(.top, 8)
            }.disclosureGroupStyle(FullRowDisclosureStyle())
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if model.busy || model.fans.isEmpty || model.mode == "External" || model.mode == "Checking" {
                HStack(spacing: 6) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.busy ? "Connecting…" : model.fans.isEmpty ? "No controllable fans detected" : model.mode == "External" ? "Controlled by another app" : "Checking fan state…")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
        }
        .padding(24).frame(width: 336)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 0.43, green: 0.39, blue: 0.88))
        .accentColor(Color(red: 0.43, green: 0.39, blue: 0.88))
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = FanModel()
    var window: NSWindow!
    var item: NSStatusItem!
    private let presetMenu = NSMenu(title: "Gust")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 336, height: 590), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Gust"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: nil)
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.action = #selector(statusItemClicked); button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Gust fan control")
            button.setAccessibilityHelp("Press to open Gust. Right-click or Control-click for fan presets and Quit.")
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Show fan presets", target: self, selector: #selector(accessibilityShowPresets))
            ])
        }
        presetMenu.delegate = self
        presetMenu.autoenablesItems = false
        let heading = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        presetMenu.addItem(heading)
        for mode in ["Auto", "Min", "Max"] {
            let entry = NSMenuItem(title: mode, action: #selector(choosePreset(_:)), keyEquivalent: "")
            entry.target = self
            entry.toolTip = mode == "Auto" ? "Let macOS manage fan speed" : mode == "Min" ? "Set all fans to their hardware minimum" : "Set all fans to their hardware maximum"
            presetMenu.addItem(entry)
        }
        presetMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Gust", action: #selector(quitGust), keyEquivalent: "q")
        quit.target = self
        presetMenu.addItem(quit)
        model.statusChanged = { [weak self] in self?.updateStatusItem() }
        model.actionFailed = { [weak self] in self?.show() }
        updateStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        show()
    }
    private func updateStatusItem() {
        guard let button = item.button else { return }
        let rpm = model.fresh ? model.fans.first.map { Int($0.actual) } : nil
        button.title = rpm.map { " \($0) rpm" } ?? " — rpm"
        let reading = rpm.map { "\($0) revolutions per minute" } ?? (model.fresh && model.fans.isEmpty ? "No fans detected" : "Fan speed unavailable")
        button.setAccessibilityValue("\(reading), \(model.mode)\(model.busy ? ", applying preset" : "")")
        let temperature = model.temperature.map { " · \(Int($0.celsius.rounded()))°C" } ?? ""
        button.toolTip = "Gust · \(model.mode)\(temperature)\n\(model.fans.count > 1 ? "Fan 1 speed. " : "")Right-click for presets."
        updatePresetMenu()
    }
    private func updatePresetMenu() {
        for entry in presetMenu.items where ["Auto", "Min", "Max"].contains(entry.title) {
            entry.state = model.mode == entry.title ? .on : .off
            entry.isEnabled = entry.title == "Auto" || (!model.busy && model.fresh && !model.fans.isEmpty)
        }
    }
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showPresets()
        } else { toggle() }
    }
    private func showPresets() {
        updatePresetMenu()
        item.menu = presetMenu
        item.button?.performClick(nil)
        item.menu = nil
    }
    @objc private func accessibilityShowPresets() -> Bool { showPresets(); return true }
    func menuNeedsUpdate(_ menu: NSMenu) { updatePresetMenu() }
    @objc private func choosePreset(_ sender: NSMenuItem) {
        guard sender.isEnabled else { return }
        model.choose(sender.title)
    }
    @objc private func quitGust() { NSApp.terminate(nil) }
    @objc func toggle() { if window.isVisible { window.orderOut(nil) } else { show() } }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func willSleep() { model.choose("Auto") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.choose("Auto"); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.shutdown { sender.reply(toApplicationShouldTerminate: true) }; return .terminateLater
    }
}

func hardwareTest() throws {
    let controller = FanController(smc: try AppleSMC())
    var report: [[String: Any]] = []
    func sample(_ label: String) throws {
        let fans = try controller.fans()
        report.append(["stage": label, "fans": try JSONSerialization.jsonObject(with: JSONEncoder().encode(fans))])
        print("\(label): " + fans.map { "fan \($0.id) \(Int($0.actual)) RPM target \(Int($0.target)) manual \($0.manual)" }.joined(separator: "; "))
    }
    try sample("baseline")
    try authorizeHelper()
    defer { _ = try? HelperClient.request("quit") }
    for (command, label, seconds) in [("set 1", "max", 10), ("set 0", "min", 8), ("set 0.5", "manual", 8)] {
        _ = try HelperClient.request(command)
        for _ in 0..<seconds { Thread.sleep(forTimeInterval: 1); _ = try HelperClient.request("ping") }
        try sample(label)
        let fans = try controller.fans()
        guard fans.allSatisfy({ $0.manual && abs($0.actual - $0.target) < max(350, $0.maximum * 0.1) }) else {
            throw GustError("Hardware did not converge to \(label) RPM.")
        }
    }
    _ = try HelperClient.request("auto"); try sample("auto")
    guard try controller.fans().allSatisfy({ !$0.manual }) else { throw GustError("Auto reset failed") }
    _ = try HelperClient.request("set 1")
    Thread.sleep(forTimeInterval: 8)
    try sample("watchdog")
    guard try controller.fans().allSatisfy({ !$0.manual }) else { throw GustError("Watchdog reset failed") }
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    if let path = ProcessInfo.processInfo.environment["DRAFT_TEST_REPORT"] { try data.write(to: URL(fileURLWithPath: path)) }
    print("PASS: Max, Min, Manual, Auto, and heartbeat-loss restoration")
}

if CommandLine.arguments.contains("--hardware-test") {
    do { try hardwareTest(); exit(0) } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--temperature-probe") {
    do {
        let reader = TemperatureReader(smc: try AppleSMC())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(reader.read()), encoding: .utf8)!)
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
