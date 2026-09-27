# Gust 1.1 validation

On Mac16,7 (M4 Pro), universal arm64/x86_64 compilation and ad-hoc signature verification pass. All 18 native regression groups pass, covering fan bounds, restore/rollback, helper command validation, competing utilities, Intel key handling, temperature decoding, sensor loss, and cooling comparisons.

The integrated app launched with live chip temperature and RPM in Auto. Its window, thermal palette, and expanded click target come from the previously tested Gust implementation. That implementation was physically tested through Max, Min, custom, Auto, and heartbeat-loss recovery on this Mac. These hardware checks were not repeated for the repository migration.

The new menu-bar control uses a template fan symbol, monospaced RPM, native menu selection states, and an explicit accessibility label, value, help, and Show fan presets action. Left click opens the panel; right/Control-click opens presets. Telemetry and the helper heartbeat run in common run-loop modes to continue while a menu is open. Full end-to-end VoiceOver and right-click testing remains unverified: native UI automation timed out when addressing menu-bar-only controls.

The original DMG script, background, layout settings, and app icon are unchanged. The generated DMG passes hdiutil verification. Its mounted app reports 1.1.0, contains arm64 and x86_64 executables, passes code-signature verification, and has an Applications symlink. The background contains the original Privacy & Security → Open Anyway instructions.

The website production build and TypeScript checks pass. Website components, styles, imagery, and download URL are unchanged; only package-manager metadata/lockfile changed to pnpm. Its existing link targets the latest release's Gust.dmg.

Legacy helper migration runs only after administrator authorization for a manual preset. It stops the known 1.0.x LaunchDaemon and removes its two installed service files before starting the session helper. Migration has been code-reviewed but not exercised against an installed 1.0.x service on this machine. Intel and other Mac models remain physically unverified. The app is ad-hoc signed, not notarized.
