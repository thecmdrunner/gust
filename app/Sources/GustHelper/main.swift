import Foundation
import GustCore
import CSMC

func run() throws {
    let smc = try AppleSMC()
    let controller = FanController(smc: smc)
    let args = CommandLine.arguments
    if args.count == 2 && args[1] == "--probe" {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(controller.fans()), encoding: .utf8)!)
        return
    }
    guard args.count == 4, args[1] == "--serve", let uid = UInt32(args[2]), let pid = Int32(args[3]), geteuid() == 0 else {
        throw GustError("Usage: GustHelper --probe | --serve UID PID (administrator)")
    }
    gust_signals_install()
    let server = gust_server_open(uid, pid)
    guard server >= 0 else { throw GustError("Another Gust session is active, or the socket could not be created.") }
    defer { gust_server_close(server, uid, pid) }
    var lastContact = gust_uptime()
    var exiting = false
    var safetyMessage: String?
    while !exiting && gust_stopping() == 0 {
        let now = gust_uptime()
        if now - lastContact > 6 || kill(pid, 0) != 0 { break }
        let thermal = ProcessInfo.processInfo.thermalState
        if controller.hasOverride && (thermal == .serious || thermal == .critical) {
            do { try controller.restore(); safetyMessage = "Mac is hot. Returned to Auto." }
            catch { safetyMessage = "Mac is hot. Auto restore failed; retrying: \(error.localizedDescription)" }
        }
        var buffer = [CChar](repeating: 0, count: 128)
        let client = gust_server_next(server, uid, pid, &buffer, buffer.count)
        if client < 0 { continue }
        do {
            let command = try HelperCommand.parse(String(cString: buffer))
            switch command {
            case .ping:
                if let message = safetyMessage { throw GustError(message) }
                if controller.hasOverride, !(try controller.fans()).allSatisfy({ $0.manual }) {
                    try controller.restore(); throw GustError("macOS reclaimed fan control. Returned to Auto.")
                }
            case .auto: try controller.restore(); safetyMessage = nil
            case .quit: try controller.restore(); exiting = true
            case .set(let fraction):
                guard thermal != .serious && thermal != .critical else { throw GustError("Mac is hot. Keep Auto enabled.") }
                try controller.set(fraction: fraction); safetyMessage = nil
            }
            lastContact = gust_uptime()
            gust_server_reply(client, "OK")
        } catch {
            gust_server_reply(client, "ERR \(error.localizedDescription)")
        }
    }
    // Retry transient firmware failures; never silently claim successful restoration.
    for _ in 0..<20 {
        do { try controller.restore(); return }
        catch { fputs("Auto restore: \(error.localizedDescription)\n", stderr); Thread.sleep(forTimeInterval: 0.25) }
    }
    throw GustError("Could not restore Auto. Restart the Mac to reset fan control.")
}
do { try run() }
catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
