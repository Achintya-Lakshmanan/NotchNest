# NotchNest 🪺

A fun, DynamicLake-style notch companion for Apple Silicon MacBooks. It lives in
your MacBook's notch, hugs the cutout when collapsed, and springs open into an
interactive card when you hover.

Built & tested on an M3 MacBook Pro, macOS Tahoe (26/27), Swift 6.4 / Xcode 27.

## Features

### 🎵 Music
- Now Playing for **Apple Music** and **Spotify** (album art, title, artist).
- Real **Apple Music artwork** (pulled via AppleScript) and a card that **tints to
  match the album colors**.
- **Scrub to seek** (drag the progress bar), plus play/pause/next/prev.
- **Audio output switcher** — flip between speakers / AirPods / AirPlay (CoreAudio).
- Collapsed: a live **equalizer** peeks beside the notch while playing.

### 📅 Calendar
- A full **month grid** + a **side panel** of the selected day's events.
- Weekends in blue, today in a red circle, dots on days with events.
- **Meeting countdown** in the collapsed notch ("12m" / "Now") for the next event
  within the hour.
- **Join** button on events that contain a Zoom / Meet / Teams / Webex / Whereby
  link (parsed from the event's URL, location, or notes).

### 📥 Shelf + AirDrop
- **Drag files onto the notch** to stash them; drag them back out anywhere.
- Per-item **AirDrop** button and an **AirDrop all** action (system AirDrop sheet).

### 🌤️ Weather
- A **weather tab** with current temp, condition, today's high/low, and an
  **hourly strip** (next 12 hours: time, icon, temp, **rain %**).
- Open-Meteo (no API key), location fixed to State College, PA, with a **sky
  gradient** that changes with the time of day and conditions.
- **Rain-soon alert** toast when precipitation looks likely in the next few hours.

### 📷 Camera mirror
- A **Mirror tab** with a live front-camera preview for a quick look before calls.
  Camera runs only while the tab is open. Requires camera permission.

### 🔔 Alerts
- Toasts for **rain soon**, **low battery**, and **fully charged** — reusing the
  same notch banner as the Bluetooth toasts.

### 🔆 HUD replacement
- Volume and brightness changes show a **sleek HUD in the notch** instead of the
  default macOS overlay (intercepts the media keys, applies the change, and
  suppresses the system HUD).
- Requires **Accessibility** permission (prompted on launch).

### 🔋 Battery & 🎧 Bluetooth
- Collapsed pill stays clean: just an **animated charging bolt** when plugged in.
- **Laptop + AirPods battery** shown when expanded (hover).
- Small **toasts** when a Bluetooth device connects / disconnects, and a
  **low-battery** warning (≤20%) — with L/R/case + Mac battery.

### ⚙️ Misc
- **Launch at login** and a **Preferences** window (gear in the notch or the
  menu-bar item) to toggle launch-at-login, the meeting countdown, and which tabs
  appear.
- No Dock icon (accessory app). Quit from the ✨ menu-bar item.
- One consistent expanded size for all tabs (no resize jump); content sits below
  the physical notch so nothing hides in the cutout.

## Build & run

```bash
# Dev build + run from terminal
swift build && swift run

# Build a double-clickable .app (release, ad-hoc signed)
./build_app.sh
open NotchNest.app          # or move NotchNest.app to /Applications
```

## Permissions

- **Automation** (System Settings ▸ Privacy & Security ▸ Automation) — to read
  now-playing info and control Music / Spotify. Prompted on first use.
- **Calendar** — to show your events. Prompted from the Calendar tab.
- **Accessibility** — for the volume/brightness HUD key tap. Prompted on launch;
  the tap auto-activates once granted (no relaunch needed).
- Battery (IOKit), Bluetooth (`system_profiler`), audio output (CoreAudio), and
  weather (network) need no special permission.

## Architecture

- `main.swift` / `AppDelegate.swift` — accessory `NSApplication` entry point.
- `NotchController.swift` — finds the notched screen, creates a borderless
  non-activating `NSPanel` at status-bar level, handles hover (NSTrackingArea +
  debounced collapse), the compact/toast/expanded resize, timers, the menu-bar
  item, and the Preferences window.
- `NotchState.swift` — the `ObservableObject` driving every view.
- `Settings.swift` — UserDefaults-backed settings (launch at login, tabs, etc.).
- `Services/`
  - `MediaController.swift` — Music/Spotify via AppleScript (now playing, transport, seek, artwork).
  - `BatteryMonitor.swift` — IOKit power source.
  - `BluetoothMonitor.swift` — connected devices + battery via `system_profiler`.
  - `CalendarService.swift` — EventKit fetch + meeting-link extraction.
  - `AudioOutput.swift` — list/get/set default output device (CoreAudio).
  - `ColorExtractor.swift` — vibrant color from album art (CoreImage).
  - `AirDropService.swift` — `NSSharingService` AirDrop.
  - `LoginItem.swift` — `SMAppService` launch at login.
  - `WeatherService.swift` — IP geolocation + Open-Meteo (no API key).
  - `HUDController.swift` — media-key event tap (volume/brightness HUD).
  - `BrightnessControl.swift` — display brightness via private DisplayServices.
- `Views/` — `NotchShape` (geometry), `CompactView`, `ExpandedView` (music /
  calendar / shelf panes), `Components` (equalizer, batteries, meeting pill,
  toast card, output menu, buttons), `NotchRootView`, `SettingsView`.

## Tuning

- Notch / card sizes: `compactSize`, `expandedSize`, `toastSize` in `Models.swift`.
- Corner curve: `bottomCornerRadius` in `Views/NotchShape.swift`.
- Poll intervals: `setupTimers()` in `NotchController.swift`.
- Album tint strength: the gradient opacity in `NotchRootView.swift`.

### Debug env vars (verification only)

- `NOTCHNEST_REGULAR=1` — run as a regular (Dock) app instead of accessory.
- `NOTCHNEST_DEBUG=1` — render the expanded card centered & floating.
- `NOTCHNEST_SNAPSHOT_DIR=<dir>` — render PNGs of each UI state, then quit.
- `NOTCHNEST_ARTTEST=<path>` — dump the current Apple Music artwork to a PNG.
