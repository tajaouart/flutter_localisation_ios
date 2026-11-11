# FlutterLocalisation for iOS

Live translation updates for native iOS apps that ship an Xcode String Catalog
(`Localizable.xcstrings`), managed on [flutterlocalisation.com](https://flutterlocalisation.com).

Edit a string in the dashboard, publish a live update, and the app shows it on
its next refresh, without a new App Store release. Your code does not change:
`String(localized:)`, `NSLocalizedString`, `LocalizedStringResource`,
`AttributedString(localized:)` and SwiftUI `Text` all pick up the live copy.

## How it works

The dashboard serves the update as a String Catalog. The SDK compiles it into
the same `.strings` and `.stringsdict` files Xcode builds into your app, and
answers your bundle's lookups from them. Foundation does all the formatting,
so plural forms (including `zero`, Arabic `two`, `few` and `many`), positional
arguments (`%1$@ %2$lld`), substitutions and device variations behave exactly
like the bundled copy. The test suite checks this against `xcstringstool`, the
compiler Xcode itself runs.

A key the update does not carry keeps the bundled string. In an app running in
`es-MX` the order is: live `es-MX`, bundled `es-MX`, live `es`, then the bundle
as usual. A base language only follows a variant written in the same script,
so `zh-Hant` never shows Simplified `zh` strings.

iOS itself does not fall back from `es-MX` to `es`: a key missing from the
`es-MX` table shows as the raw key. The dashboard therefore exports a regional
variant with its parent's text wherever it has no wording of its own, and a
live edit to `es` is sent to such a variant as well.

`InfoPlist.xcstrings` (app name, permission prompts) is read by iOS before
your code runs, so it cannot be updated live; the dashboard leaves it out of
live updates.

## Install

Swift Package Manager: add `https://github.com/tajaouart/flutter_localisation_ios`
and the `FlutterLocalisation` product. iOS 16, macOS 13, tvOS 16, watchOS 9 or
visionOS 1.

## Use

```swift
import FlutterLocalisation
import SwiftUI

@main
struct MyApp: App {
    @StateObject private var live = LiveLocalisation(
        secretKey: "sk_live_...",   // Dashboard > Live updates
        projectId: 42,
        flavor: "Default"
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .liveLocalisation(live)   // redraws when an update lands
                .task { live.start() }    // fetches in the background
        }
    }
}
```

Create it before the first string is looked up. In UIKit, keep it on your app
delegate and observe `LiveLocalisation.didUpdateNotification` to reload
visible text.

| API | |
| --- | --- |
| `start()` | Fetch in the background. |
| `refresh() async throws -> Bool` | Fetch now; true when something changed. |
| `isLive(_ key:)` | Whether the app currently shows the live copy of a key. |
| `liveLocales`, `liveKeys(in:)` | What the last updates carried. |
| `reset()` | Drop live strings and show the bundled ones. |
| `revision`, `lastModified`, `isRefreshing`, `lastError` | Published state. |

Pass `bundledAt:` with the date your catalog was exported to drop live strings
older than the build, the same rule the Flutter package applies with an ARB's
`@@last_modified`. Without a `secretKey` nothing is fetched.

Keep the secret key out of source control: the example reads it from a build
setting (`FL_SECRET_KEY`) through its Info.plist.

## Example

`Example/` is a SwiftUI app with the same content as the Flutter package's
example: seven languages (English, Spanish, Mexican Spanish, French, Arabic,
Simplified and Traditional Chinese), plurals with every Arabic form, one
string per gender (String Catalogs have no `select`), dates, currency, compact
numbers and percentages, a string marked "Don't translate", a localised app
name, and a live update panel.

```bash
cd Example
open LocalisationDemo.xcodeproj
# or with live updates:
xcodebuild -scheme LocalisationDemo FL_SECRET_KEY=sk_live_... FL_PROJECT_ID=42 ...
```

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`. To try another language, set it under Settings > Apps >
Localisation > Language, or launch with `-AppleLanguages "(ar)"`.

## Tests

```bash
swift test
```

Runs on macOS and needs Xcode's command line tools for the parity tests.

## License

MIT
