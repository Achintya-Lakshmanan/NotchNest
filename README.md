# NotchNest

A macOS notch app, built on an M3 MacBook Pro. Hover over the notch to open music
controls, your calendar, reminders and a few other tools. Move away to close it.
Every tab uses the same panel size.

<img src="docs/screenshots/music.png" alt="Expanded music widget with blue album artwork, playback controls and charging status" width="640">

## What it does

Music is the main attraction. NotchNest reads Apple Music artwork and uses its
colors for the background. Pause for 30 seconds and the background returns to
black, the compact artwork disappears and the Music tab shows "Nothing playing."
Resume and the overview comes back, with artwork, playback controls, a seek bar
with elapsed and remaining time, and an audio output menu. Spotify playback is
supported too.

The heart button favorites the current Apple Music track. The lyrics button swaps
the title for synced lyrics that follow playback. Apple Music has no lyrics API,
so lyrics come from [LRCLIB](https://lrclib.net), a free public lyrics database.
Only the title, artist, album and length are sent, one request per song, and only
while the lyrics view is open. Results are cached for the session. Turn off
Lyrics in Preferences to hide the button and never contact LRCLIB.

Calendar puts a month grid beside the selected day's events. Each visit starts
on today. Events show their time, room and a NOW badge while they run. Declined
invitations and events marked free are skipped, and multi-day events appear on
every day they cover. A one-line reminder strip under the grid shows your next
dated task and when it is due. If nothing is upcoming, it shows the most recently
overdue reminder. Click it to open Apple Reminders. NotchNest never completes or
edits reminders.

The flag button beside the date opens Deadlines: anything due in the next two
weeks, with a countdown that turns orange inside 24 hours. Deadlines come from
event titles (due, deadline, exam, quiz, assignment, homework, submission, last
day) and from registrar-style markers stored at midnight, which read "Due by
11:59 PM". Study sessions, office hours and exam prep are left out. Tap a
deadline to jump to its day.

The other tabs cover a few everyday jobs.

- Weather shows State College conditions, an hourly forecast and rain chances.
- Timer has 1, 5, 10 and 25-minute presets, a −/+ stepper for any length, and a
  countdown around the notch. Pomodoro runs 25-minute focus rounds with 5-minute
  breaks (15 minutes every fourth round) and announces each switch.
- The AI Usage tab switches between Codex and Claude weekly allowance, reset time
  and subscription tier, plus the rolling 5-hour limit and when it resets. Codex uses its existing sign-in. Claude needs a separate
  one-time connection through the Connect Claude button.
- Shelf holds files you drag in and lets you send them through AirDrop.
- Mirror opens a front-camera preview and stops the camera when you leave.

The collapsed notch can show a class or meeting countdown, music, charging
status or an active download indicator. Class mode puts a ring on the left wing
that fills as the class goes on, with the time left on the right ("12m"). Before
a class it shows an outlined ring and "in 52m". About 10 minutes before each
class or meeting, a heads-up popup shows its name and room. All-day events and
deadlines stored as midnight entries do not trigger the countdown. Small popups handle AirPods connections and battery
warnings. Focus changes and Caps Lock get brief popups too. When Claude is
connected, a popup warns when the 5-hour or weekly limit drops to 10%, and
another says when a mostly used 5-hour window resets. Popups wait while the
panel is open and appear once it closes. Volume and brightness
keys use notch controls in place of the macOS HUD.

The collapsed widget keeps both black sides visible, even when they have no
indicator. Hover either side to open it.

Focus popups use Apple's shared Focus status and need the Share Focus Status
permission, plus a build signed with the Communication Notifications capability
and a matching Apple provisioning profile. Enable Share Focus Status for the modes you want to show. The popup
says "Focus" because Apple reports whether notifications are silenced, not the
name of the active mode. macOS may still display its own Focus banner.

Open the gear button for Preferences, grouped into General, Tabs, Calendars and
Notch. Click a tab to show or hide it, or drag tabs to change their order in the
notch. Calendars lets you choose which calendars feed the grid, class mode and
deadlines. You can also hide Codex or Claude in the AI Usage tab, turn class
mode or Claude alerts off, set quiet hours, turn off the reminder strip or enable
launch at login.

The menu-bar button beside the gear opens a drawer of menu-bar apps. Press
Control-Option-M to open it without reaching a menu-bar icon, then click an app
to open its native menu. Escape, the shortcut again or a click outside closes it.
Items covered by the physical notch get an orange badge. Scanning happens only
when you open the drawer or press Refresh. Some apps do not expose their menu
through Accessibility and cannot be opened this way.

Expanded widgets stay attached to the physical notch, with a solid black strip
above their content. Native icons behind an open card are available in its drawer;
selecting one hides the card before opening the menu. The drawer separates app
menus from macOS controls, rather than filling the app grid with system helpers.
NotchNest's own menu-bar icon appears only when the MacBook display is unavailable.
The drawer does not move or hide other apps' icons.

## Screenshots

These are renders of the app's own views with sample data. The song, artwork,
events, reminder and usage figures are examples, not personal account data.

| Calendar and reminders | Hourly weather |
| --- | --- |
| <img src="docs/screenshots/calendar.png" alt="Month calendar with a next reminder strip under the grid and two events beside it" width="480"> | <img src="docs/screenshots/weather.png" alt="State College weather with hourly temperatures and rain chances" width="480"> |

| Synced lyrics | Deadlines |
| --- | --- |
| <img src="docs/screenshots/lyrics.png" alt="Music tab with the current and next lyric line in place of the title, and heart, lyrics and output buttons" width="480"> | <img src="docs/screenshots/deadlines.png" alt="Deadlines list beside the month grid with countdowns, the nearest in orange" width="480"> |

| Timer | Pomodoro break |
| --- | --- |
| <img src="docs/screenshots/timer.png" alt="Timer with fifteen minutes remaining and quick-start buttons" width="480"> | <img src="docs/screenshots/pomodoro.png" alt="Green Pomodoro break ring with three minutes left in round two" width="480"> |

| Codex weekly allowance | Claude weekly allowance |
| --- | --- |
| <img src="docs/screenshots/codex.png" alt="Codex widget with an example of 55 percent remaining and a reset countdown" width="480"> | <img src="docs/screenshots/claude.png" alt="Claude selected in the provider switch with a sample Max tier and weekly allowance" width="480"> |

Class mode in the collapsed notch: a class in progress, the next one, and the
heads-up before it starts.

<img src="docs/screenshots/class-live.png" alt="Collapsed notch with a green progress ring on the left and 12m on the right" width="390">
<img src="docs/screenshots/class-upcoming.png" alt="Collapsed notch with an outlined ring on the left and in 52m on the right" width="390">
<img src="docs/screenshots/class-heads-up.png" alt="Popup reading Algorithms - LEC, starts in 10 min, Thomas Building 100" width="475">
<img src="docs/screenshots/claude-low-alert.png" alt="Popup warning that the Claude 5-hour limit is running low" width="475">

<details>
<summary>Collapsed notch, controls and Shelf</summary>

Menu-bar apps, with a sample hidden-item badge.

<img src="docs/screenshots/menu-bar-apps.png" alt="Menu-bar app drawer with six sample app icons below the notch" width="640">

Music and charging in the collapsed notch.

<img src="docs/screenshots/compact.png" alt="Collapsed notch with album art and charging status" width="390">

Volume, brightness and a Bluetooth connection popup.

<img src="docs/screenshots/volume.png" alt="Notch volume control" width="390">
<img src="docs/screenshots/brightness.png" alt="Notch brightness control" width="390">
<img src="docs/screenshots/bluetooth.png" alt="AirPods connection popup with earbud and case battery levels" width="475">

Focus and Caps Lock changes use the same small banner.

<img src="docs/screenshots/focus.png" alt="Purple moon popup indicating Focus is on" width="475">
<img src="docs/screenshots/caps-lock.png" alt="Orange Caps Lock popup" width="475">

Files in Shelf, ready to drag out or AirDrop.

<img src="docs/screenshots/shelf.png" alt="Shelf widget with three sample items and an AirDrop all button" width="640">

</details>

## Build and run

You need a MacBook with a built-in notch, macOS 14 or later, and a Swift 6 toolchain.

```sh
./build_app.sh
open NotchNest.app
```

The script builds a release app and uses an available Apple Development or
Developer ID signing identity. It falls back to ad hoc signing if neither is
available. A stable signing identity helps macOS keep permission grants across
rebuilds.

To include the Focus connection, supply the macOS provisioning profile for
`com.notchnest.app` with the Communication Notifications capability enabled.

```sh
NOTCHNEST_PROVISIONING_PROFILE=/absolute/path/NotchNest.provisionprofile ./build_app.sh
```

Without a profile, the script builds a working app with Focus disconnected.
Caps Lock and the other notch tools still work.

Move `NotchNest.app` to `/Applications` for daily use. Quit the running copy before
replacing it. The app has no Dock icon. Use its menu-bar item or Preferences to quit.

For tests, source layout and screenshot generation, see [Development](docs/development.md).

## Permissions

macOS may ask for these permissions when you use the corresponding feature.
You can review them in System Settings under Privacy & Security.

| Permission | What uses it |
| --- | --- |
| Automation | Read artwork and playback details, and control Music or Spotify. |
| Calendars | Read events after you connect Calendar. |
| Reminders | Read dated tasks after you click Connect Reminders. This is separate from Calendar access. |
| Accessibility | Handle volume and brightness keys, observe Caps Lock changes, and read and open menu-bar items. |
| Focus status | Show when Focus silences or resumes notifications. |
| Camera | Show the Mirror tab. |
| Bluetooth | Detect device connections and disconnections. |
| Downloads folder | Detect unfinished downloads and show a completion notice. |

macOS labels Reminders permission as full access. NotchNest uses it only to read
the title, due date and list details for the strip. Reminder fetching stops when
the strip is hidden. Codex also stops refreshing when its tab is closed and uses
your existing sign-in. It does not start model tasks or redeem reset credits.
Claude has its own app-local WebKit sign-in. NotchNest does not import cookies or
credentials from Claude Desktop or your browser. It releases the hidden web page
after each reading. It refreshes while Claude is selected in the open panel and,
for limit alerts, in the background every 10 minutes on power or 30 on battery.
That check is faster while the 5-hour window is nearly used, and it pauses in
Low Power Mode, while the screens sleep, or when Claude alerts are turned off.

## TVs and external displays

With an extended desktop, the widget stays on the MacBook's built-in notch, even
when a TV is the main display. Mirroring or closing the lid for TV-only use hides
the widget and returns volume and brightness keys to macOS. Reconnecting the
MacBook display restores it. Timers and stashed files stay in memory while hidden.

## Current limits

- Weather is hardcoded to State College, Pennsylvania, and comes from Open-Meteo.
  There is no location picker or Apple Weather integration.
- Reminders need a due date. Undated tasks do not appear in the strip.
- The download indicator detects temporary browser files. It does not estimate
  percentage complete or time remaining.
- Bluetooth battery details depend on what macOS reports for the device.
- HDMI volume control depends on the output device. Unsupported controls fall
  back to macOS. Brightness control targets the built-in display.
- Brightness uses a private macOS interface, so an OS update can break it.
- Codex allowance needs a signed-in Codex installation. An unavailable reading
  appears as unavailable, not as zero remaining.
- Claude needs a separate sign-in. Its web usage interface is not a public,
  versioned API, so a website change can interrupt syncing.
- Lyrics depend on LRCLIB having the song. Favorites work for Apple Music only.
- Deadlines are detected from event titles, so unusual wording can be missed.
  Hide a calendar in Preferences if it produces false matches.
