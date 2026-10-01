# Nexora Teleport 2.0

Nexora Teleport is an iOS MapKit route/routine app with a persistent route engine, real device Live status, Daily Routines, recovery, privacy-first local storage, Live Activities and a Widget extension.

## Main screens

- **Today** — idle Live location, active-route progress, next routine, today's timeline and favorite places.
- **Map** — MapKit search, saved places, active route, real device location when no route is active, Standard/Hybrid/Satellite styles.
- **Routes** — route presets, custom speed, waypoints, MapKit alternatives, preview, health checks, random route pauses, GPX export, reverse and loop copies.
- **Routine** — weekday schedules, start-delay windows, destination stay times, multiple steps and exception days.
- **More** — History, Profiles, Status Center and Settings.

## Reliability

- Atomic JSON state writes with iOS Data Protection.
- Route checkpoints on every route update.
- Persistent routine target times so restart does not re-roll delays.
- Route watchdog / stale-heartbeat recovery.
- Resume from saved route/point.
- Emergency stop / kill switch.
- Background location only while an active route requires it.
- Idle Live mode can continue showing the real device location without creating a route.
- Battery modes and an automatic thermal guard.

## Extra features

- Favorite places and local notes.
- Profiles for routine sets, Battery Mode, Map style and idle Live behavior.
- History can be disabled completely.
- `.nexora.json` backup import/export.
- GPX export and GPX route import.
- Optional iCloud KVS backup service. Enable the iCloud Key-Value Store capability for the signing team if you want to use it.
- Live Activity / Dynamic Island for active routes.
- Widget extension with Today / Resume / Stop deep links.
- Privacy-safe diagnostics export excludes saved coordinates/place names.

## Xcode build

1. Open `NexoraTeleport.xcodeproj` in Xcode 16 or newer.
2. Select the **NexoraTeleport** target and choose your Development Team.
3. Change `com.nexora.teleport` to your own unique bundle identifier if necessary.
4. Select **NexoraTeleportWidgets** and use the same team. Its bundle identifier must remain a child identifier of the main app, for example `your.bundle.teleport.widgets`.
5. If you want iCloud backup, enable **iCloud > Key-value storage** in Signing & Capabilities for the main target. The rest of the app is local-only by default and does not require iCloud.
6. Build to an iPhone running iOS 17+.

The app requests `When In Use` first and can request `Always` for active background route sessions. Force-quitting an iOS app can stop normal background location execution; recovery state is preserved for the next launch.

## Location-output boundary

The included `AppOnlyLocationProvider` drives the in-app route engine. Public iOS APIs do not allow a normally signed app to replace the Core Location value supplied to unrelated apps. No third-party anti-detection or spoofing-bypass logic is included.
