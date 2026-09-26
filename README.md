<p align="center"><img src="docs/icon.png" width="128" alt="Gust icon"></p>

<h1 align="center">Gust</h1>

<p align="center">Free, open-source fan control for Apple Silicon Macs.<br>Lock your fans to max, min, or anything in between — right from the menu bar.</p>

<p align="center">
  <a href="https://github.com/thecmdrunner/gust/releases/latest"><b>Download</b></a> ·
  <a href="https://gust-taupe.vercel.app">Website</a> ·
  <a href="LICENSE">MIT License</a>
</p>

---

## Features

- **Auto** — macOS stays in charge (default)
- **Min** / **Max** — lock every fan to its minimum or maximum RPM
- **Custom** — pick any RPM with a slider
- Live RPM per fan, in the menu bar and the panel
- Light / dark / system appearance, open at login
- Fails safe: control goes back to macOS whenever you pick Auto, quit, or the app stops responding

## Install

1. Download `Gust.zip` from [Releases](https://github.com/thecmdrunner/gust/releases/latest), unzip, move **Gust.app** to Applications.
2. Gust isn't notarized yet. On first launch macOS will block it — open **System Settings → Privacy & Security** and click **Open Anyway**.
3. The first time you pick a manual mode, Gust asks for your password once to install its helper.

Requires macOS 14+ on an Apple Silicon Mac with fans (MacBook Pro, Mac mini, Mac Studio…). Tested on an M4 Pro MacBook Pro.

**Uninstall:** click the trash icon in the panel (removes the helper), then delete Gust.app.

## How it works

Fan speed lives in the System Management Controller (SMC). Reading it is unprivileged, writing it needs root, so Gust is two pieces:

| Piece | What it does |
| --- | --- |
| `Gust.app` | SwiftUI menu bar app. Reads RPM directly from the SMC. |
| `GustHelper` | Tiny root LaunchDaemon (`com.thecmdrunner.gust.helper`) that writes fan keys. Listens on `/var/run/gust.sock`, accepts only `auto`, `min`, `max`, `rpm <n>`, `status`, `version`. RPM is clamped to each fan's hardware min/max. |

The helper re-asserts manual modes every 2s and restores Auto if the app goes quiet for 15s or the helper is stopped.

SMC keys: `Ftst` (unlock manual control on Apple Silicon), `F<n>Md` (mode), `F<n>Tg` (target), `F<n>Ac` / `F<n>Mn` / `F<n>Mx` (actual / min / max).

## Build from source

No Xcode project, no dependencies — just the Swift toolchain (Xcode or Command Line Tools).

```sh
git clone https://github.com/thecmdrunner/gust && cd gust
./app/build.sh            # → app/build/Gust.app
open app/build/Gust.app
```

Debug helpers:

```sh
swiftc -I app/Sources/CSMC/include app/Sources/smcprobe/main.swift app/build/smc.o -framework IOKit -o smcprobe
./smcprobe list                        # dump all fan SMC keys
echo status | nc -U /var/run/gust.sock # talk to the helper
GUST_WINDOW=1 app/build/Gust.app/Contents/MacOS/Gust   # panel in a normal window
```

The website lives in [`web/`](web) (Next.js): `cd web && bun install && bun dev`.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Reports from Macs other than the M4 Pro are especially useful.

## Disclaimer

Gust changes hardware fan behaviour. It never goes outside the limits your Mac reports, and it hands control back to macOS on exit, but you use it at your own risk.

## License

[MIT](LICENSE) © thecmdrunner
