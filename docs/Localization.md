# Localization

Schedy supports English (`en`) and Simplified Chinese (`zh-Hans`) using Apple's String Catalogs. It follows the system's app language selection. English is the development/fallback language.

- App display name: **Schedy: Timetable** / **Schedy 课程表**.
- `Schedy/Localizable.xcstrings`: UI, errors, default names, CSV instructions/templates, and notifications.
- `SchedyWidget/Localizable.xcstrings`: widget UI, previews, and App Intent configuration.
- Each target has its own `InfoPlist.xcstrings` for its display name. The widget target uses explicit resource membership in the Xcode project.

Use stable semantic keys in lowercase dot-separated namespaces. Use underscores within a segment: `settings.appearance.title`, `import.csv.error.empty_file`, `widget.configuration.follow_app`. Name the concept and its role, rather than encoding the current sentence, punctuation, or parameter values. Editing or translating copy must not require changing the key. Reuse keys only when their meaning and context match.

Use Apple's native APIs with literal keys and English `defaultValue` text, including for strings returned by models and services:

```swift
String(localized: "settings.appearance.title", defaultValue: "Appearance")
String(localized: "schedule.week.label", defaultValue: "Week \(week)")
LocalizedStringResource("widget.title", defaultValue: "Today's Classes")
```

App Intent metadata uses `LocalizedStringResource`. Keep interpolated sentences together so translations can reorder arguments. Count-based messages use plural variations in the catalog. When changing argument order in a default value, update positional arguments in every translation. User-supplied option names are interpolated through `widget.configuration.schedule_name`, so a name that happens to match a key is still displayed literally.

Scheduled notifications use `notification.course.title` and `notification.course.body` and are localized by the system at delivery. Keep the body’s manually registered catalog entry and its documented argument order. `CFBundleDisplayName` in `InfoPlist.xcstrings` is an Apple-defined key and must retain its exact name. Use `Text(verbatim:)` for brand names, numeric labels, or already-formatted text that should not become translation keys.

Dates use locale-aware templates. Widgets receive a timestamp in addition to legacy formatted strings, allowing the widget to format dates in its own language. Academic weekday numbering and semester calculations remain independent of language.

Do not translate stored names, enum raw values, App Group keys, school catalog names, or parser tokens. Default timetable/preset names are localized when first created and then remain user data. The widget's saved “follow app” string remains `跟随 App 当前选中` for compatibility; its App Intent option has a separate localized title. Names supplied by users remain literal option titles.

CSV headers remain the existing Chinese schema in both languages. English templates and AI instructions explicitly retain these headers. Exported week patterns use the parser's language-independent `all`, `odd`, and `even` values; the parser also continues accepting the original Chinese values.

Build the app and widget, then run:

```sh
scripts/check-localization.sh /absolute/path/to/Debug-iphonesimulator/Schedy.app
```

The script first runs `scripts/check-localization-catalogs.py` to enforce the key convention, exact source/catalog coverage, compiler-extracted key coverage, language coverage, and compatible format arguments. It then compiles the actual model, CSV, and widget data code into an isolated check executable. Runtime checks cover localized app names, plurals, reordered arguments, notification text, CSV round trips and templates, literal user names, legacy widget selections, and timestamp-based dates without accessing application data.

App Store names, descriptions, and screenshots are managed separately in App Store Connect.
