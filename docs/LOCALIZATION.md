# Localization

LiveTranscriber uses semantic localization keys for new and migrated UI text.

Currently supported app UI locales are `en`, `zh-Hans`, `zh-Hant`, `de`, `nl`, and `ja`.

## Rule

Do not add new user-visible strings as Chinese source keys in Swift code. Avoid this pattern:

```swift
Text("录音文件")
String(localized: "正在分析")
```

Instead, add a semantic key to `LiveTranscriber/Semantic.xcstrings`, expose it from `LiveTranscriber/L10n.swift`, and reference that resource from Swift.

```swift
Text(L10n.Recordings.title)
String(localized: L10n.Recordings.analyzing)
```

## Files

- `LiveTranscriber/Semantic.xcstrings`: the primary string catalog for semantic app strings.
- `LiveTranscriber/L10n.swift`: typed accessors grouped by feature area, such as `L10n.Recordings`, `L10n.Source`, `L10n.ICloud`, and `L10n.Intelligence`.
- `LiveTranscriber/en.lproj/InfoPlist.strings` and `LiveTranscriber/zh-Hans.lproj/InfoPlist.strings`: system-facing strings such as privacy permission prompts.

## How to Add Text

1. Add a semantic key to `Semantic.xcstrings`.
   - Use stable feature-oriented keys such as `recordings.delete_failed`, not source text.
   - Keep `en` and `zh-Hans` values together.
   - Use English `defaultValue` in code.
2. Add a matching accessor in `L10n.swift`.
   - Group it under the owning feature area.
   - Add a short comment describing where the text appears.
3. Use `LocalizedStringResource` directly in SwiftUI when possible.
   - `Text(L10n.Recordings.title)`
   - `Button { save() } label: { Text(L10n.Common.save) }`
   - `EmptyStateView(icon: "map", titleResource: L10n.Recordings.noLocatedRecordings)`
4. Use `String(localized:)` only when an API needs a `String`.
   - `.navigationTitle(String(localized: L10n.Recordings.mapTitle))`
   - `errorText = String(localized: L10n.Recordings.locationUnavailable)`

For formatted strings, keep the format in the catalog and pass values from code:

```swift
String(
    format: String(localized: L10n.Recordings.deleteConfirmationFormat),
    recordingName
)
```

Do not localize user data such as recording names, tags, transcript text, location names, language display names, or system error descriptions.

## Shared Views

If a shared SwiftUI helper only accepts `LocalizedStringKey`, add an overload that accepts `LocalizedStringResource` instead of converting a semantic string back into a source-text key.

Preferred:

```swift
init(titleResource: LocalizedStringResource) {
    self.title = Text(titleResource)
}
```

Avoid:

```swift
init(title: String) {
    self.title = Text(LocalizedStringKey(title))
}
```

The string-based initializer may remain for legacy callers, but migrated callers should use the resource initializer.

## Adding a New Language

1. Add the new locale to `LiveTranscriber/Semantic.xcstrings` in Xcode.
   - Open the string catalog.
   - Add the target language, such as `ja`, `fr`, or `de`.
   - Translate every semantic key in the catalog.
2. Keep Swift code unchanged.
   - Swift should keep calling `L10n.Feature.key`.
   - Do not add language-specific branches for UI text.
3. Localize system-facing strings separately when needed.
   - Permission prompts, display names, and other Info.plist-facing text should live in the appropriate `InfoPlist.strings` or legacy `.lproj` file if they are not already in a string catalog.
   - Do not recreate `Localizable.strings` for app UI. Add app UI text to `Semantic.xcstrings` instead.
4. Test the language in Xcode.
   - Use the scheme run options to set App Language, or change the simulator/device language.
   - Check recording, recordings list, detail, settings, source information, import, save, translation, and error states.
5. Verify that the language did not introduce source-code strings.
   - New user-visible text still needs a semantic key and `L10n.swift` accessor.
   - Dynamic user content, including recording names, transcript text, tags, place names, language display names, and system error descriptions, should not be translated through app localization files.

## Verification

Before finishing localization work, run:

```sh
jq empty LiveTranscriber/Semantic.xcstrings
git diff --check
rg -n "[\\p{Han}]" --glob '*.swift' LiveTranscriber LiveTranscriberWidget
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project LiveTranscriber.xcodeproj \
  -scheme LiveTranscriber \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/LiveTranscriberDerivedDataLocalization \
  -quiet build
```

For migrated Swift code, the `rg` command should return no user-visible Chinese source text. Chinese translations belong in `.xcstrings` or `.strings` files, not Swift source.
