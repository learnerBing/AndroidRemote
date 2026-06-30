# AndroidRemote TV Receiver

Kotlin Android TV app — WebRTC receiver with mDNS discovery and local HTTP signaling.

## Open in Android Studio

1. Open `android-tv/` as project
2. Sync Gradle
3. Run on Android TV emulator or device (Leanback launcher)

## Architecture

Clean Architecture layers under `app/src/main/java/com/androidremote/tv/`:

- `domain/` — entities, repository protocols, use cases
- `data/` — signaling server, WebRTC, mDNS, settings, repository implementations
- `presentation/` — Compose for TV UI (Stitch V1 designs)

## UI (V1)

| Screen | Composable | Purpose |
|--------|------------|---------|
| Pairing | `PairingScreen` | 10-foot UI, huge 6-digit code, status line |
| Streaming | `StreamingScreen` | Fullscreen WebRTC + Live overlay + optional diagnostics |
| Settings | `SettingsScreen` | Device name, 720p/1080p, diagnostics toggle, About |

Navigation: `ReceiverScreen` routes Home (pairing/streaming) ↔ Settings. Settings blocked while streaming.

Design tokens: `TvColors` (`#0D1117`, `#58A6FF`, `#161B22`).

## Signaling Port

Default: `8765` (mDNS service `_androidremote._tcp`)
