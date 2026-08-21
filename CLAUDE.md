# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AndroidRemote casts an iPhone's screen to a Google TV / Chromecast over LAN via WebRTC, with no cloud relay and no TV app install required. It's a monorepo with three independently-buildable pieces plus a Mac-only dev/test tool:

- `ios/` — SwiftUI sender app + ReplayKit Broadcast Upload Extension (the primary client)
- `cast-receiver/` — Google Cast custom web receiver (primary TV target, hosted as static HTML/JS)
- `android-tv/` — optional native Kotlin/Compose TV receiver (secondary path, higher performance)
- `tools/` — Mac LAN test relay used to develop/test before a Cast App ID is registered

There are no automated test suites in this repo yet (no XCTest target, no Android instrumentation/unit tests beyond JUnit stubs, no JS tests). Verification is manual/on-device — see "Testing on LAN" below.

## Commands

### iOS

```bash
# Regenerate AndroidRemote.xcodeproj after editing ios/project.yml (uses vendored XcodeGen, no install needed)
cd ios && ../tools/xcodegen-bin/xcodegen/bin/xcodegen generate
# or
./ios/generate-xcodeproj.sh

# Open and build
open ios/AndroidRemote.xcodeproj
```

- Dependencies resolve via Swift Package Manager (WebRTC from `stasel/WebRTC`, Cast SDK from `castlabs/google-cast-spm`) — no CocoaPods. If Xcode doesn't fetch automatically: File → Packages → Resolve Package Versions.
- Must run on a **physical iPhone** — ReplayKit broadcast does not work in the Simulator.
- Set the signing **Team** on both the `AndroidRemote` and `BroadcastExtension` targets before building for device.
- Both targets share the App Group `group.com.androidremote.shared` (used for session handoff between the main app and the extension — do not change this without updating both targets' entitlements).

### Android TV

No `gradlew` wrapper is committed — open `android-tv/` in Android Studio and let it sync/generate the wrapper, or build with a locally installed Gradle matching the AGP/Kotlin versions in `android-tv/build.gradle.kts` (AGP 8.7.3, Kotlin 2.0.21, compileSdk 35).

### Cast receiver / LAN test relay

```bash
# Static file serving for Cast dev (register this URL, not localhost, in the Cast console)
cd cast-receiver && python3 -m http.server 8080 --bind 0.0.0.0

# Mac relay for testing without a registered Cast App ID (signaling relay + static files)
python3 tools/lan-test-server.py           # default port 8080
./tools/start-lan-test-server.sh           # same, plus prints the macOS firewall allow command for this Python binary
```

The relay exists because the iPhone cannot reliably accept inbound LAN TCP, so ARCP signaling is relayed through the Mac instead of running on-device in test mode. WebRTC media itself is still peer-to-peer.

**`cast-receiver/` is only live on the TV once it's on `main`.** GitHub Pages (`https://learnerbing.github.io/AndroidRemote/`) auto-deploys `cast-receiver/` on push to `main` — a feature branch's changes to `index.html`/`test-receiver.html` never reach the TV until merged. This bit an entire multi-session debugging effort: weeks of receiver-side fixes sat on a feature branch while the TV kept loading a stale `index.html`, and every symptom got misread as a signaling bug instead. After any `cast-receiver/` change, merge (or fast-forward) into `main`, push, and confirm the `Deploy Cast Receiver` GitHub Actions workflow succeeded (`gh run list --workflow="Deploy Cast Receiver" --limit 1`) before trusting an on-device test against it. iOS-only changes don't need this — only `cast-receiver/`.

## Architecture

### The two signaling paths — don't conflate them

1. **Cast path (primary, V1 target)**: iPhone main app uses the Google Cast SDK to discover/launch the receiver and exchange custom messages (`urn:x-cast:com.androidremote.signaling`: `pairing_code`, `session_prepare`, `status`) directly with the TV. Once paired, the **Broadcast Extension** (not the main app) runs an HTTP signaling server (`ExtensionSignalingServer`, port `8766`) on the iPhone; the Cast web receiver polls/posts SDP and ICE against it. See `ios/Shared/ExtensionSignalingServer.swift` and the ARCP extension endpoints in `docs/ARCHITECTURE.md`.
2. **Native Android TV path (optional/secondary)**: uses mDNS (`_androidremote._tcp`) for discovery and runs its own HTTP signaling server on the TV (port `8765`, see `SignalingServer.kt`), per the base ARCP protocol.
3. **LAN test mode**: neither of the above — `tools/lan-test-server.py` on the Mac relays signaling between the iPhone and a browser tab (`cast-receiver/test-receiver.html`) so the WebRTC pipeline can be exercised before a Cast App ID is registered.

All three paths converge on the same WebRTC media transport (H.264, STUN-only ICE, no TURN).

### Why the extension owns WebRTC, not the main app

iOS system-wide screen capture requires a Broadcast Upload Extension, which runs under a strict ~50MB memory ceiling and is suspended independently of the main app's lifecycle. The extension therefore owns the WebRTC peer connection, the encoder, and (in Cast mode) the signaling server; the main app only handles Cast discovery/pairing and hands off session config via the shared App Group container (`ios/Shared/SessionStore.swift`). This is "Pattern 2" in `docs/ARCHITECTURE.md` — don't move WebRTC logic into the main app, it will get killed when backgrounded.

Hard constraints on the extension: H.264 hardware encoding only (VideoToolbox) — VP8 software encode OOMs the extension — capped around 720p@30fps.

### Clean Architecture layering (both iOS and Android TV)

Both clients follow the same three-layer split:
- **Presentation** — SwiftUI Views/ViewModels (`ios/AndroidRemote/Presentation/`) or Compose screens/ViewModel (`android-tv/.../presentation/`)
- **Domain** — entities, repository protocols, use cases (`ios/AndroidRemote/Domain/`, `android-tv/.../domain/`)
- **Data** — repository implementations, WebRTC, mDNS/Cast discovery, signaling (`ios/AndroidRemote/Data/`, `android-tv/.../data/`)

Code shared between the iOS main app and the Broadcast Extension targets (both link against it in `project.yml`) lives in `ios/Shared/`: ARCP wire models, the signaling client/server, `WebRtcBroadcastEngine`, `SessionStore`, ReplayKit audio capture (`ReplayKitAudioDevice`/`ReplayKitAudioRingBuffer`). Changes here affect both targets — check both build.

### Protocol reference

The ARCP HTTP signaling protocol (V1 endpoints: `/pair`, `/sdp`, `/ice`, `/status`; Cast-path extensions: `/sdp/offer`, ICE side params; V2 planned endpoints for media/remote) is fully specified in `docs/ARCHITECTURE.md`. `docs/ROADMAP.md` has the V1/V2 feature scope and phase status — check it before assuming a feature (photos, video, IPTV, YouTube, remote control) is implemented; as of now only V1 screen mirroring exists, V2 is planned/stubbed only.

### Versioning discipline

V1 is screen-mirroring only. V2 (photos/video/IPTV/YouTube/remote) reuses the same discovery/pairing/session layer and adds new cast modes on top of ARCP rather than a new protocol — when extending toward V2 features, extend the existing signaling bus and mode-router pattern described in `docs/ROADMAP.md` rather than introducing a parallel mechanism.

### Debugging on-device — there is no reliable remote debugger for the TV

Chrome remote debugging (`chrome://inspect`, `<tv-ip>:9222`) requires Cast Developer Mode, which is a *separate* thing from registering the device's serial number in the Cast SDK Developer Console (the latter only authorizes loading the unpublished receiver app, and is likely already done — check `cast.google.com/publish` → Devices before assuming debug access needs setting up from scratch). Getting Developer Mode's debug port actually open (Google Home app → device → tap Serial Number 7× → toggle → power-cycle the TV) has not been reliably achieved in this project's history. **Default to the on-screen debug log in `cast-receiver/index.html`/`test-receiver.html`** (`#debug-log`, written via a `logLine()` helper) as the primary way to see what the receiver is doing — it's what actually diagnosed the real bugs below. When adding receiver-side logic, log through `logLine()`, not just `console.log`, or a TV-side failure is invisible again.

The iOS side has an equivalent split: the **Broadcast Extension is a separate OS process** from the main app. `xcrun devicectl device process launch --console com.androidremote.app` only bridges the *main app's* stdout — extension logs (everything in `WebRtcBroadcastEngine`/`ExtensionSignalingServer`) need Xcode's own console or Console.app while the extension is running. A given bug may live in either process — check both `ARLog` streams, don't assume the extension's log alone tells the whole story (e.g. `sendSessionPrepare` runs in the main app; the SDP/ICE HTTP traffic it's negotiating runs in the extension).

### Hard-won bugs worth knowing before touching this code again

- **`ExtensionSignalingServer.swift`'s hand-rolled HTTP parsing**: Swift treats `"\r\n"` as a single `Character` (grapheme cluster), not two — `someString.split(separator: "\n")` silently finds *no* split points in real CRLF-terminated HTTP text, returning the whole thing as one element. This caused `Content-Length` parsing to always return `0`, which was misdiagnosed across several sessions/commits as concurrency/flakiness in the embedded server before the actual cause was found. Split on `"\r\n"` as its own `Character` literal instead (valid Swift — CRLF is a recognized grapheme-cluster exception).
- **`cast-receiver/index.html`'s Cast custom-message listener**: `context.start({ customNamespaces: { [CUSTOM_CHANNEL]: cast.framework.system.MessageType.JSON } })` tells the CAF receiver SDK to parse incoming messages *for you* — `event.data` in `addCustomMessageListener` arrives as a plain object, not a JSON string. Calling `JSON.parse(event.data)` again coerces the object via `toString()` first (`"[object Object]"`), which then fails to parse — silently, for every message, for this project's entire history, which is why `session_prepare` (sender→receiver) never worked while `pairing_code` (receiver→sender, decoded natively on iOS, unaffected) always did. Guard with `typeof event.data === 'string' ? JSON.parse(event.data) : event.data`.
- **`GCKCastOptions.suspendSessionsWhenBackgrounded` defaults to `YES`** in the Cast SDK. This app's whole architecture (extension keeps streaming independent of the main app, see above) depends on the Cast *session* surviving backgrounding too — left at the default, backgrounding the main app suspends the Cast session, fires `SENDER_DISCONNECTED` on the receiver, and (unless the receiver is written to tolerate it) kills a perfectly healthy WebRTC stream. Set to `NO` in `CastBootstrap.swift`; kept intentionally. The receiver's `SENDER_DISCONNECTED` handler also deliberately does *not* tear down an already-`connected` `RTCPeerConnection` for the same reason.
- **`UIApplication.isIdleTimerDisabled`** must be toggled on while actively streaming (`CastViewModel`/`DirectTestViewModel`, tied to `connectionState == .streaming`) or iOS auto-locks the screen after the idle timeout mid-mirror.
- **Retry/poll loops must catch thrown errors, not just non-2xx responses.** `ObserveCastStatusUseCase.pollUntilConnected()` used to `try await` its HTTP call with no catch inside the loop — a `Connection refused` (expected on the very first poll, since the extension's signaling server doesn't exist until the user manually taps the system broadcast picker seconds later) threw straight out of the whole polling `Task`, silently killing it for good. Any polling loop here needs to treat a thrown network error the same as a "still waiting" response.
