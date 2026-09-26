# Gust

Fan control for Apple Silicon Macs. Menu bar app: **Auto** (macOS), **Min**, **Custom**, **Max**, live RPM.

## App (`app/`)

```sh
./app/build.sh          # → app/build/Gust.app (swiftc + clang, no Xcode needed)
```

- `Gust` — SwiftUI menu bar app. Reads RPM straight from the SMC (no root).
- `GustHelper` — root LaunchDaemon (`com.thecmdrunner.gust.helper`) that writes the fan keys. Installed on first manual mode via an admin prompt; listens on `/var/run/gust.sock`.
- Safety: helper hands control back to macOS when you pick Auto, quit the app, the app stops checking in for 15s, or the helper stops.
- Remove helper: trash icon in the panel.

SMC keys used: `Ftst` (unlock), `F<n>Md` (mode), `F<n>Tg` (target), `F<n>Ac/Mn/Mx` (actual/min/max).

## Site (`web/`)

Next.js. `bun install && bun dev`. Download served from `web/public/Gust.zip` — refresh it with:

```sh
./app/build.sh && ditto -c -k --keepParent app/build/Gust.app web/public/Gust.zip
```
