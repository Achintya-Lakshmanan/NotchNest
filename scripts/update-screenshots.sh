#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
screenshot_bin_dir=$(swift build --show-bin-path)
screenshot_temp=$(mktemp -d "${TMPDIR:-/tmp}/notchnest-screenshots.XXXXXX")

# Argument-domain preferences apply only to this process. Nothing is persisted.
NOTCHNEST_SNAPSHOT_DIR="$screenshot_temp" "$screenshot_bin_dir/NotchNest" \
  -disabledTabs '()' \
  -showCalendarReminder YES \
  -batteryPercentInExpanded YES \
  -batteryPercentInCompact YES \
  -batteryCompactSchedule NO \
  -musicCompactRespectQuietHours NO \
  -allowanceProvider Codex

mkdir -p docs/screenshots
for mapping in \
  '1_music_charging:music' \
  '17_calendar_reminder:calendar' \
  '8_weather:weather' \
  '12_timer:timer' \
  '13_codex:codex' \
  'claude:claude' \
  '5_compact_charging:compact' \
  '9_hud_volume:volume' \
  '10_hud_brightness:brightness' \
  '4_bt_popup:bluetooth' \
  'focus_popup:focus' \
  'caps_lock_popup:caps-lock' \
  'menu_bar_apps:menu-bar-apps' \
  '3_shelf:shelf' \
  'music_lyrics:lyrics' \
  'calendar_deadlines:deadlines' \
  'compact_class_live:class-live' \
  'compact_class_upcoming:class-upcoming' \
  'class_heads_up:class-heads-up' \
  'claude_low_alert:claude-low-alert' \
  '12_timer_break:pomodoro'; do
  cp "$screenshot_temp/${mapping%%:*}.png" "docs/screenshots/${mapping##*:}.png"
done

printf 'Updated docs/screenshots. Full render set: %s\n' "$screenshot_temp"
