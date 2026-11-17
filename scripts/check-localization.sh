#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:?Usage: scripts/check-localization.sh /path/to/built/Schedy.app}"
python3 "$repo_root/scripts/check-localization-catalogs.py" "$app_path"
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun --sdk macosx swiftc -parse-as-library \
  "$repo_root/Tests/LocalizationChecks.swift" \
  "$repo_root/Schedy/Models/Course.swift" \
  "$repo_root/Schedy/Models/CourseReschedule.swift" \
  "$repo_root/Schedy/Models/Schedule.swift" \
  "$repo_root/Schedy/Models/TimeSlotPreset.swift" \
  "$repo_root/Schedy/Models/TimeSlotItem.swift" \
  "$repo_root/Schedy/Models/ParsedCourseItem.swift" \
  "$repo_root/Schedy/Helpers/WeekdayLabels.swift" \
  "$repo_root/Schedy/Services/CSVImport/CSVParser.swift" \
  "$repo_root/Schedy/Services/CSVImport/CSVExport.swift" \
  "$repo_root/Schedy/Services/CSVImport/CSVImportConstants.swift" \
  "$repo_root/SchedyWidget/WidgetDataKeys.swift" \
  -o "$check_dir/localization-checks"
"$check_dir/localization-checks" "$app_path"
