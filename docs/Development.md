# Development

## Build

Install Xcode 26 or later with the macOS 26 SDK or later, and XcodeGen 2.45.1 or later. The SDK requirement is separate from the app's minimum macOS version.

Run these commands from the repository root:

```bash
brew install xcodegen
xcodegen generate
open Dejima.xcodeproj
```

Configure your signing team in `project.yml`, or select **Sign to Run Locally** in Xcode's Signing & Capabilities settings. Regenerating the project replaces changes made only in the generated project. Use a consistent signing identity when testing Accessibility access; changing signatures or app copies can require granting access again.

Choose a scheme and run it in Xcode, or build from the command line after configuring signing:

```bash
xcodebuild -project Dejima.xcodeproj -scheme Dejima -configuration Release build
xcodebuild -project Dejima.xcodeproj -scheme Dejima26 -configuration Release build
```

## Translation targets

The targets share the app code and bundle identifier. Each includes one implementation of `TranslationHub`.

| Target | Minimum macOS | Translation session |
|---|---|---|
| `Dejima` | 15 | A SwiftUI `translationTask` attached to a hidden host window |
| `Dejima26` | 26 | `TranslationSession(installedSource:target:)` |

The legacy implementation can ask the framework to identify the source language and request language downloads. The direct session API requires a source language and installed models. The macOS 26 implementation retries language identification when the router has no confident result, and reports missing models as an error.

The `Dejima26` target produces `Dejima26.app` to avoid overwriting the other target's output. Packaging renames both builds to `Dejima.app` and puts them in separate folders.

Optional refinement uses Foundation Models when available on macOS 26 or later. Both targets include the same refinement code.

## Verify Apple Intelligence use

Dejima has two distinct model paths:

- **Draft translation:** `TranslationSession` chooses its default strategy because Dejima does not explicitly select one. On macOS 26.4 or later, inspect `session.preferredStrategy` and the build SDK. Apple's [`highFidelity`](https://developer.apple.com/documentation/translation/translationsession/strategy/highfidelity) strategy prefers Apple Intelligence models and can fall back to traditional models. Existing Apple Intelligence models may satisfy the requirement without separate language downloads. A preferred strategy alone does not identify the model that handled a particular request.
- **Additional refinement:** the **Refine with Apple Intelligence** switch controls a separate `LanguageModelSession` call in `Polisher.swift`, after the draft is complete. It is off by default and requires `SystemLanguageModel.default.availability` to be `.available`. Turning it off does not force the draft translation to avoid Apple Intelligence.

Read the saved refinement preference without changing it:

```bash
defaults read com.nuki.Dejima polishWithAppleIntelligence
```

An unset key uses the default `false`. The running app also checks model availability. To confirm an individual request, use a Debug build with the intended signing identity and synthetic text:

1. Enable **Refine with Apple Intelligence** and translate the sample. In `Controller.swift`, confirm that `Polisher.isEnabled` is true before `result.beginRefining()`.
2. Set a breakpoint at `session.respond(to:)` in `Polisher.swift` to confirm that the additional request starts.
3. Inspect `response.content` after the await completes, and compare the trimmed `revised` value with `draft`. A nonempty identical response is still a successful model call. An empty response returns the draft.
4. Set another breakpoint in the `catch` block and inspect `error` to distinguish a failed request from successful unchanged output. The current app silently keeps the draft on failure.

The temporary **Refining…** label shows that the step started; it does not certify success. The final interface does not retain a refinement outcome, so the displayed text alone cannot distinguish disabled, unchanged, or failed refinement.

For timing and request inspection, use Apple's [Foundation Models instrument](https://developer.apple.com/documentation/FoundationModels/analyzing-the-runtime-performance-of-your-foundation-models-app). Use synthetic text for traces because they can contain prompts and responses. A standalone probe can verify model availability and the helper's behavior, but cannot establish that a previous request in the installed app used refinement.

## Source layout

- `Sources/Controller.swift` connects permissions, key monitoring, translation, and the result panel.
- `Sources/DoubleCopyMonitor.swift` detects the copy gesture and reads the clipboard.
- `Sources/LanguageRouter.swift` selects the translation direction; `TextCleaner.swift` repairs copied line breaks.
- `Sources/TranslationLegacy/` and `Sources/Translation26/` contain the target-specific translation implementations.
- `Sources/Polisher.swift` handles optional refinement and returns the draft on failure.
- `Sources/PermissionGuide.swift`, `MenuBarView.swift`, `ResultPanel.swift`, and `ResultView.swift` provide the interface.
- `Sources/Updater.swift` checks GitHub releases; `LoginItem.swift` manages launch at login.

UI translations are stored in `Localizable.xcstrings` and `InfoPlist.xcstrings`. Keep these catalogs, `Assets.xcassets`, and `AppIcon.icon` included in both targets when changing `project.yml`. After regenerating the project, check the language list in Xcode before editing translations; the translated strings remain in the catalogs.

## App icon

Edit `AppIcon.icon` in Icon Composer. Xcode uses it for both targets and generates compatible icons for older macOS releases. The menu bar symbol remains in `Sources/DejimaMark.swift`.

Run `./Scripts/app-icon.sh` with Xcode 27 selected to refresh the PNGs in `Assets.xcassets/AppIcon.appiconset`. These exports include the traditional macOS inset; packaging uses `icon_512.png` for DMG artwork and the volume icon.

## Package a release

The release script requires a clean working tree. It builds both targets, verifies their signatures, and creates `dist/Dejima-<version>.dmg`. It also regenerates the Xcode project and replaces the contents of `build/release`.

For public distribution, configure a Developer ID Application signing identity and notarization credentials. Store a Keychain profile using the interactive prompt:

```bash
xcrun notarytool store-credentials dejima
```

With the release changes committed, run:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=dejima \
./Scripts/release.sh 0.3.0
```

Replace the identity and version with your own. The version argument creates a local `vX.Y.Z` tag on HEAD before building. If HEAD is already tagged, omit the argument, including when retrying a failed build. The script does not push tags or publish a GitHub release.

Release versions come from the tag; build numbers come from the Git commit count. The script passes both to Xcode, so a release does not require editing `MARKETING_VERSION` in `project.yml`. That setting supplies the version for ordinary development builds. The updater compares the published release tag with the running app's bundle version.

Without `CODE_SIGN_IDENTITY`, the script uses the project's signing configuration. Without `NOTARY_PROFILE`, it skips notarization. A development-signed or unnotarized package may be blocked by Gatekeeper when downloaded on another Mac.

The DMG contains one folder per minimum macOS version, each with `Dejima.app` and an Applications shortcut. Folder names and installation instructions are localized in English, Simplified Chinese, Japanese, and Korean.

DMG backgrounds are generated by `Scripts/dmg-window.swift`. The packaging steps and localized folder names are maintained in `Scripts/release.sh`.
