# irc_client

Mobile IRC client built with Flutter (iOS-first, cross-platform friendly).

## Features
- Connect to `host:port` over TCP or TLS
- TLS modes: System, Insecure, or SHA‑1 fingerprint pinning
- IRC registration: `NICK` / `USER` automatically on connect
- Commands: `/nick`, `/user`, `/join`, `/part`, `/msg`, `/list`
- Channel picker and per‑channel message history
- Auto `PING`/`PONG` handling
- Image/GIF preview with safe rendering (no execution)
- Optional raw IRC line view
- Dark mode support
- Auto-reconnect after backgrounding
- Local notification on connection loss

## Quick Start
```bash
flutter pub get
flutter run
```

### Running in Release
```bash
flutter run --release
```
Use `--release` for full performance (optimized build, no debug banner).

### iOS 7‑Day Expiry (Free Apple Developer Account)
If you deploy to a physical iPhone with a free Apple Developer account,
the installed app and its signing profile typically expire after 7 days.
You’ll need to re‑install it after that period. This is an Apple limitation,
not specific to Flutter or this project.

## Usage
1. Open **Connection** tab.
2. Enter host/IP and port.
3. Enter Nick and User (required).
4. Choose TLS mode if needed.
5. Tap **Connect**.

## Commands
- `/nick <nickname>`
- `/user <username> [realname]`
- `/join <#channel>`
- `/part <#channel>`
- `/msg <target> <message>`
- `/list` (refresh channel list)

## Media Support
Direct image URLs (`.png`, `.jpg`, `.gif`, `.webp`) are displayed as previews.
Some common GIF links (Giphy/Tenor/Discord) are converted to direct media URLs when possible.
If a preview fails, you can open it in the browser.

## Notes on iOS Backgrounding
iOS suspends apps shortly after they go to the background. The app will attempt
to reconnect when returning to the foreground. Long‑lived background connections
are not guaranteed on iOS without special background modes (not used here).
