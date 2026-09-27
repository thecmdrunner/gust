Gust 1.1.2 improves preset reliability when the app window is hidden.

- Max, Min, and manual presets check for an expired helper connection and reconnect before applying.
- Background heartbeats no longer depend on the UI run loop. Active overrides stay awake without preventing the Mac from sleeping.
- Slow firmware unlocks get enough time to finish instead of triggering a premature disconnect.
- The menu bar shows “Applying…” while a preset is in progress.
- Safety refusals remain visible; Auto and the six-second watchdog remain available.
- Installers now use the name `Gust-1.1.2-macos.dmg`. The website automatically finds the latest installer.

**Update:** Quit Gust, open `Gust-1.1.2-macos.dmg`, then drag Gust to Applications and choose Replace. If macOS blocks the app, use System Settings → Privacy & Security → Open Anyway. The original illustrated installer is unchanged.

Universal Apple Silicon / Intel, macOS 14+. Ad-hoc signed, not notarized.
