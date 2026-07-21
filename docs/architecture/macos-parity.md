# macOS feature-parity matrix

This matrix is the release gate for the native macOS product. “Equivalent” means the same user capability is present through a native macOS interaction; it does not require copying an iPhone layout literally. A row may be marked complete only after both source review and a runnable macOS smoke test.

| Area | iOS capability | Native macOS implementation | Status | Remaining verification or work |
| --- | --- | --- | --- | --- |
| App shell | Transcribe, Recordings, Settings tabs | Three sidebar destinations: Transcribe, Recordings, and Settings | Complete | Visual smoke test at narrow and wide window sizes |
| Introduction | Feature overview, language, format, recommended MOSS and summary-model setup | First-run `MacOnboardingView` with the same choices and downloads | Complete | Signed download smoke test |
| Launch presentation | Animated launch splash | Shared launch splash followed by the native first-run introduction | Complete | Visual timing smoke test in a signed app |
| Live recording | Start, pause, resume, stop; waveform, elapsed time and status | `MacTranscriptionView` with keyboard shortcut and native controls | Complete | Signed microphone permission smoke test |
| Live language allocation | Apple Speech language selection and old-locale release prompt | Matching preparation/release flow; selection no longer accidentally starts recording | Complete | Test on a Mac with the system locale limit reached |
| Live transcript | Interim/final lines, copy and edit final lines | Native scroll list, context-menu copy and final-line editor | Complete | Manual recording smoke test |
| Live translation | Choose Apple Translation target and translate completed lines while recording | Translation menu, per-line translated/original text and progress/error state | Complete | Test first-time language-pack installation |
| Live system status | Live Activity / Dynamic Island | Menu-bar status item with state, elapsed time, latest line and Show App | Equivalent | Signed runtime smoke test |
| Save recording | Name, generated title/tags/summary, category, key points, tags, duration and optional location | Native save form with all corresponding metadata and location preview | Complete | Signed location permission smoke test |
| Recording import | Audio document import and Photos/video import | Multi-select Finder importer for audio and movie files | Equivalent | Add drag-and-drop convenience |
| Recordings library | Search, category filters, map and refresh | Split-view list/detail, search, categories, recording map and refresh | Complete | Add richer row context-menu shortcuts |
| Category management | Create, rename, icon/color, delete, assign recordings | Native category organizer and recording edit/category assignment | Complete | Add multi-recording assignment convenience |
| Playback | Play/pause, seek, skip, speed, active-line following | Native playback card with all matching controls | Complete | Keyboard/media-key smoke test |
| Recording metadata | Name, language, category, tags, key points, summary and location editing | `MacRecordingEditSheet`, including add/replace/remove location | Complete | Visual smoke test with long metadata |
| Transcript editing | Edit text and speaker; optionally propagate speaker through immediately consecutive same-speaker segments | Matching editor and propagation confirmation constrained to consecutive segments | Complete | Add regression tests for propagation boundaries |
| Saved translation | Apple Translation target, translated/original lines and translated analysis input | Matching translation menu, cache, progress/error state and analysis handoff | Complete | Test first-time language-pack installation |
| Re-transcription | Apple language picker/release prompt; Whisper model/language picker; Qwen3-ASR; MOSS; Gemini | Matching native pickers, availability gating and all engines | Complete | Signed model-runtime smoke tests |
| Manual Gemini | Copy prompt/share audio, import JSON and restore pre-Gemini transcript | Native share picker, paste/import sheet and restore confirmation | Complete | Gemini app round-trip smoke test |
| AI analysis | Provider choice, summary, meeting analysis and recording chat | Matching provider menus, summary/meeting cards and shared chat UI | Complete | Signed Apple Intelligence and local-model smoke tests |
| Reminders | Review/edit action items before saving | Native editable review sheet and Reminders export | Complete | Signed Reminders permission smoke test |
| Audio events | Analyze, display confidence/time ranges and seek | Native analysis sheet, event chips and seek | Complete | Test supported/unsupported hardware |
| Export and sharing | Share audio; TXT, Markdown, SRT, VTT and JSON | ShareLink/native save panels for the same formats | Complete | Verify sandbox destinations |
| File visibility | Files app export/access | Show Audio in Finder and Open Recordings Folder | Equivalent | Clarify managed private storage versus user exports in help text |
| Settings: transcription | Language, live backend, Whisper/Core ML, Qwen, MOSS decoder recommendation and Gemini | Native transcription settings pane with matching controls/downloads | Complete | Signed download/delete smoke tests |
| Settings: intelligence | Provider, Apple availability and local summary model management | Native intelligence pane | Complete | Signed local-model smoke test |
| Settings: recording/files/privacy/developer | Format, iCloud, sync detail, privacy explanations, diagnostics and intro reset | Dedicated native panes, Finder access, and live permission status/actions | Complete | Signed permission-status smoke test |
| Feedback and policy | Public beta, email feedback and privacy-policy links | Native Help settings pane | Complete | Verify default mail client behavior |
| Permission management | Usage explanations plus system permission behavior | Live microphone, speech, location, screen-recording and Reminders status with Open System Settings actions | Complete | Signed permission prompt and settings-link smoke test |
| Shortcuts and intents | App Shortcuts / recording intents | Shared App Intents sources compile into macOS target | Partial | Verify donation, phrases and invocation in a signed build |
| Localization | Shared localized UI in supported languages | Shared catalogs plus the translated Mac-specific `MacSemantic.strings` catalog in all six supported locales | Complete | Visual pseudo-localization and truncation smoke test |
| System-audio recording | Microphone recording | Transcribe offers system-only and system-plus-microphone modes for a selected display/app/window, saves one M4A through `RecordingStore`, and never silently substitutes microphone audio | Mac extension complete | Signed Zoom/Teams/Meet audio smoke tests |
| Project generation | Xcode project reproducible from source spec | `LiveTranscriberMac.xcodeproj` is regenerated from the checked-in `project.yml` | Complete | Keep regeneration in the macOS build verification lane |
| CI/toolchains | iOS and macOS builds | Xcode 27 iOS build and macOS tests pass locally | Partial | Repair the Xcode 26 iOS GenerationOptions compatibility failure and add both products to CI |

## Release rule

Do not describe the macOS app as having full parity while any row above is `Partial`. Platform-specific equivalents are acceptable, but silent omissions and no-op stubs are not.
