# Development

## Build

Install Xcode 26 or later with the macOS 26 SDK or later. The SDK requirement is separate from the app's minimum macOS version.

Xcode resolves Sparkle 2.10.0 through Swift Package Manager. Keep the committed `Package.resolved` file when building or releasing.

Command-line builds require the full Xcode installation selected with `xcode-select` or a per-command `DEVELOPER_DIR` override.

Open the checked-in project from the repository root:

```bash
open Dejima.xcodeproj
```

In each target's **Signing & Capabilities** settings, choose your team or **Sign to Run Locally**. Use a consistent signing identity when testing Accessibility access; changing signatures or app copies can require granting access again.

Choose a scheme and run it in Xcode, or build from the command line after configuring signing:

```bash
xcodebuild -project Dejima.xcodeproj -scheme Dejima -configuration Release -destination 'generic/platform=macOS' build
xcodebuild -project Dejima.xcodeproj -scheme Dejima26 -configuration Release -destination 'generic/platform=macOS' build
```

Run `./Scripts/test-release-preflight.sh` to check that invalid release settings stop before tagging or building. The tests use temporary fixtures and stub commands; they do not access signing credentials or notarization services.

## Translation targets

The targets share the app code and bundle identifier. Each includes one implementation of `TranslationHub`.

| Target | Minimum macOS | Translation session |
|---|---|---|
| `Dejima` | 15 | A SwiftUI `translationTask` attached to a hidden host window |
| `Dejima26` | 26 | `TranslationSession(installedSource:target:)` |

The legacy implementation can ask the framework to identify the source language and request language downloads. The direct session API requires a source language and installed models. The macOS 26 implementation retries language identification when the router has no confident result, and reports missing models as an error.

The `Dejima26` target produces `Dejima26.app` to avoid overwriting the other target's output. Packaging renames both builds to `Dejima.app` and puts them in separate folders.

Optional refinement uses Foundation Models when available on macOS 26 or later. Both targets include the same refinement code.

## First-run language setup

The permission guide continues to a shared language setup view after Accessibility is granted. Both targets use a visible `translationTask` session and `prepareTranslation()` to request any missing languages. The ordinary macOS 26 translation path still uses installed models directly.

Setup checks both directions for the two selected languages using the same default strategy as translation. Existing Apple Intelligence models can satisfy that check without downloading traditional language packs. A successful `prepareTranslation()` return is not proof that downloads have finished, so setup rechecks availability before enabling **Get started**. Closing or postponing setup does not mark it complete. Other source languages may need downloads later.

The menu opens the system's Translation Languages sheet using the link exposed by Apple's own download dialog. This was verified on macOS 27; if another system opens only Language & Region, the user can choose **Translation Languages…** there. First-run downloads use the public Translation API independently of this settings link.

## Verify Apple Intelligence use

Dejima has two distinct model paths:

- **Draft translation:** `TranslationSession` chooses its default strategy because Dejima does not explicitly select one. On macOS 26.4 or later, inspect `session.preferredStrategy` and the build SDK. Apple's [`highFidelity`](https://developer.apple.com/documentation/translation/translationsession/strategy/highfidelity) strategy prefers Apple Intelligence models and can fall back to traditional models. Existing Apple Intelligence models may satisfy the requirement without separate language downloads. A preferred strategy alone does not identify the model that handled a particular request.
- **Additional refinement:** the **Refine with Apple Intelligence** switch controls a separate `LanguageModelSession` call in `Sources/Shared/Polisher.swift`, after the draft is complete. It is off by default and requires `SystemLanguageModel.default.availability` to be `.available`. Turning it off does not force the draft translation to avoid Apple Intelligence.

Read the saved refinement preference without changing it:

```bash
defaults read com.nuki.Dejima polishWithAppleIntelligence
```

An unset key uses the default `false`. The running app also checks model availability. To confirm an individual request, use a Debug build with the intended signing identity and synthetic text:

1. Enable **Refine with Apple Intelligence** and translate the sample. In `Sources/Shared/Controller.swift`, confirm that `Polisher.isEnabled` is true before `result.beginRefining()`.
2. Set a breakpoint at `session.respond(to:)` in `Sources/Shared/Polisher.swift` to confirm that the additional request starts.
3. Inspect `response.content` after the await completes, and compare the trimmed `revised` value with `draft`. A nonempty identical response is still a successful model call. An empty response returns the draft.
4. Set another breakpoint in the `catch` block and inspect `error` to distinguish a failed request from successful unchanged output. The current app silently keeps the draft on failure.

The temporary **Refining…** label shows that the step started; it does not certify success. The final interface does not retain a refinement outcome, so the displayed text alone cannot distinguish disabled, unchanged, or failed refinement.

For timing and request inspection, use Apple's [Foundation Models instrument](https://developer.apple.com/documentation/FoundationModels/analyzing-the-runtime-performance-of-your-foundation-models-app). Use synthetic text for traces because they can contain prompts and responses. A standalone probe can verify model availability and the helper's behavior, but cannot establish that a previous request in the installed app used refinement.

## Source layout

The project's `Sources` group contains three file system synchronized folders. `Shared` belongs to both targets, `TranslationLegacy` only to `Dejima`, and `Translation26` only to `Dejima26`. Add shared Swift files under `Sources/Shared` and target-specific files under the matching translation folder; Xcode discovers them automatically.

- `Sources/Shared/Controller.swift` connects permissions, key monitoring, translation, and the result panel.
- `Sources/Shared/DoubleCopyMonitor.swift` detects the copy gesture and reads the clipboard.
- `Sources/Shared/LanguageRouter.swift` selects the translation direction; `TextCleaner.swift` repairs copied line breaks.
- `Sources/TranslationLegacy/` and `Sources/Translation26/` contain the target-specific translation implementations.
- `Sources/Shared/Polisher.swift` handles optional refinement and returns the draft on failure.
- `Sources/Shared/PermissionGuide.swift`, `MenuBarView.swift`, `ResultPanel.swift`, and `ResultView.swift` provide the interface.
- `Sources/Shared/LanguageSetup.swift` checks the selected languages and requests downloads during setup.
- `Sources/Shared/Updater.swift` manages Sparkle updates; `LoginItem.swift` manages launch at login.

UI translations are stored in `Localizable.xcstrings` and `InfoPlist.xcstrings`. These catalogs, `Assets.xcassets`, and `AppIcon.icon` are shared resources at the repository root. Keep them included in both targets and update the project's language list in Xcode when adding localizations.

## App icon

Edit `AppIcon.icon` in Icon Composer. Xcode uses it for both targets and generates compatible icons for older macOS releases. The menu bar symbol remains in `Sources/Shared/DejimaMark.swift`.

Run `./Scripts/app-icon.sh` with Xcode 27 selected to refresh the PNGs in `Assets.xcassets/AppIcon.appiconset`. These exports include the traditional macOS inset; packaging uses `icon_512.png` for DMG artwork and the volume icon.

## In-app updates

Sparkle 2.10.0 handles downloading, installing, and relaunching the app. **Check for updates** opens its standard update flow; the menu shows **Update available** when an update is waiting. Installation requires user confirmation, with silent automatic installation disabled.

Automatic checks are off by default. The existing `checkForUpdatesAutomatically` preference is migrated, and enabled checks run daily in the background. System profiling is disabled. Checks and downloads contact the GitHub update feeds and release download services without sending translated text.

The running macOS version selects `appcast-macos15.xml` on macOS 15–25 or `appcast-macos26.xml` on macOS 26 and later. Each feed points to a ZIP containing the corresponding single `Dejima.app`. The combined DMG remains the first-install and manual-install download. Users of older versions must install the first Sparkle-enabled release manually once.

The public update key is stored in `SUPublicEDKey` in `Info.plist`. Keep the matching private key in the login Keychain under account `com.nuki.Dejima`, or select its account with `SPARKLE_KEY_ACCOUNT` when packaging. Never commit the private key. Signed feeds and archives are required and verified before release artifacts are placed in `dist`.

## Local packaging

To test packaging with uncommitted changes:

```bash
./Scripts/release.sh --local 0.3.0
```

This builds both targets with ad-hoc signing in `build/local` and creates a `-local.dmg` plus two `-local.zip` archives in `dist`. It does not create tags, notarize, update provisioning assets, or generate update feeds. These packages are for local testing and must not be published as production updates.

## Package a release

Public release packaging requires a clean working tree, a valid Developer ID Application identity with its private key, a notarization Keychain profile, and the matching Sparkle signing key in Keychain. Missing or invalid credentials stop the script before it creates a tag. Public packaging does not fall back to development signing.

Store notarization credentials in a Keychain profile using the interactive prompt:

```bash
xcrun notarytool store-credentials dejima
```

With the release changes committed, run:

```bash
./Scripts/release.sh 0.3.0
```

Replace the version with your own. The notarization profile defaults to `dejima`; set `NOTARY_PROFILE` to use another. If exactly one valid Developer ID Application identity is installed, it is selected automatically; otherwise set `CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"`. The version argument creates a local `vX.Y.Z` tag on HEAD after preflight checks and before building. If HEAD is already tagged, omit the argument, including when retrying a failed build. The script does not push tags or publish a GitHub release.

Release versions come from the tag. The script sets both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to that version, so `CFBundleShortVersionString` and `CFBundleVersion` match. Sparkle compares `CFBundleVersion` to determine update order; use an increasing version for each release. The project settings supply the versions for ordinary development builds.

The script replaces `build/release`, archives and exports both targets, verifies Developer ID signatures, notarizes the DMG and staples the tickets, then signs and verifies the update feeds and archives. Successful packaging produces five files in `dist`:

| File | Purpose |
| --- | --- |
| `Dejima-<version>.dmg` | Both variants for first or manual installation |
| `Dejima-<version>-macos15.zip` | App update for macOS 15–25 |
| `Dejima-<version>-macos26.zip` | App update for macOS 26 and later |
| `appcast-macos15.xml` | Signed update feed for macOS 15–25 |
| `appcast-macos26.xml` | Signed update feed for macOS 26 and later |

Push the tag and upload all five files to the same GitHub release as a separate publishing step. The app reads the latest release's feeds, whose archive links point to the matching versioned release downloads. Upload the complete set before publishing the release.

The DMG contains one folder per minimum macOS version, each with `Dejima.app` and an Applications shortcut. Folder names and installation instructions are localized in English, Simplified Chinese, Japanese, and Korean.

DMG backgrounds are generated by `Scripts/dmg-window.swift`. The packaging steps and localized folder names are maintained in `Scripts/release.sh`.
