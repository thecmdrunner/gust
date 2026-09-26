import AppKit
import ServiceManagement
import Foundation

enum FanMode: String, CaseIterable, Identifiable {
    case auto, min, custom, max
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto"
        case .min: "Min"
        case .custom: "Custom"
        case .max: "Max"
        }
    }
}

@MainActor
final class FanController: ObservableObject {
    @Published var fans: [FanInfo] = []
    @Published var mode: FanMode = .auto
    @Published var customRPM: Double = UserDefaults.standard.object(forKey: "customRPM") as? Double ?? 3000 {
        didSet { UserDefaults.standard.set(customRPM, forKey: "customRPM") }
    }
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { try? openAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }
    @Published var helperReady = false
    @Published var error: String?

    var averageRPM: Int { fans.isEmpty ? 0 : Int(fans.map(\.rpm).reduce(0, +) / Double(fans.count)) }
    var minRPM: Double { fans.map(\.min).min() ?? 1000 }
    var maxRPM: Double { fans.map(\.max).max() ?? 6000 }

    static weak var shared: FanController?
    private var pollTimer: Timer?
    private var beatTimer: Timer?

    init() {
        refresh()
        Self.shared = self
        helperReady = HelperClient.send("version") == "ok \(Gust.helperVersion)"
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        beatTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            _ = HelperClient.send("auto")
        }
    }

    func refresh() {
        let now = Fans.all()
        if now != fans { fans = now }
    }

    func select(_ new: FanMode) {
        error = nil
        if new != .auto && !helperReady {
            do {
                try HelperInstaller.install()
                helperReady = waitForHelper()
            } catch {
                self.error = error.localizedDescription
                return
            }
            guard helperReady else { error = "Helper didn’t start"; return }
        }
        mode = new
        push()
    }

    func push() {
        guard helperReady || mode == .auto else { return }
        let reply = HelperClient.send(command)
        if reply == nil, mode != .auto { error = "Helper unreachable"; helperReady = false; mode = .auto }
    }

    func uninstallHelper() {
        _ = HelperClient.send("auto")
        mode = .auto
        try? HelperInstaller.uninstall()
        helperReady = false
    }

    private var command: String {
        switch mode {
        case .auto: "auto"
        case .min: "min"
        case .max: "max"
        case .custom: "rpm \(Int(customRPM))"
        }
    }

    private func heartbeat() {
        if mode != .auto { push() }
    }

    private func waitForHelper() -> Bool {
        for _ in 0..<30 {
            if HelperClient.send("version") == "ok \(Gust.helperVersion)" { return true }
            usleep(100_000)
        }
        return false
    }
}

enum HelperClient {
    /// One request/response over the helper's Unix socket. Returns nil if the helper isn't running.
    static func send(_ line: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            Gust.socketPath.utf8CString.withUnsafeBytes { buf.copyMemory(from: $0) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { return nil }
        let msg = line + "\n"
        _ = msg.withCString { write(fd, $0, strlen($0)) }
        var buf = [UInt8](repeating: 0, count: 128)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HelperInstaller {
    static let binary = "/Library/PrivilegedHelperTools/\(Gust.helperLabel)"
    static let plist = "/Library/LaunchDaemons/\(Gust.helperLabel).plist"

    static func install() throws {
        guard let src = Bundle.main.url(forAuxiliaryExecutable: "GustHelper")?.path else {
            throw NSError(domain: "Gust", code: 1, userInfo: [NSLocalizedDescriptionKey: "Helper missing from app bundle"])
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(Gust.helperLabel).plist")
        let dict: [String: Any] = ["Label": Gust.helperLabel, "ProgramArguments": [binary], "RunAtLoad": true, "KeepAlive": true]
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: tmp)
        try runAsAdmin("""
        launchctl bootout system/\(Gust.helperLabel) 2>/dev/null; \
        mkdir -p /Library/PrivilegedHelperTools && \
        cp \(q(src)) \(q(binary)) && chown root:wheel \(q(binary)) && chmod 755 \(q(binary)) && \
        cp \(q(tmp.path)) \(q(plist)) && chown root:wheel \(q(plist)) && chmod 644 \(q(plist)) && \
        launchctl bootstrap system \(q(plist))
        """)
    }

    static func uninstall() throws {
        try runAsAdmin("launchctl bootout system/\(Gust.helperLabel) 2>/dev/null; rm -f \(q(binary)) \(q(plist))")
    }

    private static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func runAsAdmin(_ shell: String) throws {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges with prompt \"Gust needs to install a small helper to control your fans.\"")
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
        if let err {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "Install failed"
            throw NSError(domain: "Gust", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
