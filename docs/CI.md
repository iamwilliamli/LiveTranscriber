# Continuous integration

`Apple Platforms` runs for every pull request, pushes to `main` and `feature/**`, and manual dispatches. Its matrix keeps three failure domains visible as separate checks:

| Lane | Hosted toolchain | Verification |
| --- | --- | --- |
| Shared domain tests | Default Xcode on `macos-26` | Runs all `TranscriberDomain` and `TranscriberCore` tests. |
| iOS 26 compatibility build | Default Xcode on `macos-26` | Builds the complete iOS app and extensions without signing. |
| macOS app tests | Default Xcode on `macos-26` | Builds the native Mac app and runs its unit tests without signing. |

GitHub's hosted macOS image currently provides Xcode 26, while this repository also contains optional Xcode 27 SDK features. `HAS_IOS27_SDK` is therefore derived from the selected SDK instead of being forced globally:

- An Xcode 27 build compiles the Native Speech and structured Foundation Models paths.
- The hosted Xcode 26 lane compiles the supported compatibility paths and stubs only the SDK symbols that do not exist yet.
- The release gate still requires the full iOS build with Xcode 27 locally or in Xcode Cloud until GitHub hosts that toolchain.

## Local verification

Open the root `LiveTranscriber.xcworkspace` for both iOS and macOS, or run these commands from the repository root. Switch schemes to choose the platform. Do not set a temporary `-derivedDataPath`; Xcode's standard DerivedData directory preserves the same incremental behavior as the app.

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -workspace LiveTranscriber.xcworkspace \
  -scheme LiveTranscriber \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -quiet \
  build

/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -workspace LiveTranscriber.xcworkspace \
  -scheme LiveTranscriberMac \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  -quiet \
  test

/usr/bin/env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  /usr/bin/xcrun swift test \
  --package-path Packages/TranscriberDomain \
  --scratch-path "$HOME/Library/Developer/Xcode/DerivedData/TranscriberDomain-SwiftPM"

/usr/bin/env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  /usr/bin/xcrun swift test \
  --package-path Packages/Qwen3Speech \
  --scratch-path "$HOME/Library/Developer/Xcode/DerivedData/Qwen3Speech-SwiftPM"
```

Unsigned builds verify compilation and unit behavior only. Before release, smoke-test microphone recording on iPhone and ScreenCaptureKit capture on a signed Mac because TCC permissions, iCloud containers, audio devices, and capture selection cannot be validated reliably in hosted CI.

## Xcode package resolution

Use the root `LiveTranscriber.xcworkspace` for both apps. It contains `LiveTranscriber.xcodeproj` and `LiveTranscriberMac/LiveTranscriberMac.xcodeproj`; Xcode resolves their common local dependencies (`Packages/TranscriberDomain`, `Packages/Qwen3Speech`, and `Vendor/MLXAudioMOSS`) once in the workspace package graph.

If Xcode reports `Missing package product 'TranscriberDomain'` or `Missing package product 'TranscriberCore'`, first let its current package operation finish, then use **File > Packages > Resolve Package Versions**. The equivalent command is:

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -resolvePackageDependencies \
  -workspace LiveTranscriber.xcworkspace \
  -scheme LiveTranscriberMac
```

This preserves Xcode's standard incremental DerivedData. If the issue navigator still shows an old package error after resolution succeeds, close standalone project or legacy workspace windows and reopen only the root workspace; clearing all DerivedData should not be the first recovery step.
