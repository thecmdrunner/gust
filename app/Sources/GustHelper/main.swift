import Foundation

// Root LaunchDaemon. Accepts one-line commands on a Unix socket:
//   version | status | auto | min | max | rpm <n>
// Manual modes are re-asserted every tick and dropped back to auto if the app stops checking in.

enum Mode: Equatable { case auto, min, max, rpm(Double) }

let heartbeatTimeout: TimeInterval = 15
var mode: Mode = .auto
var lastSeen = Date()
let queue = DispatchQueue(label: "gust.helper")

func log(_ s: String) { FileHandle.standardError.write("gust: \(s)\n".data(using: .utf8)!) }

func unlock() -> Bool {
    // Apple Silicon: Ftst=1 hands fan control over from thermalmonitord. F*Md may reject writes briefly after.
    if SMC.readUInt8("Ftst") != nil, SMC.readUInt8("Ftst") != 1 { SMC.write("Ftst", [1]) }
    for _ in 0..<40 {
        if (0..<Fans.count).allSatisfy({ SMC.readUInt8("F\($0)Md") == 1 || SMC.write("F\($0)Md", [1]) }) { return true }
        usleep(100_000)
    }
    return false
}

func restoreAuto() {
    for i in 0..<Fans.count { SMC.write("F\(i)Md", [0]) }
    if SMC.readUInt8("Ftst") != nil { SMC.write("Ftst", [0]) }
}

func apply() {
    if mode == .auto { return }
    guard unlock() else { log("unlock failed"); return }
    for fan in Fans.all() {
        let target: Double
        switch mode {
        case .auto: return
        case .min: target = fan.min
        case .max: target = fan.max
        case .rpm(let r): target = Swift.min(Swift.max(r, fan.min), fan.max)
        }
        if abs(fan.target - target) > 1 { SMC.writeFloat("F\(fan.index)Tg", Float(target)) }
    }
}

func setMode(_ m: Mode) {
    let was = mode
    mode = m
    if m == .auto { if was != .auto { restoreAuto() } } else { apply() }
}

func status() -> String {
    let m: String
    switch mode {
    case .auto: m = "auto"
    case .min: m = "min"
    case .max: m = "max"
    case .rpm(let r): m = "rpm \(Int(r))"
    }
    return "ok \(m)"
}

func handle(_ line: String) -> String {
    let parts = line.split(separator: " ")
    lastSeen = Date()
    switch parts.first {
    case "version": return "ok \(Gust.helperVersion)"
    case "status": return status()
    case "auto": setMode(.auto)
    case "min": setMode(.min)
    case "max": setMode(.max)
    case "rpm":
        guard parts.count == 2, let r = Double(parts[1]), r.isFinite else { return "err bad rpm" }
        setMode(.rpm(r))
    default: return "err unknown"
    }
    return status()
}

// MARK: socket

unlink(Gust.socketPath)
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { buf in
    Gust.socketPath.utf8CString.withUnsafeBytes { buf.copyMemory(from: $0) }
}
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard bound == 0, listen(fd, 8) == 0 else { log("bind failed: \(errno)"); exit(1) }
chmod(Gust.socketPath, 0o666)

let acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
acceptSource.setEventHandler {
    let c = accept(fd, nil, nil)
    guard c >= 0 else { return }
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var buf = [UInt8](repeating: 0, count: 128)
    let n = read(c, &buf, buf.count)
    if n > 0 {
        let line = String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = handle(line) + "\n"
        _ = reply.withCString { write(c, $0, strlen($0)) }
    }
    close(c)
}
acceptSource.resume()

let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now() + 2, repeating: 2)
timer.setEventHandler {
    if mode != .auto && Date().timeIntervalSince(lastSeen) > heartbeatTimeout {
        log("app went quiet, restoring auto")
        setMode(.auto)
    }
    apply()
}
timer.resume()

for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let s = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    s.setEventHandler { restoreAuto(); unlink(Gust.socketPath); exit(0) }
    s.resume()
    _ = Unmanaged.passRetained(s)
}

log("started, fans: \(Fans.count)")
dispatchMain()
