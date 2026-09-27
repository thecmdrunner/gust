# Gust 1.1 validation

On Mac16,7 (M4 Pro), universal arm64/x86_64 compilation and ad-hoc signature verification pass. All 18 native regression groups pass, covering fan bounds, restore/rollback, helper command validation, competing utilities, Intel key handling, temperature decoding, sensor loss, and cooling comparisons.

The integrated app launched with live chip temperature and RPM in Auto. Its window, thermal palette, and expanded click target come from the previously tested Gust implementation. That implementation was physically tested through Max, Min, custom, Auto, and heartbeat-loss recovery on this Mac. These hardware checks were not repeated for the repository migration.

The new menu-bar control uses a template fan symbol, monospaced RPM, native menu selection states, and an explicit accessibility label, value, help, and Show fan presets action. Left click opens the panel; right/Control-click opens presets. Telemetry and the helper heartbeat run in common run-loop modes to continue while a menu is open. Full end-to-end VoiceOver and right-click testing remains unverified: native UI automation timed out when addressing menu-bar-only controls.

The original DMG script, background, layout settings, and app icon are unchanged. The generated DMG passes hdiutil verification. Its mounted app reports 1.1.0, contains arm64 and x86_64 executables, passes code-signature verification, and has an Applications symlink. The background contains the original Privacy & Security → Open Anyway instructions.

The website production build and TypeScript checks pass. Website components, styles, imagery, and download URL are unchanged; only package-manager metadata/lockfile changed to pnpm. Its existing link targets the latest release's Gust.dmg.

Legacy helper migration runs only after administrator authorization for a manual preset. It stops the known 1.0.x LaunchDaemon and removes its two installed service files before starting the session helper. Migration has been code-reviewed but not exercised against an installed 1.0.x service on this machine. Intel and other Mac models remain physically unverified. The app is ad-hoc signed, not notarized.

## 1.1.1 fanless experience

18 core tests plus five model tests pass. The new model tests exercise confirmed zero fans with and without temperature data, initial checking, missing fan-count keys, recovery from read failure, and a physical fan stopped at zero RPM. They assert that fanless/unknown paths never request administrator authorization or write SMC data. Temperature can remain visible if the independent fan read fails.

The actual SwiftUI fanless component was rendered off-screen with explicit fixture readings in light and dark themes, plus the missing-temperature state. These are test fixtures, not live MacBook Air measurements. No preview mode or synthetic temperature data is shipped in the app. A physical MacBook Air was not available. The production website build passes.

## 1.1.2 hidden-window preset regression

Three red/green reproductions: a stopped-fan model with an expired helper returned the reported disconnect error on its next Max selection; suppressing the UI run loop prevented the old timer from sending heartbeats; and a supported slow firmware unlock consumed 8.6 seconds against the former eight-second client timeout. The injected transport uses the real FanModel command path; it does not simulate SMC writes on the host Mac.

The fixed suite covers reconnect-before-preset, independent background heartbeats, no reauthorization on a safety refusal, and Auto after a refusal. The firmware test checks that the transport budget covers supported arbitration/retry waits. The six-second helper watchdog remains unchanged. Full physical reproduction of the user's hidden-window scenario is not claimed; OS App Nap timing itself was not forced in the test.

Five download-route tests cover versioned names, legacy fallback, missing assets, API failures, and unexpected hosts. Universal compilation, native tests, website typechecking/build, and the preserved DMG packaging are verified for this release.
