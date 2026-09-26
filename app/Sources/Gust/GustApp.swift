import AppKit
import SwiftUI

@main
struct GustApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var fans = FanController()
    @AppStorage("appearance") private var appearance = 0

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(fans)
                .onAppear { applyAppearance(appearance) }
                .onChange(of: appearance) { _, v in applyAppearance(v) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: fans.mode == .auto ? "fan" : "fan.fill")
                Text(fans.averageRPM.formatted()).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func applyAppearance(_ v: Int) {
        NSApp.appearance = v == 1 ? NSAppearance(named: .aqua) : v == 2 ? NSAppearance(named: .darkAqua) : nil
    }
}

struct PanelView: View {
    @EnvironmentObject var c: FanController
    @AppStorage("appearance") private var appearance = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Gust").font(.system(size: 15, weight: .semibold))
                Spacer()
                Circle().fill(c.mode == .auto ? Color.secondary.opacity(0.5) : Color.accentColor).frame(width: 7, height: 7)
                Text(c.mode == .auto ? "macOS" : "Manual").font(.caption).foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(c.fans, id: \.index) { FanRow(fan: $0) }
                if c.fans.isEmpty {
                    Text("No fans found").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }

            Picker("", selection: Binding(get: { c.mode }, set: { c.select($0) })) {
                ForEach(FanMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if c.mode == .custom {
                HStack {
                    Slider(value: $c.customRPM, in: c.minRPM...c.maxRPM) { editing in
                        if !editing { c.push() }
                    }
                    Text(Int(c.customRPM).formatted()).monospacedDigit().font(.caption).frame(width: 36, alignment: .trailing)
                }
            }

            if let e = c.error {
                Text(e).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 14) {
                Button { appearance = (appearance + 1) % 3 } label: {
                    Image(systemName: ["circle.lefthalf.filled", "sun.max", "moon"][appearance])
                }
                .help(["System", "Light", "Dark"][appearance])

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .help("Fans return to macOS")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 290)
    }
}

struct FanRow: View {
    let fan: FanInfo
    @StateObject private var spinner = Spinner()

    var body: some View {
        HStack(spacing: 12) {
            TimelineView(.animation) { t in
                Image(systemName: "fan.fill")
                    .font(.system(size: 26, weight: .light))
                    .rotationEffect(.degrees(spinner.angle(at: t.date, rpm: fan.rpm)))
            }
            .frame(width: 34, height: 34)
            .foregroundStyle(fan.forced ? Color.accentColor : .primary)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Int(fan.rpm).formatted())
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int(fan.rpm))
                    Text("rpm").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Fan \(fan.index + 1)").font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    let p = max(0, min(1, (fan.rpm - fan.min) / max(fan.max - fan.min, 1)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(fan.forced ? Color.accentColor : Color.primary.opacity(0.6))
                            .frame(width: max(4, g.size.width * p))
                            .animation(.smooth, value: p)
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

/// Accumulates rotation so the glyph speeds up/down smoothly instead of jumping.
final class Spinner: ObservableObject {
    private var angle = 0.0
    private var last: Date?

    func angle(at date: Date, rpm: Double) -> Double {
        let dt = last.map { min(date.timeIntervalSince($0), 0.1) } ?? 0
        last = date
        angle = (angle + dt * rpm / 60 * 360 * 0.02).truncatingRemainder(dividingBy: 360)
        return angle
    }
}
