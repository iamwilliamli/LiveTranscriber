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

Open `LiveTranscriber.xcworkspace`, or run these commands from the repository root. Do not set a temporary `-derivedDataPath`; Xcode's standard DerivedData directory preserves the same incremental behavior as the app.

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
```

Unsigned builds verify compilation and unit behavior only. Before release, smoke-test microphone recording on iPhone and ScreenCaptureKit capture on a signed Mac because TCC permissions, iCloud containers, audio devices, and capture selection cannot be validated reliably in hosted CI.

## Xcode package resolution

Always open `LiveTranscriber.xcworkspace`, not either `.xcodeproj` on its own. Both app projects consume the local `Packages/TranscriberDomain` package, and the workspace is the source of truth for resolving those shared products.

If Xcode reports `Missing package product 'TranscriberDomain'` or `Missing package product 'TranscriberCore'`, first let its current package operation finish, then use **File > Packages > Resolve Package Versions**. The equivalent command is:

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -resolvePackageDependencies \
  -workspace LiveTranscriber.xcworkspace \
  -scheme LiveTranscriberMac
```

This preserves Xcode's standard incremental DerivedData. If the issue navigator still shows the old error after resolution succeeds, close the project window and reopen `LiveTranscriber.xcworkspace`; clearing all DerivedData should not be the first recovery step.
