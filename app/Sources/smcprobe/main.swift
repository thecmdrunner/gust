import CSMC
import Foundation

func show(_ k: String) {
    var v = SMCVal()
    let r = smc_read(k, &v)
    if r != 0 { print(k, "err", r); return }
    let type = withUnsafeBytes(of: v.type) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    let bytes = withUnsafeBytes(of: v.bytes) { Array($0.prefix(Int(v.size))) }
    var extra = ""
    if type == "flt ", bytes.count == 4 { extra = String(bytes.withUnsafeBytes { $0.load(as: Float.self) }) }
    print(k, type, bytes.map { String(format: "%02x", $0) }.joined(separator: " "), extra)
}

let args = CommandLine.arguments.dropFirst()
if args.first == "list" {
    let n = smc_key_count()
    print("keys:", n)
    var buf = [CChar](repeating: 0, count: 5)
    for i in 0..<n where smc_key_at(i, &buf) == 0 {
        let k = String(cString: buf)
        if k.hasPrefix("F") { show(k) }
    }
} else {
    args.forEach(show)
}
