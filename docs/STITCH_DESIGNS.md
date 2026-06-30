# Stitch MCP — UI Design Briefs

Use these prompts with **Google Stitch MCP** once configured in Cursor.

## Enable Stitch in Cursor

Add to Cursor MCP settings (`~/.cursor/mcp.json` or project settings):

```json
{
  "mcpServers": {
    "stitch": {
      "url": "https://stitch.googleapis.com/mcp",
      "headers": {
        "X-Goog-Api-Key": "YOUR_API_KEY"
      }
    }
  }
}
```

Then restart Cursor. Tools available: `create_project`, `generate_screen_from_text`, `list_screens`, `get_screen`.

---

## Project: AndroidRemote

Create one Stitch project for both apps with shared design tokens.

### Design System

| Token | Value |
|-------|-------|
| Background | `#0D1117` |
| Surface | `#161B22` |
| Primary | `#58A6FF` |
| Text primary | `#FFFFFF` |
| Text secondary | `#8B949E` |
| Font | SF Pro / system sans |
| Corner radius | 12px (mobile), 8px (TV) |
| Style | Dark, minimal, couch-distance TV typography |

---

## Screen 1: iOS Sender — Home (MOBILE)

**Prompt for `generate_screen_from_text`:**

> Dark mode iOS screen mirroring app home screen. Title "AndroidRemote" with TV icon. Subtitle "Cast iPhone to Android TV". Section "Available TVs" with list cards showing TV name and checkmark when selected. Large 6-digit code input field with monospaced digits. Primary blue button "Start Casting". Small broadcast picker area at bottom labeled "Then start screen broadcast". Background #0D1117, accent #58A6FF, modern iOS 17 style, clean spacing.

**deviceType:** `MOBILE`

---

## Screen 2: iOS Sender — Connecting (MOBILE)

**Prompt:**

> iOS app connecting state for screen cast. Dark background. Centered animated connection graphic between phone and TV icons. Status text "Establishing secure connection…". Progress indicator. Minimal, reassuring UX. Colors #0D1117 and #58A6FF.

**deviceType:** `MOBILE`

---

## Screen 3: Android TV — Pairing (DESKTOP/TV)

**Prompt:**

> Android TV leanback pairing screen, 10-foot UI. Large title "AndroidRemote" at top. Subtitle "Enter this code on your iPhone". Huge 6-digit pairing code in blue (#58A6FF) centered on dark background (#0D1117). Status line "Waiting for iPhone to connect" in gray. Landscape 1920x1080, high contrast for viewing from couch.

**deviceType:** `DESKTOP`

---

## Screen 4: Android TV — Streaming (DESKTOP/TV)

**Prompt:**

> Android TV fullscreen video playback for screen mirroring. Black background with mirrored phone screen centered aspect-fit. Small subtle overlay in corner: green dot "Live" and connection quality. Minimal chrome. Landscape 1920x1080.

**deviceType:** `DESKTOP`

---

## Screen 5: Android TV — Settings (DESKTOP/TV)

**Prompt:**

> Android TV settings screen for cast receiver app. Options: Device name, Video quality (720p/1080p), Show diagnostics overlay toggle, About. D-pad navigable list, dark theme matching #0D1117, focus highlight #58A6FF.

**deviceType:** `DESKTOP`

---

## V2 Screens (generate after V1 ships)

### V2-iOS: Home with mode tabs (MOBILE)

**Prompt:**

> Dark iOS app home with bottom tab bar: Mirror, Photos, Videos, IPTV, YouTube, Remote. Mirror tab selected showing TV discovery list. Accent #58A6FF, background #0D1117, iOS 17 style.

**deviceType:** `MOBILE`

---

### V2-iOS: Photo picker cast (MOBILE)

**Prompt:**

> iOS photo cast screen. Grid of selected photos with checkmarks. Top bar shows connected TV name. Primary button "Cast 12 Photos". Dark theme, PHPicker-style grid.

**deviceType:** `MOBILE`

---

### V2-iOS: TV Remote (MOBILE)

**Prompt:**

> iPhone TV remote control screen. Large touchpad area for D-pad navigation in center. Button row below: back, home, play/pause. Volume rocker on sides. Connected TV name at top. Dark #0D1117, blue accent buttons #58A6FF. Haptic-friendly large tap targets.

**deviceType:** `MOBILE`

---

### V2-iOS: IPTV playlist (MOBILE)

**Prompt:**

> iOS IPTV screen. M3U playlist URL input field. Channel list preview with group headers (Sports, News, Entertainment). Sync to TV button. Dark minimal UI.

**deviceType:** `MOBILE`

---

### V2-TV: IPTV channel grid (DESKTOP/TV)

**Prompt:**

> Android TV IPTV channel browser. Leanback grid of channel cards with logos and names. Group tabs at top. Focus highlight blue #58A6FF. Dark background, 10-foot UI, landscape 1920x1080.

**deviceType:** `DESKTOP`

---

### V2-TV: Photo slideshow (DESKTOP/TV)

**Prompt:**

> Android TV fullscreen photo viewer. Large centered image with subtle bottom bar showing "3 of 12" and photo title. Minimal UI, black letterboxing, dark theme.

**deviceType:** `DESKTOP`

---

## Stitch Project (created)

| Field | Value |
|-------|-------|
| Project | `projects/1101549812967539169` |
| Title | AndroidRemote |
| Design system | `assets/13146778710685448128` |

### V1 screens generated

| # | Screen | Device | Screen ID |
|---|--------|--------|-----------|
| 1 | iOS Home (Mirror tab) | MOBILE | `4a1352ab153e40829867bd2a2a8898d0` |
| 2 | iOS Connecting | MOBILE | `ae531fea852c4c4a89f5d514d4aa8b50` |
| 3 | Android TV Pairing | DESKTOP | `b0ce467f48824b1a8da07763ae58b8a4` |
| 4 | Android TV Streaming | DESKTOP | `12cb1d6947f34425aacdba478d1c213c` |
| 5 | Android TV Settings | DESKTOP | `a141c0c891504f2b8e3c1beebd8bf9c8` |

Use `get_screen` with name `projects/1101549812967539169/screens/{screenId}` to export HTML/CSS for SwiftUI / Compose implementation.

---

## Workflow

1. `create_project` → name: "AndroidRemote" ✅
2. `generate_screen_from_text` for each screen above ✅ (V1)
3. `get_screen` to export HTML/CSS for implementation reference
4. Apply tokens to SwiftUI (iOS) and Compose for TV (Android)
