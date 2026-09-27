<p align="center"><img src="docs/icon.png" width="128" alt="Gust icon"></p>

<h1 align="center">Gust</h1>

<p align="center">Free, open-source fan control for Macs.<br>Lock your fans to max, min, or anything in between — right from the menu bar.</p>

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
- Fan icon and live RPM in the menu bar; right-click for Auto, Min, Max, and Quit
- Live chip temperature, thermal colors, and cooling progress during Max
- Individual fan readings inside an easy-to-click Fan details row
- Light / dark / system appearance
- Fails safe: control goes back to macOS whenever you pick Auto, quit, or the app stops responding

## Install

1. Download `Gust.dmg` from [Releases](https://github.com/thecmdrunner/gust/releases/latest), open it, drag **Gust** into Applications.
2. Gust isn't notarized yet. On first launch macOS will block it — open **System Settings → Privacy & Security** and click **Open Anyway**.
3. The first manual preset in an app session asks for administrator permission to start the helper.

**Updating from 1.0.x:** quit the old Gust before replacing it. Version 1.1 automatically retires the old LaunchDaemon when you next authorize manual control.

Requires macOS 14+ on a Mac with fans. Universal Apple Silicon / Intel build; physically tested on an M4 Pro MacBook Pro. Intel and other models have not been physically verified.

**Uninstall:** quit Gust and delete Gust.app. The 1.1 helper exits with the app; no persistent service is installed. If you never authorized 1.1 and still have the 1.0.x helper, its original cleanup is:

```sh
sudo launchctl bootout system/com.thecmdrunner.gust.helper
sudo rm /Library/PrivilegedHelperTools/com.thecmdrunner.gust.helper /Library/LaunchDaemons/com.thecmdrunner.gust.helper.plist
```

## How it works

The SwiftUI app reads fan RPM and supported CPU/GPU temperature sensors through AppleSMC. Temperature is the hottest available chip sensor, with a labeled CPU proximity fallback on supported Intel Macs. It is not case temperature. The menu bar shows the first fan's RPM, matching the main panel.

A small root helper handles writes. Each app session gets a private socket under `/var/run/gust-fan/`; the helper validates both the connecting user and app process. A root-owned lock prevents competing Gust sessions. Commands are restricted to validated fan operations within the hardware's reported limits.

The helper restores Auto on quit, lost heartbeat (six seconds), parent exit, or serious thermal pressure. Closing the app window and system sleep also request Auto. Menu tracking keeps the heartbeat running. A failed menu preset opens the panel to explain the error.

The app is ad-hoc signed, not notarized. No Developer ID certificate is included. MIT and third-party notices are bundled in the app.

## Build from source

Requires macOS, the Swift toolchain (Xcode or Command Line Tools), and Bun. Installer packaging also needs uv or pipx.

```sh
git clone https://github.com/thecmdrunner/gust && cd gust
./app/build.sh                   # universal → app/build/Gust.app
bun app/scripts/test.ts          # native regression tests
./app/make-dmg.sh                # original illustrated installer → app/build/Gust.dmg
open app/build/Gust.app
```

Read-only diagnostics:

```sh
app/build/Gust.app/Contents/Helpers/GustHelper --probe
app/build/Gust.app/Contents/MacOS/Gust --temperature-probe
```

The website lives in [`web/`](web) (Next.js): `cd web && pnpm install && bun run dev`.

CI builds/tests on main and pull requests. Version tags publish `Gust.dmg` and its SHA-256 checksum after app and website checks pass. The website's existing latest-release link automatically serves the new installer.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Reports from Macs other than the M4 Pro are especially useful.

## Disclaimer

Gust changes hardware fan behaviour. It never goes outside the limits your Mac reports, and it hands control back to macOS on exit, but you use it at your own risk.

## License

[MIT](LICENSE) © thecmdrunner
