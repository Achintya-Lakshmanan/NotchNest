# Development

NotchNest uses SwiftUI for the widgets and AppKit for the notch window. It has no
third-party package dependencies. Development has used an M3 MacBook Pro with
Swift 6.4 and Xcode 27. The package targets macOS 14 and later.

## Build and test

```sh
swift build
swift test
./build_app.sh
```

Use the app bundle for permission and device checks. Running the executable from
a terminal can produce different permission behavior from launching the signed
app. The build script uses a local signing identity when one is available.

Tests cover display routing, calendar navigation, reminder selection and
permissions, Codex allowance, panel sizing and the album-color pause timeout.
Claude decoder tests use fixtures, not a signed-in account. The live web
connection needs a manual sign-in check. Claude's web usage endpoints are not
a versioned public API and may change.
The layout tests briefly open windows with sample content. They do not change
your calendar or reminders.

## Source map

Paths below are relative to `Sources/NotchNest`.

| File or folder | Responsibility |
| --- | --- |
| `main.swift`, `AppDelegate.swift` | Start the app and handle debug modes. |
| `NotchController.swift` | Own the panel, hover behavior, display changes, polling and menu-bar item. |
| `NotchState.swift` | Hold the view state and coordinate actions. |
| `Models.swift`, `Settings.swift` | Define display data, panel dimensions and saved preferences. |
| `Services/DisplayRouting.swift` | Choose the built-in display or pause for mirroring and closed-lid use. |
| `Services/MediaController.swift`, `Services/ColorExtractor.swift` | Read playback and artwork, then extract the background color. |
| `Services/CalendarService.swift`, `Services/ReminderService.swift` | Read EventKit data and choose events and reminders to show. |
| `Services/CodexUsageService.swift` | Read weekly allowance through a short-lived Codex app-server process. |
| `Services/ClaudeUsageService.swift` | Read Claude's weekly usage through a separate WebKit sign-in, without importing credentials from other apps. |
| `Services/BatteryMonitor.swift`, `Services/BluetoothMonitor.swift`, `Services/BluetoothEventMonitor.swift` | Read battery status and track device connections. |
| `Services/AudioOutput.swift`, `Services/HUDController.swift`, `Services/BrightnessControl.swift` | Select audio output and handle volume and brightness controls. |
| `Services/FocusMonitor.swift` | Observe shared Focus status through Apple's Intents API and filter duplicate or unknown states. |
| `Services/MenuBarAppsService.swift`, `Services/MenuBarShortcut.swift` | Scan menu-bar extras on demand and open the drawer with a registered Control-Option-M hotkey. |
| `Services/WeatherService.swift` | Fetch the State College forecast from Open-Meteo. |
| `Services/DownloadMonitor.swift` | Watch Downloads for temporary browser files. |
| `Services/AirDropService.swift`, `Services/LoginItem.swift` | Open AirDrop sharing and manage launch at login. |
| `Views/` | Draw the compact notch, expanded tabs, controls and Preferences. |
| `NotchPresentation.swift` | Own the panel, pointer interaction, drawer and native-menu handoff. |
| `Services/DisplayRefresh.swift` | Settle display changes with bounded retries after temporary empty screen snapshots. |
| `Snapshot.swift` | Render documentation and test images with sample data. |

## Regenerate screenshots

Run this from the repository root.

```sh
./scripts/update-screenshots.sh
```

The script builds the debug executable, renders the app's views offscreen and
copies the selected PNGs into `docs/screenshots`. It does not restart or replace
the installed app. It uses fictional music and reminder data, generated cover
artwork and sample weather and allowance values. It does not fetch account data,
read your calendar or query Music for artwork.

The images reflect the rendering Mac's date, clock format and system fonts.
Review the PNGs before committing them, especially after changing panel dimensions.
The screenshot script uses temporary preference overrides so hidden tabs and
quiet hours do not change the gallery. It does not save those overrides.

## Useful debug modes

Set these environment variables when launching the development executable.

| Variable | Effect |
| --- | --- |
| `NOTCHNEST_REGULAR=1` | Add a Dock icon for the development run. |
| `NOTCHNEST_DEBUG=1` | Start with the expanded panel centered on screen. |
| `NOTCHNEST_SNAPSHOT_DIR=/absolute/path` | Render sample PNGs to the folder, then quit. |
| `NOTCHNEST_SNAPSHOT_REMINDERS_ONLY=1` | Limit a snapshot run to Calendar and reminder states. |
| `NOTCHNEST_SNAPSHOT_CODEX_ONLY=1` | Limit a snapshot run to Codex allowance states. |
| `NOTCHNEST_ARTTEST=/absolute/path.png` | Export current Apple Music artwork. This reads live Music data. |
| `NOTCHNEST_CODEX_CHECK=1` | Read and print the signed-in account's weekly allowance once, then quit. |

The two snapshot filters require `NOTCHNEST_SNAPSHOT_DIR`. The live Codex check
does not start a model task or redeem a reset credit.

## Things to check on a Mac

Automated tests simulate display layouts. Check these cases with a real TV after
changing display routing or HUD handling.

- Extend the desktop and make the TV the main display. The notch should stay on
  the MacBook, including when the TV sits above or left of it in the arrangement.
- Mirror the displays or close the lid for TV-only use. The notch should hide,
  and macOS should handle the volume and brightness keys.
- Reopen the lid or disconnect the TV. The notch should return without a restart.
- Change resolution, sleep and wake. Check the notch's position again.

For music changes, pause for at least 30 seconds, resume, then try a brief pause.
Check both the collapsed notch and the Music tab. After the longer pause, the
background should turn black, the compact artwork should disappear and Music
should show "Nothing playing." Resume playback and check that the overview returns.

For Calendar, browse another month, close the notch and reopen it. It should show
today. Check the reminder permission flow separately from Calendar permission.

For menu-bar apps, test Control-Option-M, Escape and an outside click. Open a
native menu from the drawer, including a hidden item if the menu bar is crowded.
Check that the card and HUDs stay attached to the screen's top, with content below
the physical cutout and a black strip above it. Check the Apps and System filters.
An unchanged screen-parameters notification must not hide or close the card. A burst
of empty snapshots during HDMI negotiation must recover when the built-in display
returns. No recurring AX
scan or keyboard-text listener is needed. Apps that do not expose their menu
should report that it is unavailable instead of pretending it opened.

With Music idle and no meeting, timer or stashed file, the collapsed widget must
keep both black sides visible. Hover each side to open the card, then move into
the card without it collapsing. The cutout stays centered even if only one side
has an indicator. Check that hovering a nearby menu-bar icon does not open it.
Try both sides at the very top edge, move straight into the card, then leave and
return quickly. Repeat after selecting a native menu from the drawer. These paths
must work without another mouse-enter event. Pointer monitoring is event-driven;
there is no repeating hover timer. The window changes hit geometry immediately,
while SwiftUI fades in content, so old window animations cannot finish out of order.

## Adjusting the layout

Panel sizes live in `NotchMetrics` in `Models.swift`. Keep the expanded size shared
across tabs. `TrackingHostView` lets the controller set the window size instead
of allowing SwiftUI content to enlarge it. `NotchPresentation` keeps the native
window frame in sync with `NotchState.presentationSize`.

`Views/NotchShape.swift` defines the bottom corners. `Views/NotchRootView.swift`
sets the album tint and fade animation. The 30-second pause delay lives in
`NotchState.swift`. Polling intervals live in `NotchController.setupTimers()`.
