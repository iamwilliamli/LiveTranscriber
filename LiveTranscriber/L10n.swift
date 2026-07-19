import Foundation

enum L10n {
    private static let semanticTable = "Semantic"

    fileprivate static func resource(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        comment: StaticString
    ) -> LocalizedStringResource {
        LocalizedStringResource(
            key,
            defaultValue: defaultValue,
            table: semanticTable,
            comment: comment
        )
    }

    enum Splash {
        static let tagline = L10n.resource(
            "splash.tagline",
            defaultValue: "Unboxed. Ready to record.",
            comment: "Tagline under the app name on the animated launch splash."
        )
    }

    enum Common {
        static let unknown = L10n.resource(
            "common.unknown",
            defaultValue: "Unknown",
            comment: "Fallback text when a value is unavailable."
        )
        static let ok = L10n.resource(
            "common.ok",
            defaultValue: "OK",
            comment: "Generic OK button title."
        )
        static let cancel = L10n.resource(
            "common.cancel",
            defaultValue: "Cancel",
            comment: "Generic cancel button title."
        )
        static let copy = L10n.resource(
            "common.copy",
            defaultValue: "Copy",
            comment: "Generic copy action title."
        )
        static let done = L10n.resource(
            "common.done",
            defaultValue: "Done",
            comment: "Generic done button title."
        )
        static let delete = L10n.resource(
            "common.delete",
            defaultValue: "Delete",
            comment: "Generic delete button title."
        )
        static let save = L10n.resource(
            "common.save",
            defaultValue: "Save",
            comment: "Generic save button title."
        )
        static let back = L10n.resource(
            "common.back",
            defaultValue: "Back",
            comment: "Accessibility label for a back button."
        )
        static let more = L10n.resource(
            "common.more",
            defaultValue: "More",
            comment: "Accessibility label for a more actions button."
        )
        static let notApplicable = L10n.resource(
            "common.not_applicable",
            defaultValue: "Not Applicable",
            comment: "Fallback text when a value does not apply."
        )
    }

    enum App {
        static let transcribeTab = L10n.resource("app.tab.transcribe", defaultValue: "Transcribe", comment: "Main tab title for live transcription.")
        static let recordingsTab = L10n.resource("app.tab.recordings", defaultValue: "Recordings", comment: "Main tab title for saved recordings.")
        static let settingsTab = L10n.resource("app.tab.settings", defaultValue: "Settings", comment: "Main tab title for settings.")
    }

    enum Onboarding {
        static let title = L10n.resource("onboarding.title", defaultValue: "Live Transcriber", comment: "Onboarding hero title.")
        static let caption = L10n.resource("onboarding.caption", defaultValue: "Capture speech, keep searchable recordings, and choose the transcription path that fits the moment.", comment: "Onboarding hero caption.")
        static let liveTitle = L10n.resource("onboarding.feature.live.title", defaultValue: "Live captions that stay with the audio", comment: "Onboarding feature title for live transcription.")
        static let liveDetail = L10n.resource("onboarding.feature.live.detail", defaultValue: "Record meetings, lectures, calls, or field notes with timed transcript lines ready as soon as you stop.", comment: "Onboarding feature description for live transcription.")
        static let recordingsTitle = L10n.resource("onboarding.feature.recordings.title", defaultValue: "A focused library for every recording", comment: "Onboarding feature title for saved recordings.")
        static let recordingsDetail = L10n.resource("onboarding.feature.recordings.detail", defaultValue: "Import audio, retranscribe with Apple Speech or Local Whisper, translate transcripts, and add tags or summaries.", comment: "Onboarding feature description for recordings.")
        static let privacyTitle = L10n.resource("onboarding.feature.privacy.title", defaultValue: "Local-first by default", comment: "Onboarding feature title for privacy.")
        static let privacyDetail = L10n.resource("onboarding.feature.privacy.detail", defaultValue: "Speech, files, and summaries stay on this iPhone unless you explicitly enable an online option for a saved recording.", comment: "Onboarding feature description for privacy.")
        static let setupTitle = L10n.resource("onboarding.setup.title", defaultValue: "Quick setup", comment: "Onboarding setup section title.")
        static let languageTitle = L10n.resource("onboarding.setup.language", defaultValue: "Transcription Language", comment: "Onboarding language setting title.")
        static let formatTitle = L10n.resource("onboarding.setup.format", defaultValue: "Recording Format", comment: "Onboarding recording format setting title.")
        static let whisperModelTitle = L10n.resource("onboarding.setup.whisper_model", defaultValue: "Local Whisper Model", comment: "Onboarding Local Whisper model picker title.")
        static let downloadWhisperFormat = L10n.resource("onboarding.setup.download_whisper.format", defaultValue: "Download Whisper Model (%@)", comment: "Onboarding Local Whisper download button. Parameter: model download size.")
        static let footer = L10n.resource("onboarding.footer", defaultValue: "You can change these choices later in Settings. Microphone and Speech permissions are requested only when the related feature needs them.", comment: "Onboarding footer privacy and settings note.")
        static let heroSplashTitle = L10n.resource("onboarding.hero_splash.title", defaultValue: "Capture now. Revisit everything.", comment: "Onboarding splash hero title.")
        static let heroSplashCaption = L10n.resource("onboarding.hero_splash.caption", defaultValue: "Live captions, saved audio, offline Whisper, and private transcript tools in one place.", comment: "Onboarding splash hero caption.")
        static let heroChipLive = L10n.resource("onboarding.hero_chip.live", defaultValue: "Live transcript", comment: "Onboarding hero status chip for live transcription.")
        static let heroChipWhisper = L10n.resource("onboarding.hero_chip.whisper", defaultValue: "Whisper ready", comment: "Onboarding hero status chip for Local Whisper.")
        static let heroChipPrivate = L10n.resource("onboarding.hero_chip.private", defaultValue: "On device", comment: "Onboarding hero status chip for privacy.")
        static let carouselCaptureTitle = L10n.resource("onboarding.carousel.capture.title", defaultValue: "Live Capture", comment: "Onboarding splash carousel card title for live capture.")
        static let carouselCaptureDetail = L10n.resource("onboarding.carousel.capture.detail", defaultValue: "Turn speech into timed lines", comment: "Onboarding splash carousel card detail for live capture.")
        static let carouselLibraryTitle = L10n.resource("onboarding.carousel.library.title", defaultValue: "Audio Library", comment: "Onboarding splash carousel card title for library.")
        static let carouselLibraryDetail = L10n.resource("onboarding.carousel.library.detail", defaultValue: "Import, search, and replay", comment: "Onboarding splash carousel card detail for library.")
        static let carouselWhisperTitle = L10n.resource("onboarding.carousel.whisper.title", defaultValue: "Local Whisper", comment: "Onboarding splash carousel card title for Local Whisper.")
        static let carouselWhisperDetail = L10n.resource("onboarding.carousel.whisper.detail", defaultValue: "Download offline models", comment: "Onboarding splash carousel card detail for Local Whisper.")
        static let carouselPrivateTitle = L10n.resource("onboarding.carousel.private.title", defaultValue: "Private Notes", comment: "Onboarding splash carousel card title for privacy.")
        static let carouselPrivateDetail = L10n.resource("onboarding.carousel.private.detail", defaultValue: "Keep work on this iPhone", comment: "Onboarding splash carousel card detail for privacy.")
        static let cta = L10n.resource("onboarding.cta", defaultValue: "Start Transcribing", comment: "Onboarding primary call to action.")
        static let useDefaults = L10n.resource("onboarding.use_defaults", defaultValue: "Use Defaults", comment: "Onboarding secondary action to continue with default settings.")
    }

    enum Settings {
        static let title = L10n.resource("settings.title", defaultValue: "Settings", comment: "Settings screen title.")
        static let transcription = L10n.resource("settings.transcription", defaultValue: "Transcription", comment: "Settings section title for transcription.")
        static let recording = L10n.resource("settings.recording", defaultValue: "Recording", comment: "Settings section title for recording.")
        static let files = L10n.resource("settings.files", defaultValue: "Files", comment: "Settings section title for files.")
        static let privacy = L10n.resource("settings.privacy", defaultValue: "Privacy", comment: "Settings section title for privacy.")
        static let privacyPolicy = L10n.resource("settings.privacy_policy", defaultValue: "Privacy Policy", comment: "Settings link title for opening the app privacy policy.")
        static let localProcessing = L10n.resource("settings.local_processing", defaultValue: "Local Processing", comment: "Privacy setting value and section title.")
        static let developerOptions = L10n.resource("settings.developer_options", defaultValue: "Developer Options", comment: "Developer options settings title.")
        static let languageAndModel = L10n.resource("settings.subtitle.language_model", defaultValue: "Language and transcription model", comment: "Settings row subtitle.")
        static let audioFormatAndBehavior = L10n.resource("settings.subtitle.audio_format_behavior", defaultValue: "Audio format and recording behavior", comment: "Settings row subtitle.")
        static let storageLocationAndCount = L10n.resource("settings.subtitle.storage_location_count", defaultValue: "Storage location and recording count", comment: "Settings row subtitle.")
        static let dataBoundariesAndPermissions = L10n.resource("settings.subtitle.data_boundaries_permissions", defaultValue: "Data boundaries and permission usage", comment: "Settings row subtitle.")
        static let deviceAndPipelineDiagnostics = L10n.resource("settings.subtitle.device_pipeline_diagnostics", defaultValue: "Device and pipeline diagnostics", comment: "Settings row subtitle.")
        static let publicBetaFeedback = L10n.resource("settings.public_beta_feedback", defaultValue: "Public Beta Feedback", comment: "Settings row title for opening the public beta Telegram feedback group.")
        static let feedback = L10n.resource("settings.feedback", defaultValue: "Feedback", comment: "Settings row title for sending feedback email.")
        static let feedbackUnavailable = L10n.resource("settings.feedback.unavailable", defaultValue: "Feedback Unavailable", comment: "Alert title when feedback email cannot be opened.")
        static let feedbackOpenFailedFormat = L10n.resource("settings.feedback.open_failed.format", defaultValue: "No mail app is configured. Send feedback to %@.", comment: "Alert message when feedback email cannot be opened. Parameter: feedback email address.")
        static let feedbackEmailSubjectFormat = L10n.resource("settings.feedback.email_subject.format", defaultValue: "LiveTranscriber Feedback - %@", comment: "Feedback email subject. Parameter: app version.")
        static let feedbackEmailGreeting = L10n.resource("settings.feedback.email.greeting", defaultValue: "Hi,", comment: "Greeting at the start of the feedback email template.")
        static let feedbackEmailPrompt = L10n.resource("settings.feedback.email.prompt", defaultValue: "Please describe your feedback or issue here:", comment: "Prompt in the feedback email template.")
        static let feedbackEmailSteps = L10n.resource("settings.feedback.email.steps", defaultValue: "Steps to reproduce:", comment: "Steps section heading in the feedback email template.")
        static let feedbackEmailExpected = L10n.resource("settings.feedback.email.expected", defaultValue: "Expected result:", comment: "Expected result heading in the feedback email template.")
        static let feedbackEmailActual = L10n.resource("settings.feedback.email.actual", defaultValue: "Actual result:", comment: "Actual result heading in the feedback email template.")
        static let feedbackEmailDiagnostics = L10n.resource("settings.feedback.email.diagnostics", defaultValue: "Diagnostics", comment: "Diagnostics heading in the feedback email template.")
        static let feedbackEmailApp = L10n.resource("settings.feedback.email.app", defaultValue: "App", comment: "App label in the feedback email diagnostics.")
        static let feedbackEmailCurrentPipeline = L10n.resource("settings.feedback.email.current_pipeline", defaultValue: "Current Pipeline", comment: "Current speech pipeline label in feedback diagnostics.")
        static let feedbackEmailConfiguredPipeline = L10n.resource("settings.feedback.email.configured_pipeline", defaultValue: "Configured Pipeline", comment: "Configured speech pipeline label in feedback diagnostics.")
        static let feedbackEmailSelectedLanguage = L10n.resource("settings.feedback.email.selected_language", defaultValue: "Selected Language", comment: "Selected transcription language label in feedback diagnostics.")
        static let feedbackEmailLiveBackend = L10n.resource("settings.feedback.email.live_backend", defaultValue: "Live Backend", comment: "Live transcription backend label in feedback diagnostics.")
        static let feedbackEmailLocalWhisperModel = L10n.resource("settings.feedback.email.local_whisper_model", defaultValue: "Local Whisper Model", comment: "Local Whisper model label in feedback diagnostics.")
        static let feedbackEmailRealtimeWhisperModel = L10n.resource("settings.feedback.email.realtime_whisper_model", defaultValue: "Realtime Whisper Model", comment: "Realtime Whisper model label in feedback diagnostics.")
        static let feedbackEmailSummaryEngine = L10n.resource("settings.feedback.email.summary_engine", defaultValue: "Summary Engine", comment: "Summary engine label in feedback diagnostics.")
        static let feedbackEmailLocalSummaryModel = L10n.resource("settings.feedback.email.local_summary_model", defaultValue: "Local Summary Model", comment: "Local summary model label in feedback diagnostics.")
        static let feedbackEmailLocalSummaryStatus = L10n.resource("settings.feedback.email.local_summary_status", defaultValue: "Local Summary Status", comment: "Local summary model status label in feedback diagnostics.")
        static let feedbackEmailCoreMLEncoderLoading = L10n.resource("settings.feedback.email.core_ml_encoder_loading", defaultValue: "Core ML Encoder Loading", comment: "Core ML encoder loading label in feedback diagnostics.")
        static let transcriptionLanguage = L10n.resource("settings.transcription_language", defaultValue: "Transcription Language", comment: "Settings row title for transcription language.")
        static let betaFeatures = L10n.resource("settings.beta_features", defaultValue: "Beta Features", comment: "Settings section title for beta features.")
        static let localWhisperLiveBeta = L10n.resource("settings.local_whisper_live_beta", defaultValue: "Local Whisper Live", comment: "Settings toggle title for beta live Local Whisper transcription.")
        static let localWhisperLiveBetaDescription = L10n.resource("settings.local_whisper_live_beta.description", defaultValue: "Use the selected realtime model while recording. This is offline, experimental, and uses Whisper-supported languages.", comment: "Settings toggle description for beta live Local Whisper transcription.")
        static let localWhisperLiveBetaRequiresSelection = L10n.resource("settings.local_whisper_live_beta.requires_selection", defaultValue: "Choose a realtime transcription model before using Local Whisper Live.", comment: "Settings warning shown when live Local Whisper beta is enabled without a selected live model.")
        static let localWhisperLiveBetaRequiresModel = L10n.resource("settings.local_whisper_live_beta.requires_model", defaultValue: "Download the selected realtime model before starting Local Whisper Live.", comment: "Settings warning shown when live Local Whisper beta is enabled without a downloaded model.")
        static let nextStartUsesLanguage = L10n.resource("settings.next_start_uses_language", defaultValue: "The selected language will be used next time recording starts", comment: "Transcription language row subtitle.")
        static let cannotChangeLanguageWhileRecording = L10n.resource("settings.cannot_change_language_while_recording", defaultValue: "Language cannot be changed while recording", comment: "Warning shown while recording.")
        static let recordingFormat = L10n.resource("settings.recording_format", defaultValue: "Recording Format", comment: "Settings row title for recording format.")
        static let cannotChangeFormatWhileRecording = L10n.resource("settings.cannot_change_format_while_recording", defaultValue: "Format cannot be changed while recording", comment: "Warning shown while recording.")
        static let noDeveloperServers = L10n.resource("settings.privacy.no_developer_servers", defaultValue: "No developer-operated servers, third-party analytics, ads, or tracking are used. Optional cloud actions connect directly from this iPhone to the selected provider.", comment: "Privacy explanation.")
        static let onDeviceProcessing = L10n.resource("settings.privacy.on_device_processing", defaultValue: "Processing is local by default. Audio or transcript text is sent to Gemini only after you enable and explicitly choose the related cloud action.", comment: "Privacy explanation.")
        static let developerCannotAccessContent = L10n.resource("settings.privacy.developer_cannot_access_content", defaultValue: "Audio and transcripts are not uploaded to developer servers, and the developer cannot access user content.", comment: "Privacy explanation.")
        static let storage = L10n.resource("settings.storage", defaultValue: "Storage", comment: "Settings section title for storage.")
        static let currentLocation = L10n.resource("settings.current_location", defaultValue: "Current Location", comment: "Settings metric title for current storage location.")
        static let localThenICloudStorage = L10n.resource("settings.storage.local_then_icloud", defaultValue: "Recordings are saved in the local app-private container by default. When iCloud is enabled in Settings, recording files and the index are saved to the app-private iCloud container.", comment: "Storage privacy explanation.")
        static let indexSyncPrivateDatabase = L10n.resource("settings.storage.index_sync_private_database", defaultValue: "The recording index is stored locally by default. When iCloud is enabled, it syncs through the user's own CloudKit private database.", comment: "Storage privacy explanation.")
        static let deleteRemovesManagedFiles = L10n.resource("settings.storage.delete_removes_managed_files", defaultValue: "Deleting a recording removes the app-managed audio file and transcript text.", comment: "Storage privacy explanation.")
        static let permissionUsage = L10n.resource("settings.permission_usage", defaultValue: "Permission Usage", comment: "Settings section title for permission usage.")
        static let microphonePermissionUse = L10n.resource("settings.permission.microphone", defaultValue: "Microphone permission is only used for recording and live transcription.", comment: "Permission usage explanation.")
        static let speechPermissionUse = L10n.resource("settings.permission.speech", defaultValue: "Speech recognition permission is only used to convert user-selected recordings into text.", comment: "Permission usage explanation.")
        static let locationPermissionUse = L10n.resource("settings.permission.location", defaultValue: "Location permission is only used when the user chooses to add a location while saving a recording.", comment: "Permission usage explanation.")
        static let cameraPermissionUse = L10n.resource("settings.permission.camera", defaultValue: "The camera is not used for photos or video. The camera permission description only satisfies Apple capture framework review requirements.", comment: "Permission usage explanation.")
        static let backgroundAudioUse = L10n.resource("settings.permission.background_audio", defaultValue: "Background audio is only used to let recording or playback continue, not for other background tasks.", comment: "Permission usage explanation.")
        static let speechPipelineMode = L10n.resource("settings.speech_pipeline_mode", defaultValue: "Speech Pipeline Mode", comment: "Settings page title for speech pipeline mode.")
        static let cannotChangePipelineWhileRecording = L10n.resource("settings.cannot_change_pipeline_while_recording", defaultValue: "Pipeline cannot be changed while recording", comment: "Warning shown while recording.")
        static let recordingCount = L10n.resource("settings.recording_count", defaultValue: "Recording Count", comment: "Settings metric title.")
        static let storageLocation = L10n.resource("settings.storage_location", defaultValue: "Storage Location", comment: "Settings metric title.")
        static let iCloudSync = L10n.resource("settings.icloud_sync", defaultValue: "iCloud Sync", comment: "Settings toggle title.")
        static let iCloudSyncDescription = L10n.resource("settings.icloud_sync.description", defaultValue: "When enabled, new recordings and the index are saved to the app-private iCloud container. When disabled, they are saved in the local app-private container by default.", comment: "iCloud sync setting description.")
        static let iCloudStatus = L10n.resource("settings.icloud_status", defaultValue: "iCloud Status", comment: "Settings metric title.")
        static let iCloudProgress = L10n.resource("settings.icloud_progress", defaultValue: "iCloud Sync Progress", comment: "Settings metric title.")
        static let device = L10n.resource("settings.device", defaultValue: "Device", comment: "Developer settings metric title.")
        static let systemVersion = L10n.resource("settings.system_version", defaultValue: "System Version", comment: "Developer settings metric title.")
        static let version = L10n.resource("settings.version", defaultValue: "Version", comment: "Developer settings metric title.")
        static let buildTime = L10n.resource("settings.build_time", defaultValue: "Build Time", comment: "Developer settings metric title.")
        static let currentSpeechPipeline = L10n.resource("settings.current_speech_pipeline", defaultValue: "Current Speech Pipeline", comment: "Developer settings metric title.")
        static let switchPipelineSubtitle = L10n.resource("settings.switch_pipeline_subtitle", defaultValue: "Switch compatible mode or iOS 27 Native mode", comment: "Developer settings row subtitle.")
        static let advancedModel = L10n.resource("settings.advanced_model", defaultValue: "Advanced Model", comment: "Developer settings metric title.")
        static let intelligence = L10n.resource("settings.intelligence", defaultValue: "Intelligence", comment: "Settings section title for summaries and local intelligence models.")
        static let summariesAndLocalModels = L10n.resource("settings.subtitle.summaries_local_models", defaultValue: "Summaries and local model downloads", comment: "Settings row subtitle for summary intelligence settings.")
        static let showIntroduction = L10n.resource("settings.show_introduction", defaultValue: "Show Introduction", comment: "Settings action title to show onboarding again.")
    }

    enum Appearance {
        static let title = L10n.resource("appearance.title", defaultValue: "Appearance", comment: "Settings section title for appearance options.")
        static let subtitle = L10n.resource("appearance.subtitle", defaultValue: "Colors and interface style", comment: "Settings row subtitle for appearance options.")
        static let playbackGlass = L10n.resource("appearance.playback_glass", defaultValue: "Player Glass", comment: "Setting title for playback glass color.")
        static let playbackGlassRed = L10n.resource("appearance.playback_glass.red", defaultValue: "Red", comment: "Playback glass color option.")
        static let playbackGlassBlue = L10n.resource("appearance.playback_glass.blue", defaultValue: "Blue", comment: "Playback glass color option.")
        static let playbackGlassWhite = L10n.resource("appearance.playback_glass.white", defaultValue: "White", comment: "Playback glass color option.")
        static let playbackGlassGraphite = L10n.resource("appearance.playback_glass.graphite", defaultValue: "Graphite", comment: "Playback glass color option.")
    }

    enum Transcription {
        static let liveTranscription = L10n.resource("transcription.live", defaultValue: "Live Transcription", comment: "Live transcription section title.")
        static let wavDetail = L10n.resource("transcription.audio_format.wav_detail", defaultValue: "Lossless PCM, larger files", comment: "WAV recording format detail.")
        static let m4aDetail = L10n.resource("transcription.audio_format.m4a_detail", defaultValue: "AAC compression, smaller files", comment: "M4A recording format detail.")
        static let savedFormat = L10n.resource("transcription.saved.format", defaultValue: "Saved: %@", comment: "Saved recording banner. Parameter: recording name.")
        static let resume = L10n.resource("transcription.resume", defaultValue: "Resume", comment: "Resume recording button title.")
        static let pause = L10n.resource("transcription.pause", defaultValue: "Pause", comment: "Pause recording button title.")
        static let stop = L10n.resource("transcription.stop", defaultValue: "Stop", comment: "Stop recording button title.")
        static let saveRecording = L10n.resource("transcription.save_recording", defaultValue: "Save Recording", comment: "Save recording button or sheet title.")
        static let startRecording = L10n.resource("transcription.start_recording", defaultValue: "Start Recording", comment: "Start recording button title.")
        static let waitingForFinalSegments = L10n.resource("transcription.translation.waiting_final_segments", defaultValue: "Waiting for completed segments", comment: "Live translation status.")
        static let translatingFinalSegments = L10n.resource("transcription.translation.translating_final_segments", defaultValue: "Translating completed segments", comment: "Live translation status.")
        static let realTimeTranslation = L10n.resource("transcription.translation.real_time", defaultValue: "Live Translation", comment: "Live translation screen title.")
        static let stopLiveTranslation = L10n.resource("transcription.translation.stop_live", defaultValue: "Stop live translation", comment: "Live translation original-language subtitle.")
        static let translationLanguage = L10n.resource("transcription.translation.language", defaultValue: "Translation Language", comment: "Live translation language section title.")
        static let noTranslationLanguages = L10n.resource("transcription.translation.no_languages", defaultValue: "No translatable languages", comment: "Empty text for translation language list.")
        static let discard = L10n.resource("transcription.discard", defaultValue: "Discard", comment: "Discard unsaved recording button title.")
        static let titleGenerationFailed = L10n.resource("transcription.title_generation_failed", defaultValue: "Title Generation Failed", comment: "Alert title for recording title generation failure.")
        static let generateTitleAndTagsAccessibility = L10n.resource("transcription.generate_title_tags_accessibility", defaultValue: "Generate title, summary, and tags with AI", comment: "Accessibility label for title, summary, and tag generation button.")
    }

    enum TranscriptionBackend {
        static let appleOnDeviceTitle = L10n.resource("transcription.backend.apple.title", defaultValue: "Apple On-Device", comment: "Apple on-device transcription backend title.")
        static let appleOnDeviceDetail = L10n.resource("transcription.backend.apple.detail", defaultValue: "Private local transcription using Apple Speech.", comment: "Apple on-device transcription backend detail.")
        static let localWhisperBetaTitle = L10n.resource("transcription.backend.local_whisper_beta.title", defaultValue: "Local Whisper Live (Beta)", comment: "Local Whisper live transcription backend title.")
        static let localWhisperBetaDetail = L10n.resource("transcription.backend.local_whisper_beta.detail", defaultValue: "Experimental offline live transcription using whisper.cpp.", comment: "Local Whisper live transcription backend detail.")
    }

    enum LocalWhisper {
        static let modelTitle = L10n.resource("local_whisper.model.title", defaultValue: "Local Whisper Model", comment: "Settings section title for local Whisper model management.")
        static let selectedModel = L10n.resource("local_whisper.model.selected", defaultValue: "Loaded Model", comment: "Settings row title for the selected local Whisper model.")
        static let modelStatus = L10n.resource("local_whisper.model.status", defaultValue: "Model Status", comment: "Settings metric title for local Whisper model status.")
        static let modelReady = L10n.resource("local_whisper.model.ready", defaultValue: "Ready", comment: "Local Whisper model status when a model is available.")
        static let modelNotInstalled = L10n.resource("local_whisper.model.not_installed", defaultValue: "Not Installed", comment: "Local Whisper model status when a model is not installed.")
        static let modelDownloadedDetailFormat = L10n.resource("local_whisper.model.downloaded_detail.format", defaultValue: "%@ is downloaded on this iPhone (%@).", comment: "Local Whisper downloaded model detail. Parameters: model filename, file size.")
        static let modelBundledDetailFormat = L10n.resource("local_whisper.model.bundled_detail.format", defaultValue: "%@ is bundled with this app (%@).", comment: "Local Whisper bundled model detail. Parameters: model filename, file size.")
        static let modelMissingDetailFormat = L10n.resource("local_whisper.model.missing_detail.format", defaultValue: "Download %@ (%@) before using Local Whisper transcription.", comment: "Local Whisper missing model detail. Parameters: model name, expected size.")
        static let modelChoiceSubtitleFormat = L10n.resource("local_whisper.model.choice_subtitle.format", defaultValue: "%@. %@ - %@", comment: "Local Whisper model picker subtitle. Parameters: model detail, install status, expected model size.")
        static let downloadSelectedModel = L10n.resource("local_whisper.model.download_selected", defaultValue: "Download Selected Model", comment: "Settings button title to download the selected local Whisper model.")
        static let coreMLEncoderStatus = L10n.resource("local_whisper.coreml_encoder.status", defaultValue: "Core ML Encoder", comment: "Settings metric title for local Whisper Core ML encoder status.")
        static let coreMLEncoderLoading = L10n.resource("local_whisper.coreml_encoder.loading", defaultValue: "Load Core ML Encoder", comment: "Settings toggle title for enabling local Whisper Core ML encoder loading.")
        static let coreMLEncoderLoadingDescription = L10n.resource("local_whisper.coreml_encoder.loading.description", defaultValue: "Not recommended for most recordings. It can be slower or less accurate in live transcription. Off by default.", comment: "Settings toggle description for enabling local Whisper Core ML encoder loading.")
        static let downloadCoreMLEncoder = L10n.resource("local_whisper.coreml_encoder.download", defaultValue: "Download Core ML Encoder", comment: "Settings button title to download the Core ML encoder for a local Whisper model.")
        static let coreMLEncoderDownloadedDetailFormat = L10n.resource("local_whisper.coreml_encoder.downloaded_detail.format", defaultValue: "%@ Core ML encoder is downloaded on this iPhone (%@).", comment: "Core ML encoder downloaded detail. Parameters: model name, installed size.")
        static let coreMLEncoderBundledDetailFormat = L10n.resource("local_whisper.coreml_encoder.bundled_detail.format", defaultValue: "%@ Core ML encoder is bundled with this app (%@).", comment: "Core ML encoder bundled detail. Parameters: model name, installed size.")
        static let coreMLEncoderMissingDetailFormat = L10n.resource("local_whisper.coreml_encoder.missing_detail.format", defaultValue: "Optional Apple Neural Engine acceleration for %@. Download size is about %@.", comment: "Core ML encoder missing detail. Parameters: model name, expected download size.")
        static let downloadingCoreMLEncoderFormat = L10n.resource("local_whisper.coreml_encoder.downloading.format", defaultValue: "Downloading Encoder %.0f%%", comment: "Core ML encoder download progress. Parameter: percent complete.")
        static let downloadedModelsTitle = L10n.resource("local_whisper.model.downloaded.title", defaultValue: "Downloaded Models", comment: "Settings section title for downloaded local Whisper models.")
        static let deleteModelDownload = L10n.resource("local_whisper.model.delete_download", defaultValue: "Delete Download", comment: "Button label to delete one downloaded local Whisper model.")
        static let noDownloadedModels = L10n.resource("local_whisper.model.no_downloaded", defaultValue: "No downloaded Local Whisper models.", comment: "Empty state for downloaded local Whisper model management.")
        static let liveModelTitle = L10n.resource("local_whisper.live_model.title", defaultValue: "Realtime Transcription Model", comment: "Settings row title for selecting the beta live Local Whisper model.")
        static let liveModelNotSelected = L10n.resource("local_whisper.live_model.not_selected", defaultValue: "Not Selected", comment: "Settings value when no beta live Local Whisper model has been selected.")
        static let downloadLiveModel = L10n.resource("local_whisper.live_model.download", defaultValue: "Download Realtime Model", comment: "Settings button title to download the beta live Local Whisper model.")
        static let downloadingModelFormat = L10n.resource("local_whisper.model.downloading.format", defaultValue: "Downloading %.0f%%", comment: "Local Whisper model download progress. Parameter: percent complete.")
        static let downloadFailed = L10n.resource("local_whisper.model.download_failed", defaultValue: "Model Download Failed", comment: "Alert title when a local Whisper model download fails.")
        static let deleteFailed = L10n.resource("local_whisper.model.delete_failed", defaultValue: "Model Delete Failed", comment: "Alert title when deleting a local Whisper model fails.")
        static let runtimeUnavailable = L10n.resource("local_whisper.error.runtime_unavailable", defaultValue: "whisper.cpp is not embedded in this build.", comment: "Local Whisper error when the native runtime cannot be loaded.")
        static let missingSymbolFormat = L10n.resource("local_whisper.error.missing_symbol.format", defaultValue: "whisper.cpp is missing the required symbol: %@.", comment: "Local Whisper error when a native function cannot be found. Parameter: symbol name.")
        static let missingModel = L10n.resource("local_whisper.error.missing_model", defaultValue: "Download the Local Whisper model in Settings before running local Whisper transcription.", comment: "Local Whisper error when no model file can be found.")
        static let missingLiveModel = L10n.resource("local_whisper.error.missing_live_model", defaultValue: "Choose a realtime Local Whisper model in Beta Features before using Local Whisper Live.", comment: "Local Whisper error when no live model is selected.")
        static let audioConversionFailed = L10n.resource("local_whisper.error.audio_conversion_failed", defaultValue: "The audio file could not be converted for local Whisper transcription.", comment: "Local Whisper audio conversion error.")
        static let emptyAudio = L10n.resource("local_whisper.error.empty_audio", defaultValue: "The audio file has no samples to transcribe.", comment: "Local Whisper empty audio error.")
        static let modelDownloadFailed = L10n.resource("local_whisper.error.model_download_failed", defaultValue: "The Local Whisper model download did not produce a valid model file.", comment: "Local Whisper invalid downloaded model error.")
        static let contextCreationFailed = L10n.resource("local_whisper.error.context_creation_failed", defaultValue: "Local Whisper could not load the selected model.", comment: "Local Whisper model initialization error.")
        static let transcriptionFailed = L10n.resource("local_whisper.error.transcription_failed", defaultValue: "Local Whisper transcription failed.", comment: "Local Whisper inference error.")
        static let modelTinyTitle = L10n.resource("local_whisper.model.tiny.title", defaultValue: "Tiny Multilingual", comment: "Local Whisper tiny multilingual model name.")
        static let modelTinyDetail = L10n.resource("local_whisper.model.tiny.detail", defaultValue: "Fastest, lowest accuracy, supports multiple languages.", comment: "Local Whisper tiny multilingual model detail.")
        static let modelTinyEnglishTitle = L10n.resource("local_whisper.model.tiny_english.title", defaultValue: "Tiny English", comment: "Local Whisper tiny English-only model name.")
        static let modelTinyEnglishDetail = L10n.resource("local_whisper.model.tiny_english.detail", defaultValue: "Fastest English-only model.", comment: "Local Whisper tiny English-only model detail.")
        static let modelBaseTitle = L10n.resource("local_whisper.model.base.title", defaultValue: "Base Multilingual", comment: "Local Whisper base multilingual model name.")
        static let modelBaseDetail = L10n.resource("local_whisper.model.base.detail", defaultValue: "Recommended balance for offline transcription.", comment: "Local Whisper base multilingual model detail.")
        static let modelBaseEnglishTitle = L10n.resource("local_whisper.model.base_english.title", defaultValue: "Base English", comment: "Local Whisper base English-only model name.")
        static let modelBaseEnglishDetail = L10n.resource("local_whisper.model.base_english.detail", defaultValue: "Recommended balance for English-only transcription.", comment: "Local Whisper base English-only model detail.")
        static let modelSmallTitle = L10n.resource("local_whisper.model.small.title", defaultValue: "Small Multilingual", comment: "Local Whisper small multilingual model name.")
        static let modelSmallDetail = L10n.resource("local_whisper.model.small.detail", defaultValue: "Better quality, slower and larger.", comment: "Local Whisper small multilingual model detail.")
        static let modelSmallEnglishTitle = L10n.resource("local_whisper.model.small_english.title", defaultValue: "Small English", comment: "Local Whisper small English-only model name.")
        static let modelSmallEnglishDetail = L10n.resource("local_whisper.model.small_english.detail", defaultValue: "Better quality for English-only transcription.", comment: "Local Whisper small English-only model detail.")
        static let modelMediumTitle = L10n.resource("local_whisper.model.medium.title", defaultValue: "Medium Multilingual", comment: "Local Whisper medium multilingual model name.")
        static let modelMediumDetail = L10n.resource("local_whisper.model.medium.detail", defaultValue: "High quality, much slower and requires significantly more storage.", comment: "Local Whisper medium multilingual model detail.")
        static let modelMediumEnglishTitle = L10n.resource("local_whisper.model.medium_english.title", defaultValue: "Medium English", comment: "Local Whisper medium English-only model name.")
        static let modelMediumEnglishDetail = L10n.resource("local_whisper.model.medium_english.detail", defaultValue: "High quality for English-only transcription.", comment: "Local Whisper medium English-only model detail.")
        static let modelLargeV3TurboQ5Title = L10n.resource("local_whisper.model.large_v3_turbo_q5.title", defaultValue: "Large v3 Turbo Q5", comment: "Local Whisper large v3 turbo Q5 model name.")
        static let modelLargeV3TurboQ5Detail = L10n.resource("local_whisper.model.large_v3_turbo_q5.detail", defaultValue: "Large turbo model with quantization; stronger quality with lower storage than full large.", comment: "Local Whisper large v3 turbo Q5 model detail.")
        static let modelLargeV3Q5Title = L10n.resource("local_whisper.model.large_v3_q5.title", defaultValue: "Large v3 Q5", comment: "Local Whisper large v3 Q5 model name.")
        static let modelLargeV3Q5Detail = L10n.resource("local_whisper.model.large_v3_q5.detail", defaultValue: "Largest quantized multilingual model; best quality option, heaviest runtime.", comment: "Local Whisper large v3 Q5 model detail.")
        static let modelLargeV3Title = L10n.resource("local_whisper.model.large_v3.title", defaultValue: "Large v3", comment: "Local Whisper large v3 model name.")
        static let modelLargeV3Detail = L10n.resource("local_whisper.model.large_v3.detail", defaultValue: "Full large multilingual model; very large download and memory use.", comment: "Local Whisper large v3 model detail.")
    }

    enum SpeechText {
        static let runtimeInputWaitingRecording = L10n.resource("speech.runtime_input.waiting_recording", defaultValue: "Runtime Analyzer input: waiting for recording", comment: "Developer speech pipeline diagnostic.")
        static let runtimeInputWaitingFirstBuffer = L10n.resource("speech.runtime_input.waiting_first_buffer", defaultValue: "Runtime Analyzer input: waiting for first buffer", comment: "Developer speech pipeline diagnostic.")
        static let runtimeInputMicToAnalyzerFormat = L10n.resource("speech.runtime_input.mic_to_analyzer.format", defaultValue: "Runtime Analyzer input: Mic %@ -> Analyzer %@", comment: "Developer speech pipeline diagnostic. Parameters: mic format, analyzer format.")
        static let recordingStartFailedFormat = L10n.resource("speech.error.recording_start_failed.format", defaultValue: "Recording failed to start: %@", comment: "Recording start error. Parameter: error description.")
        static let recordingResumeFailed = L10n.resource("speech.error.recording_resume_failed", defaultValue: "Recording resume failed", comment: "Recording resume error.")
        static let recordingResumeFailedFormat = L10n.resource("speech.error.recording_resume_failed.format", defaultValue: "Recording resume failed: %@", comment: "Recording resume error. Parameter: error description.")
        static let localeSetupFailed = L10n.resource("speech.locale.setup_failed", defaultValue: "Speech language setup failed", comment: "Speech language asset setup error title.")
        static let releaseOldLanguagesTitle = L10n.resource("speech.locale.release_old.title", defaultValue: "Release old speech languages?", comment: "Confirmation title before releasing older speech language assets.")
        static let releaseOldLanguagesAction = L10n.resource("speech.locale.release_old.action", defaultValue: "Release and Continue", comment: "Confirmation action for releasing older speech language assets.")
        static let releaseOldLanguagesMessageFormat = L10n.resource("speech.locale.release_old.message.format", defaultValue: "Speech can keep up to %d languages ready. To use %@, release these older languages: %@.", comment: "Confirmation message before releasing older speech language assets. Parameters: maximum language count, target language name, released language names.")
        static let noReleasableLanguages = L10n.resource("speech.locale.no_releasable_languages", defaultValue: "No old speech languages can be released safely.", comment: "Speech language asset setup error when quota is full and there are no release candidates.")
        static let speechRestricted = L10n.resource("speech.error.restricted", defaultValue: "Speech recognition is restricted by the system", comment: "Speech permission error.")
        static let speechDenied = L10n.resource("speech.error.denied", defaultValue: "Speech recognition permission was denied", comment: "Speech permission error.")
        static let microphoneDenied = L10n.resource("speech.error.microphone_denied", defaultValue: "Microphone permission was denied", comment: "Microphone permission error.")
        static let compatiblePipelineDetail = L10n.resource("speech.pipeline.compatible.detail", defaultValue: "Uses 16 kHz mono Int16 input to keep iOS 26/27 timestamps stable.", comment: "Speech pipeline mode detail.")
        static let nativePipelineDetail = L10n.resource("speech.pipeline.native.detail", defaultValue: "Uses the iOS 27 compatibleWith converter so the system chooses the Speech input pipeline.", comment: "Speech pipeline mode detail.")
        static let supportedPipelinesIOS27 = L10n.resource("speech.pipeline.supported.ios27", defaultValue: "Supported pipelines: iOS 27 Native AnalyzerInputConverter; Compatible AVAudioConverter", comment: "Developer speech pipeline diagnostic.")
        static let analyzerAdaptiveIOS27 = L10n.resource("speech.pipeline.analyzer_adaptive.ios27", defaultValue: "Analyzer input: iOS 27 system-adaptive. Actual Hz is shown by Runtime Analyzer input while recording.", comment: "Developer speech pipeline diagnostic.")
        static let analyzerFixed16K = L10n.resource("speech.pipeline.analyzer_fixed_16k", defaultValue: "Analyzer input: 16 kHz / mono / Int16 PCM", comment: "Developer speech pipeline diagnostic.")
        static let localWhisperInput16K = L10n.resource("speech.pipeline.local_whisper.input_16k", defaultValue: "Local Whisper input: 16 kHz / mono / Float32 PCM", comment: "Developer Local Whisper pipeline diagnostic.")
        static let supportedPipelinesIOS26 = L10n.resource("speech.pipeline.supported.ios26", defaultValue: "Supported pipelines: iOS 26 AVAudioConverter fallback", comment: "Developer speech pipeline diagnostic.")
        static let supportedPipelinesLocalWhisper = L10n.resource("speech.pipeline.supported.local_whisper", defaultValue: "Supported pipeline: Local Whisper fixed 8 second chunks without overlap", comment: "Developer Local Whisper pipeline diagnostic.")
        static let cannotReadMicrophone = L10n.resource("speech.error.cannot_read_microphone", defaultValue: "Could not read microphone input", comment: "Speech pipeline error.")
        static let analyzerUnavailable = L10n.resource("speech.error.analyzer_unavailable", defaultValue: "Speech analyzer unavailable", comment: "Speech pipeline error.")
        static let unsupportedLanguage = L10n.resource("speech.error.unsupported_language", defaultValue: "This language is not supported", comment: "Speech pipeline error.")
        static let stereoUnsupported = L10n.resource("speech.error.stereo_unsupported", defaultValue: "The current microphone does not support AVCapture stereo capture", comment: "Speech pipeline error.")
        static let compatiblePipelineTitle = L10n.resource("speech.pipeline.compatible.title", defaultValue: "Compatible Pipeline", comment: "Speech pipeline mode title.")
        static let nativePipelineTitle = L10n.resource("speech.pipeline.native.title", defaultValue: "iOS 27 Native Pipeline", comment: "Speech pipeline mode title.")
        static let activeNativeCompatibleWith = L10n.resource("speech.pipeline.active.native_compatible_with", defaultValue: "iOS 27 Native compatibleWith", comment: "Active speech pipeline diagnostic value.")
        static let activeCompatibleAVAudioConverter = L10n.resource("speech.pipeline.active.compatible_avaudio_converter", defaultValue: "iOS 27 Compatible AVAudioConverter", comment: "Active speech pipeline diagnostic value.")
        static let activeIOS26AVAudioConverter = L10n.resource("speech.pipeline.active.ios26_avaudio_converter", defaultValue: "iOS 26 AVAudioConverter", comment: "Active speech pipeline diagnostic value.")
        static let activeLocalWhisper = L10n.resource("speech.pipeline.active.local_whisper", defaultValue: "Local Whisper Live", comment: "Active Local Whisper pipeline diagnostic value.")
    }

    enum Import {
        static let importingRecording = L10n.resource("import.status.importing_recording", defaultValue: "Importing recording", comment: "Import status message.")
        static let loadingVideo = L10n.resource("import.status.loading_video", defaultValue: "Loading video", comment: "Import status shown while loading a selected video from Photos or iCloud.")
        static let extractingAudio = L10n.resource("import.status.extracting_audio", defaultValue: "Extracting audio", comment: "Import status shown while extracting the audio track from a selected video.")
        static let videoImported = L10n.resource("import.status.video_imported", defaultValue: "Video imported", comment: "Import status shown briefly after a video's audio has been added to recordings.")
        static let preparingTranscription = L10n.resource("import.status.preparing_transcription", defaultValue: "Preparing transcription", comment: "Import status message.")
        static let transcribing = L10n.resource("import.status.transcribing", defaultValue: "Transcribing", comment: "Import status message.")
        static let videoUnavailable = L10n.resource("import.error.video_unavailable", defaultValue: "The selected video could not be loaded.", comment: "Error shown when a video selected from Photos cannot be loaded.")
        static let videoHasNoAudio = L10n.resource("import.error.video_has_no_audio", defaultValue: "The selected video has no audio track.", comment: "Error shown when a selected video contains no audio track.")
        static let audioExtractionFailed = L10n.resource("import.error.audio_extraction_failed", defaultValue: "The video's audio could not be extracted.", comment: "Error shown when AVFoundation cannot extract audio from a selected video.")
        static let emptyRecordingName = L10n.resource("import.error.empty_recording_name", defaultValue: "Recording name cannot be empty", comment: "Recording detail validation error.")
        static let duplicateRecordingName = L10n.resource("import.error.duplicate_recording_name", defaultValue: "A recording file with this name already exists", comment: "Recording detail validation error.")
        static let recordingFileNotFound = L10n.resource("import.error.recording_file_not_found", defaultValue: "Recording file could not be found", comment: "Recording detail validation error.")
        static let noRecognizedText = L10n.resource("import.error.no_recognized_text", defaultValue: "No text was recognized in the imported recording", comment: "Import transcription error.")
        static let transcriptionInterrupted = L10n.resource("import.error.transcription_interrupted", defaultValue: "Transcription was interrupted. Try again.", comment: "Import transcription error shown after the app restarts and finds an unfinished transcription status.")
        static let saveFailed = L10n.resource("import.error.save_failed", defaultValue: "Imported recording could not be saved", comment: "Import save error.")
        static let preparingGemini = L10n.resource("import.status.preparing_gemini", defaultValue: "Preparing for Gemini", comment: "Status shown while preparing a saved recording for Gemini Cloud processing.")
        static let uploadingToGemini = L10n.resource("import.status.uploading_to_gemini", defaultValue: "Uploading to Gemini", comment: "Status shown while uploading a saved recording to Gemini.")
        static let transcribingWithGemini = L10n.resource("import.status.transcribing_with_gemini", defaultValue: "Gemini is transcribing", comment: "Status shown while Gemini creates the cloud transcript.")
        static let analyzingWithGemini = L10n.resource("import.status.analyzing_with_gemini", defaultValue: "Gemini is analyzing", comment: "Status shown while Gemini generates summary and meeting intelligence.")
    }

    enum Recordings {
        static let title = L10n.resource("recordings.title", defaultValue: "Recordings", comment: "Recordings list screen title.")
        static let searchPrompt = L10n.resource("recordings.search_prompt", defaultValue: "Search recordings or transcripts", comment: "Search prompt on recordings list.")
        static let chooseTranscriptionLanguage = L10n.resource("recordings.choose_transcription_language", defaultValue: "Choose Transcription Language", comment: "Dialog title for choosing a transcription language.")
        static let importRecording = L10n.resource("recordings.import_recording", defaultValue: "Import Recording", comment: "Import recording action or dialog message.")
        static let importAudioFile = L10n.resource("recordings.import_audio_file", defaultValue: "Import Audio File", comment: "Menu action for importing an audio file from the document picker.")
        static let importVideoFromPhotos = L10n.resource("recordings.import_video_from_photos", defaultValue: "Import Video from Photos", comment: "Menu action for importing the audio track of a video selected from Photos.")
        static let analysisFailed = L10n.resource("recordings.analysis_failed", defaultValue: "Analysis Failed", comment: "Alert title for analysis failure.")
        static let importFailed = L10n.resource("recordings.import_failed", defaultValue: "Import Failed", comment: "Alert title for import failure.")
        static let transcriptionFailed = L10n.resource("recordings.transcription_failed", defaultValue: "Transcription Failed", comment: "Alert title for transcription failure.")
        static let deleteRecording = L10n.resource("recordings.delete_recording", defaultValue: "Delete Recording", comment: "Delete recording action or alert title.")
        static let deleteConfirmationFormat = L10n.resource("recordings.delete_confirmation.format", defaultValue: "Delete %@?", comment: "Delete recording confirmation. Parameter: recording filename.")
        static let deleteFailed = L10n.resource("recordings.delete_failed", defaultValue: "Delete Failed", comment: "Alert title for delete failure.")
        static let noRecordings = L10n.resource("recordings.no_recordings", defaultValue: "No Recordings", comment: "Empty state title when no recordings exist.")
        static let noSearchResults = L10n.resource("recordings.no_search_results", defaultValue: "No Recordings Found", comment: "Empty state title when search has no results.")
        static let map = L10n.resource("recordings.map", defaultValue: "Map", comment: "Map action accessibility label.")
        static let copyTranscript = L10n.resource("recordings.copy_transcript", defaultValue: "Copy Transcript", comment: "Copy transcript action title.")
        static let generateTagsAndSummary = L10n.resource("recordings.generate_tags_and_summary", defaultValue: "Generate Tags and Summary", comment: "Action title to generate tags and summary.")
        static let analyzeAgain = L10n.resource("recordings.analyze_again", defaultValue: "Analyze Again", comment: "Action title to analyze a recording again.")
        static let retranscribe = L10n.resource("recordings.retranscribe", defaultValue: "Transcribe with Apple Speech", comment: "Action title to retranscribe a recording using Apple Speech.")
        static let retranscribeWithLocalWhisper = L10n.resource("recordings.retranscribe_local_whisper", defaultValue: "Transcribe with Local Whisper", comment: "Action title to retranscribe a recording with bundled local Whisper.")
        static let processWithGemini = L10n.resource("recordings.gemini.process", defaultValue: "Process with Gemini Cloud", comment: "Action and confirmation title for uploading audio to Gemini for transcript and intelligence generation.")
        static let uploadAndProcess = L10n.resource("recordings.gemini.upload_and_process", defaultValue: "Upload and Process", comment: "Confirmation button for Gemini Cloud processing.")
        static let geminiProcessingConfirmation = L10n.resource("recordings.gemini.process_confirmation", defaultValue: "This uploads the recording audio and current transcript draft to Gemini, replaces the transcript only after transcription succeeds, and generates summary and meeting intelligence. A restorable copy of the current transcript is kept.", comment: "Privacy and replacement confirmation before Gemini Cloud processing.")
        static let restoreBeforeGemini = L10n.resource("recordings.gemini.restore_before", defaultValue: "Restore Transcript Before Gemini", comment: "Action and alert title for restoring the transcript saved before Gemini processing.")
        static let restoreTranscript = L10n.resource("recordings.gemini.restore", defaultValue: "Restore Transcript", comment: "Confirmation button for restoring a transcript backup.")
        static let restoreBeforeGeminiConfirmation = L10n.resource("recordings.gemini.restore_confirmation", defaultValue: "Replace the current transcript with the copy saved before Gemini processing? Current Gemini summary and meeting analysis will be cleared.", comment: "Confirmation message for restoring the pre-Gemini transcript.")
        static let manualGemini = L10n.resource("recordings.gemini.manual.title", defaultValue: "Gemini App (Manual)", comment: "Menu title for the manual Gemini App transcription workflow that does not use the app's API integration.")
        static let manualGeminiShareAndCopyPrompt = L10n.resource("recordings.gemini.manual.share_and_copy_prompt", defaultValue: "Share Audio & Copy Prompt", comment: "Action that copies a transcription prompt and opens the system audio share sheet for Gemini App.")
        static let manualGeminiImportJSON = L10n.resource("recordings.gemini.manual.import_json", defaultValue: "Import Gemini JSON", comment: "Action and sheet title for importing a manually copied Gemini transcript JSON response.")
        static let manualGeminiImportInstructions = L10n.resource("recordings.gemini.manual.import_instructions", defaultValue: "Copy Gemini's complete JSON response, then paste it below. This workflow does not use this app's Gemini API key or token counter. Importing replaces the transcript and speaker labels after saving a restorable copy of the current transcript.", comment: "Instructions in the manual Gemini JSON import sheet.")
        static let manualGeminiJSONPlaceholder = L10n.resource("recordings.gemini.manual.json_placeholder", defaultValue: "Paste the complete JSON object here", comment: "Placeholder in the manual Gemini transcript JSON editor.")
        static let manualGeminiPasteClipboard = L10n.resource("recordings.gemini.manual.paste_clipboard", defaultValue: "Paste from Clipboard", comment: "Button that pastes Gemini transcript JSON from the clipboard.")
        static let manualGeminiImportTranscript = L10n.resource("recordings.gemini.manual.import_transcript", defaultValue: "Import Transcript", comment: "Confirmation button that imports a manually pasted Gemini transcript JSON response.")
        static let manualGeminiClipboardEmpty = L10n.resource("recordings.gemini.manual.clipboard_empty", defaultValue: "The clipboard does not contain text.", comment: "Error shown when manual Gemini JSON paste finds no text in the clipboard.")
        static let analyze = L10n.resource("recordings.analyze", defaultValue: "Analyze", comment: "Analyze action title.")
        static let noLocatedRecordings = L10n.resource("recordings.no_located_recordings", defaultValue: "No Recordings with Location", comment: "Empty state title for map with no located recordings.")
        static let mapTitle = L10n.resource("recordings.map_title", defaultValue: "Recording Map", comment: "Recording map screen title.")
        static let analyzing = L10n.resource("recordings.analyzing", defaultValue: "Analyzing", comment: "Status shown while analyzing.")
        static let audioParameters = L10n.resource("recordings.audio_parameters", defaultValue: "Audio Parameters", comment: "Audio parameters screen or section title.")
        static let renameFailed = L10n.resource("recordings.rename_failed", defaultValue: "Rename Failed", comment: "Alert title for rename failure.")
        static let rename = L10n.resource("recordings.rename", defaultValue: "Rename", comment: "Rename action title.")
        static let editFailed = L10n.resource("recordings.edit_failed", defaultValue: "Edit Failed", comment: "Alert title when recording details could not be edited.")
        static let editDetails = L10n.resource("recordings.edit_details", defaultValue: "Edit Details", comment: "Action title for editing recording metadata.")
        static let shareAudio = L10n.resource("recordings.share_audio", defaultValue: "Share Audio", comment: "Share audio action title.")
        static let shareTranscript = L10n.resource("recordings.share_transcript", defaultValue: "Share Transcript Text", comment: "Share transcript text action title.")
        static let exportTranscript = L10n.resource("recordings.export_transcript", defaultValue: "Export Transcript", comment: "Menu title for exporting a transcript file.")
        static let exportTXT = L10n.resource("recordings.export_transcript.txt", defaultValue: "TXT", comment: "Export transcript as TXT action title.")
        static let exportMarkdown = L10n.resource("recordings.export_transcript.markdown", defaultValue: "Markdown", comment: "Export transcript as Markdown action title.")
        static let exportSRT = L10n.resource("recordings.export_transcript.srt", defaultValue: "SRT Subtitles", comment: "Export transcript as SRT subtitles action title.")
        static let exportVTT = L10n.resource("recordings.export_transcript.vtt", defaultValue: "VTT Captions", comment: "Export transcript as WebVTT captions action title.")
        static let exportJSON = L10n.resource("recordings.export_transcript.json", defaultValue: "JSON", comment: "Export transcript as JSON action title.")
        static let exportFailed = L10n.resource("recordings.export_failed", defaultValue: "Export Failed", comment: "Alert title when transcript export fails.")
        static let exportEmptyTranscript = L10n.resource("recordings.export_empty_transcript", defaultValue: "No transcript text is available to export.", comment: "Error shown when exporting an empty transcript.")
        static let share = L10n.resource("recordings.share", defaultValue: "Share", comment: "Share menu title.")
        static let copied = L10n.resource("recordings.copied", defaultValue: "Copied", comment: "Status shown after copying.")
        static let intelligenceSummary = L10n.resource("recordings.intelligence_summary", defaultValue: "Summary", comment: "Intelligent summary section title.")
        static let meetingAnalysis = L10n.resource("recordings.meeting_analysis", defaultValue: "Meeting Analysis", comment: "Meeting intelligence section title.")
        static let analyzeMeeting = L10n.resource("recordings.meeting_analysis.analyze", defaultValue: "Analyze Meeting", comment: "Action title to generate meeting intelligence.")
        static let analyzeMeetingAgain = L10n.resource("recordings.meeting_analysis.analyze_again", defaultValue: "Analyze Again", comment: "Action title to regenerate meeting intelligence.")
        static let analyzingMeeting = L10n.resource("recordings.meeting_analysis.analyzing", defaultValue: "Analyzing Meeting", comment: "Status shown while meeting intelligence is generated.")
        static let noMeetingAnalysis = L10n.resource("recordings.meeting_analysis.empty", defaultValue: "No Meeting Analysis", comment: "Empty state title when no meeting intelligence exists.")
        static let audioEvents = L10n.resource("recordings.audio_events", defaultValue: "Audio Events", comment: "Sound analysis section title.")
        static let analyzeAudioEvents = L10n.resource("recordings.audio_events.analyze", defaultValue: "Analyze Audio", comment: "Action title to run sound event analysis.")
        static let analyzeAudioEventsAgain = L10n.resource("recordings.audio_events.analyze_again", defaultValue: "Analyze Again", comment: "Action title to rerun sound event analysis.")
        static let analyzingAudioEvents = L10n.resource("recordings.audio_events.analyzing", defaultValue: "Analyzing Audio", comment: "Status shown while sound events are being analyzed.")
        static let noAudioEvents = L10n.resource("recordings.audio_events.empty", defaultValue: "No Audio Events", comment: "Empty state title when no sound events have been saved.")
        static let noAudioEventsDetected = L10n.resource("recordings.audio_events.none_detected", defaultValue: "No clear audio events were detected in this recording.", comment: "Error shown when sound analysis completes without usable events.")
        static let audioEventAnalysisCancelled = L10n.resource("recordings.audio_events.cancelled", defaultValue: "Audio event analysis was cancelled.", comment: "Error shown when sound analysis is cancelled.")
        static let audioEventConfidenceFormat = L10n.resource("recordings.audio_events.confidence.format", defaultValue: "%.0f%% confidence", comment: "Audio event confidence text. Parameter: confidence percentage.")
        static let audioEventUnknown = L10n.resource("recordings.audio_events.label.unknown", defaultValue: "Other Sound", comment: "Fallback label for a sound classification introduced after the app's localization table was built.")
        static let audioEventLabelAlarm = L10n.resource("recordings.audio_events.label.alarm", defaultValue: "Alarm", comment: "Localized sound event label.")
        static let audioEventLabelApplause = L10n.resource("recordings.audio_events.label.applause", defaultValue: "Applause", comment: "Localized sound event label.")
        static let audioEventLabelBabyCrying = L10n.resource("recordings.audio_events.label.baby_crying", defaultValue: "Baby Crying", comment: "Localized sound event label.")
        static let audioEventLabelBell = L10n.resource("recordings.audio_events.label.bell", defaultValue: "Bell", comment: "Localized sound event label.")
        static let audioEventLabelCat = L10n.resource("recordings.audio_events.label.cat", defaultValue: "Cat", comment: "Localized sound event label.")
        static let audioEventLabelCheering = L10n.resource("recordings.audio_events.label.cheering", defaultValue: "Cheering", comment: "Localized sound event label.")
        static let audioEventLabelClapping = L10n.resource("recordings.audio_events.label.clapping", defaultValue: "Clapping", comment: "Localized sound event label.")
        static let audioEventLabelCough = L10n.resource("recordings.audio_events.label.cough", defaultValue: "Cough", comment: "Localized sound event label.")
        static let audioEventLabelDog = L10n.resource("recordings.audio_events.label.dog", defaultValue: "Dog", comment: "Localized sound event label.")
        static let audioEventLabelDoorbell = L10n.resource("recordings.audio_events.label.doorbell", defaultValue: "Doorbell", comment: "Localized sound event label.")
        static let audioEventLabelEngine = L10n.resource("recordings.audio_events.label.engine", defaultValue: "Engine", comment: "Localized sound event label.")
        static let audioEventLabelFootsteps = L10n.resource("recordings.audio_events.label.footsteps", defaultValue: "Footsteps", comment: "Localized sound event label.")
        static let audioEventLabelKnock = L10n.resource("recordings.audio_events.label.knock", defaultValue: "Knock", comment: "Localized sound event label.")
        static let audioEventLabelLaughter = L10n.resource("recordings.audio_events.label.laughter", defaultValue: "Laughter", comment: "Localized sound event label.")
        static let audioEventLabelMusic = L10n.resource("recordings.audio_events.label.music", defaultValue: "Music", comment: "Localized sound event label.")
        static let audioEventLabelPhone = L10n.resource("recordings.audio_events.label.phone", defaultValue: "Phone", comment: "Localized sound event label.")
        static let audioEventLabelRain = L10n.resource("recordings.audio_events.label.rain", defaultValue: "Rain", comment: "Localized sound event label.")
        static let audioEventLabelSinging = L10n.resource("recordings.audio_events.label.singing", defaultValue: "Singing", comment: "Localized sound event label.")
        static let audioEventLabelSiren = L10n.resource("recordings.audio_events.label.siren", defaultValue: "Siren", comment: "Localized sound event label.")
        static let audioEventLabelSneeze = L10n.resource("recordings.audio_events.label.sneeze", defaultValue: "Sneeze", comment: "Localized sound event label.")
        static let audioEventLabelThunder = L10n.resource("recordings.audio_events.label.thunder", defaultValue: "Thunder", comment: "Localized sound event label.")
        static let audioEventLabelTyping = L10n.resource("recordings.audio_events.label.typing", defaultValue: "Typing", comment: "Localized sound event label.")
        static let audioEventLabelVehicle = L10n.resource("recordings.audio_events.label.vehicle", defaultValue: "Vehicle", comment: "Localized sound event label.")
        static let audioEventLabelWater = L10n.resource("recordings.audio_events.label.water", defaultValue: "Water", comment: "Localized sound event label.")
        static let audioEventLabelWind = L10n.resource("recordings.audio_events.label.wind", defaultValue: "Wind", comment: "Localized sound event label.")
        static let meetingSummary = L10n.resource("recordings.meeting_analysis.summary", defaultValue: "Meeting Summary", comment: "Meeting intelligence summary section title.")
        static let actionItems = L10n.resource("recordings.meeting_analysis.action_items", defaultValue: "Action Items", comment: "Meeting intelligence action items section title.")
        static let addAllActionItemsToReminders = L10n.resource("recordings.meeting_analysis.add_all_to_reminders", defaultValue: "Add All to Reminders", comment: "Action title to add every extracted action item to Reminders.")
        static let addActionItemToReminders = L10n.resource("recordings.meeting_analysis.add_to_reminders", defaultValue: "Add to Reminders", comment: "Action title to add one extracted action item to Reminders.")
        static let addingToReminders = L10n.resource("recordings.meeting_analysis.adding_to_reminders", defaultValue: "Adding to Reminders", comment: "Status shown while action items are being added to Reminders.")
        static let addedRemindersFormat = L10n.resource("recordings.meeting_analysis.added_reminders.format", defaultValue: "Added %d reminder(s)", comment: "Status after adding extracted action items to Reminders. Parameter: reminder count.")
        static let decisions = L10n.resource("recordings.meeting_analysis.decisions", defaultValue: "Decisions", comment: "Meeting intelligence decisions section title.")
        static let openQuestions = L10n.resource("recordings.meeting_analysis.open_questions", defaultValue: "Open Questions", comment: "Meeting intelligence open questions section title.")
        static let meetingNotes = L10n.resource("recordings.meeting_analysis.notes", defaultValue: "Notes", comment: "Meeting intelligence notes section title.")
        static let reminderAccessDenied = L10n.resource("recordings.meeting_analysis.reminder_access_denied", defaultValue: "Allow Reminders access in Settings before adding action items.", comment: "Error shown when Reminders access is denied.")
        static let reminderNoWritableList = L10n.resource("recordings.meeting_analysis.reminder_no_writable_list", defaultValue: "No writable Reminders list is available.", comment: "Error shown when no writable Reminders list exists.")
        static let reminderNoActionItems = L10n.resource("recordings.meeting_analysis.reminder_no_action_items", defaultValue: "There are no action items to add.", comment: "Error shown when no action items can be added to Reminders.")
        static let reminderNoteSourceFormat = L10n.resource("recordings.meeting_analysis.reminder_note_source.format", defaultValue: "From LiveTranscriber recording: %@", comment: "Reminder note source line. Parameter: recording title.")
        static let reminderNoteOwnerFormat = L10n.resource("recordings.meeting_analysis.reminder_note_owner.format", defaultValue: "Owner: %@", comment: "Reminder note owner line. Parameter: owner.")
        static let reminderNoteDueDateFormat = L10n.resource("recordings.meeting_analysis.reminder_note_due_date.format", defaultValue: "Detected due date: %@", comment: "Reminder note due date line. Parameter: due date text.")
        static let reviewReminders = L10n.resource("recordings.meeting_analysis.review_reminders", defaultValue: "Review Reminders", comment: "Sheet title for reviewing reminders before adding them.")
        static let addToReminders = L10n.resource("recordings.meeting_analysis.add_to_reminders_confirm", defaultValue: "Add", comment: "Confirmation button title to add reviewed reminders.")
        static let reminderTitle = L10n.resource("recordings.meeting_analysis.reminder_title", defaultValue: "Reminder Title", comment: "Text field placeholder for reminder title.")
        static let reminderDueDate = L10n.resource("recordings.meeting_analysis.reminder_due_date", defaultValue: "Due Date", comment: "Due date field title in reminder review.")
        static let reminderReviewFooter = L10n.resource("recordings.meeting_analysis.reminder_review_footer", defaultValue: "Review and edit these reminders before they are added to Reminders.", comment: "Footer text in reminder review sheet.")
        static let detailPages = L10n.resource("recordings.detail_pages", defaultValue: "View", comment: "Accessibility label for the detail page switcher.")
        static let aiAnalysis = L10n.resource("recordings.ai_analysis", defaultValue: "AI Analysis", comment: "Detail page title for the AI analysis page.")
        static let chatSection = L10n.resource("recordings.chat_section", defaultValue: "Ask AI", comment: "Chat card title on the AI analysis page.")
        static let chatPlaceholder = L10n.resource("recordings.chat_placeholder", defaultValue: "Ask about this recording…", comment: "Chat input placeholder on the AI analysis page.")
        static let chatEmpty = L10n.resource("recordings.chat_empty", defaultValue: "Ask anything about this recording. Answers are based on the transcript.", comment: "Empty state shown before the first chat message.")
        static let chatThinking = L10n.resource("recordings.chat_thinking", defaultValue: "Thinking…", comment: "Status shown while the AI answer is being generated.")
        static let chatFailed = L10n.resource("recordings.chat_failed", defaultValue: "Couldn't get an answer.", comment: "Error shown when the AI answer fails.")
        static let chatUnavailable = L10n.resource("recordings.chat_unavailable", defaultValue: "AI chat is unavailable. Enable Apple Intelligence or download the local model in Settings.", comment: "Message shown when no AI provider is available for chat.")
        static let chatClear = L10n.resource("recordings.chat_clear", defaultValue: "Clear Conversation", comment: "Action that clears the recording chat conversation.")
        static let chatSend = L10n.resource("recordings.chat_send", defaultValue: "Send", comment: "Accessibility label for the chat send button.")
        static let chatSearchingTranscriptExcerpts = L10n.resource("recordings.chat.status.searching_excerpts", defaultValue: "Searching transcript excerpts", comment: "AI chat status while finding relevant transcript excerpts.")
        static let chatPreparingTranscriptContext = L10n.resource("recordings.chat.status.preparing_context", defaultValue: "Preparing transcript context", comment: "AI chat status while preparing transcript context.")
        static let chatSwitchingToLocalQwen = L10n.resource("recordings.chat.status.switching_local_qwen", defaultValue: "Switching to local Qwen", comment: "AI chat status while switching from Apple Intelligence to local Qwen.")
        static let chatGeneratingAnswer = L10n.resource("recordings.chat.status.generating_answer", defaultValue: "Generating answer", comment: "AI chat status while generating an answer.")
        static let chatGeneratingAnswerWithContextFormat = L10n.resource("recordings.chat.status.generating_answer_with_context.format", defaultValue: "%@. Generating answer", comment: "AI chat status combining transcript context preparation with answer generation. Parameter: context status.")
        static let chatRetryingSmallerExcerpt = L10n.resource("recordings.chat.status.retrying_smaller_excerpt", defaultValue: "Context was too long. Retrying with a smaller excerpt", comment: "AI chat status after the selected context exceeded the local model limit.")
        static let chatUsingFullTranscript = L10n.resource("recordings.chat.status.using_full_transcript", defaultValue: "Using the full transcript", comment: "AI chat status when the complete transcript fits in context.")
        static let chatCompressingTranscriptContext = L10n.resource("recordings.chat.status.compressing_context", defaultValue: "Compressing transcript context", comment: "AI chat status when a long transcript is reduced to a context digest.")
        static let chatRelevantExcerptCountFormat = L10n.resource("recordings.chat.status.relevant_excerpt_count.format", defaultValue: "Relevant transcript excerpts: %d", comment: "AI chat status showing how many relevant transcript excerpts were selected. Parameter: excerpt count.")
        static let noSummary = L10n.resource("recordings.no_summary", defaultValue: "No Summary", comment: "Empty state title when no summary exists.")
        static let sampleRate = L10n.resource("recordings.audio.sample_rate", defaultValue: "Sample Rate", comment: "Audio parameter row title.")
        static let bitRate = L10n.resource("recordings.audio.bit_rate", defaultValue: "Bit Rate", comment: "Audio parameter row title.")
        static let averageBitRate = L10n.resource("recordings.audio.average_bit_rate", defaultValue: "Average Bit Rate", comment: "Audio parameter row title.")
        static let channels = L10n.resource("recordings.audio.channels", defaultValue: "Channels", comment: "Audio parameter row title.")
        static let encoding = L10n.resource("recordings.audio.encoding", defaultValue: "Encoding", comment: "Audio parameter row title.")
        static let fileFormat = L10n.resource("recordings.audio.file_format", defaultValue: "File Format", comment: "Audio parameter row title.")
        static let processingFormat = L10n.resource("recordings.audio.processing_format", defaultValue: "Processing Format", comment: "Audio parameter row title.")
        static let pcmBitDepth = L10n.resource("recordings.audio.pcm_bit_depth", defaultValue: "PCM Bit Depth", comment: "Audio parameter row title.")
        static let audioDuration = L10n.resource("recordings.audio.duration", defaultValue: "Audio Duration", comment: "Audio parameter row title.")
        static let audioFrames = L10n.resource("recordings.audio.frames", defaultValue: "Audio Frames", comment: "Audio parameter row title.")
        static let fileName = L10n.resource("recordings.audio.file_name", defaultValue: "File Name", comment: "Audio parameter row title.")
        static let fileCreationDate = L10n.resource("recordings.audio.file_creation_date", defaultValue: "File Creation Time", comment: "Audio parameter row title for the file system creation date and time.")
        static let fileSize = L10n.resource("recordings.audio.file_size", defaultValue: "File Size", comment: "Audio parameter row title.")
        static let storage = L10n.resource("recordings.audio.storage", defaultValue: "Storage", comment: "Audio parameter group title.")
        static let technicalDetails = L10n.resource("recordings.audio.technical_details", defaultValue: "Technical Details", comment: "Audio parameter group title.")
        static let iCloudSync = L10n.resource("recordings.audio.icloud_sync", defaultValue: "iCloud Sync", comment: "Audio parameter row title.")
        static let readingAudioParameters = L10n.resource("recordings.audio.reading_parameters", defaultValue: "Reading audio parameters", comment: "Status shown while reading audio parameters.")
        static let pause = L10n.resource("recordings.playback.pause", defaultValue: "Pause", comment: "Playback pause button accessibility label.")
        static let play = L10n.resource("recordings.playback.play", defaultValue: "Play", comment: "Playback play button accessibility label.")
        static let transcript = L10n.resource("recordings.transcript", defaultValue: "Transcript", comment: "Transcript section title.")
        static let editTranscriptLine = L10n.resource("recordings.transcript.edit_line", defaultValue: "Edit Transcript Line", comment: "Action and sheet title for editing one transcript line.")
        static let transcriptLineText = L10n.resource("recordings.transcript.line_text", defaultValue: "Transcript Text", comment: "Field title for one editable transcript line.")
        static let lockTranscript = L10n.resource("recordings.transcript.lock", defaultValue: "Lock Transcript", comment: "Menu action to lock transcript text against automatic updates.")
        static let unlockTranscript = L10n.resource("recordings.transcript.unlock", defaultValue: "Unlock Transcript", comment: "Menu action to unlock transcript text.")
        static let transcriptLocked = L10n.resource("recordings.transcript.locked", defaultValue: "Transcript Locked", comment: "Status shown when transcript text is locked.")
        static let transcriptUnlocked = L10n.resource("recordings.transcript.unlocked", defaultValue: "Transcript Unlocked", comment: "Status shown when transcript text is not locked.")
        static let transcriptLockedDetail = L10n.resource("recordings.transcript.locked_detail", defaultValue: "Automatic transcription updates cannot overwrite this transcript.", comment: "Short explanation for locked transcript status.")
        static let transcriptLockedError = L10n.resource("recordings.transcript.locked_error", defaultValue: "Transcript is locked. Unlock it before running transcription again.", comment: "Error shown when automatic transcription tries to overwrite a locked transcript.")
        static let transcriptLineMissing = L10n.resource("recordings.transcript.line_missing", defaultValue: "Transcript line could not be found.", comment: "Error shown when a transcript line edit cannot be applied.")
        static let transcriptSpeakerFormat = L10n.resource("recordings.transcript.speaker.format", defaultValue: "Speaker %d", comment: "Display name for a numbered transcript speaker. Parameter: one-based speaker number.")
        static let transcriptSpeakersDetectedFormat = L10n.resource("recordings.transcript.speakers_detected.format", defaultValue: "%d speakers", comment: "Transcript speaker legend title. Parameter: number of distinct speakers; shown only when there are multiple speakers.")
        static let noText = L10n.resource("recordings.no_text", defaultValue: "No Text", comment: "Empty state title when no transcript text exists.")
        static let original = L10n.resource("recordings.translation.original", defaultValue: "Original", comment: "Translation menu option for original transcript.")
        static let translate = L10n.resource("recordings.translation.translate", defaultValue: "Translate", comment: "Translate menu button title.")
        static let translatingToFormat = L10n.resource("recordings.translation.translating_to.format", defaultValue: "Translating to %@", comment: "Translation status. Parameter: target language name.")
        static let translating = L10n.resource("recordings.translation.translating", defaultValue: "Translating", comment: "Status shown while translating a transcript line.")
        static let waitForTranslationBeforeSummary = L10n.resource("recordings.translation.wait_before_summary", defaultValue: "Wait for translation to finish before generating the summary", comment: "Error shown when analysis is requested during translation.")
        static let noTranslatedTextForSummary = L10n.resource("recordings.translation.no_translated_text_for_summary", defaultValue: "No translated text is available for the summary", comment: "Error shown when translated analysis has no text.")
        static let audioInfoReadFailedFormat = L10n.resource("recordings.audio.read_failed.format", defaultValue: "Could not read audio parameters: %@", comment: "Audio info read failure. Parameter: error description.")
        static let editRecordingTitle = L10n.resource("recordings.edit.title", defaultValue: "Edit Recording", comment: "Edit recording screen title.")
        static let recordingName = L10n.resource("recordings.edit.recording_name", defaultValue: "Recording Name", comment: "Recording name field title.")
        static let projectName = L10n.resource("recordings.edit.project_name", defaultValue: "Folder / Project", comment: "Recording folder or project field title.")
        static let projectNamePlaceholder = L10n.resource("recordings.edit.project_name.placeholder", defaultValue: "Course, meeting, client, or folder", comment: "Placeholder for the folder or project field.")
        static let categoryName = L10n.resource("recordings.edit.category_name", defaultValue: "Category", comment: "Recording category field title.")
        static let categoryNamePlaceholder = L10n.resource("recordings.edit.category_name.placeholder", defaultValue: "Lecture, interview, standup, idea", comment: "Placeholder for the category field.")
        static let keyPoints = L10n.resource("recordings.edit.key_points", defaultValue: "Key Points", comment: "Recording key points field title.")
        static let keyPointsPlaceholder = L10n.resource("recordings.edit.key_points.placeholder", defaultValue: "Important moments, conclusions, or follow-ups", comment: "Placeholder for recording key points.")
        static let projectFilter = L10n.resource("recordings.project_filter", defaultValue: "Folder Filter", comment: "Accessibility label for the recordings folder filter menu.")
        static let allProjects = L10n.resource("recordings.project_filter.all", defaultValue: "All Folders", comment: "Menu item to show recordings from all folders.")
        static let categoryFilter = L10n.resource("recordings.category_filter", defaultValue: "Category Filter", comment: "Accessibility label for the recordings category filter menu.")
        static let allCategories = L10n.resource("recordings.category_filter.all", defaultValue: "All Categories", comment: "Menu item to show recordings from all categories.")
        static let filters = L10n.resource("recordings.filters", defaultValue: "Filters", comment: "Recordings filter menu title.")
        static let clearFilters = L10n.resource("recordings.filters.clear", defaultValue: "Clear Filters", comment: "Action title to clear recordings filters.")
        static let allRecordings = L10n.resource("recordings.filters.all_recordings", defaultValue: "All Recordings", comment: "Recordings filter option to show every recording.")
        static let uncategorized = L10n.resource("recordings.category.uncategorized", defaultValue: "Uncategorized", comment: "Folder title for recordings without a category.")
        static let categories = L10n.resource("recordings.categories", defaultValue: "Categories", comment: "Recordings category folder root title.")
        static let newCategory = L10n.resource("recordings.category.new", defaultValue: "New Category", comment: "Action title to create a recording category.")
        static let newCategoryDetail = L10n.resource("recordings.category.new_detail", defaultValue: "Create a folder for a course, meeting, client, or topic", comment: "Subtitle for the new category folder row.")
        static let renameCategory = L10n.resource("recordings.category.rename", defaultValue: "Rename Category", comment: "Action and sheet title to rename a recording category.")
        static let deleteCategory = L10n.resource("recordings.category.delete", defaultValue: "Delete Category", comment: "Action and alert title to delete a recording category.")
        static let deleteCategoryConfirmationFormat = L10n.resource("recordings.category.delete_confirmation.format", defaultValue: "Delete %@ and move %d recording(s) to Uncategorized?", comment: "Delete category confirmation. Parameters: category name, recording count.")
        static let categoryExists = L10n.resource("recordings.category.exists", defaultValue: "A category with this name already exists.", comment: "Error shown when creating or renaming a category to a duplicate name.")
        static let organize = L10n.resource("recordings.category.organize", defaultValue: "Organize", comment: "Action title to organize recordings into categories.")
        static let categoryCountFormat = L10n.resource("recordings.category.count.format", defaultValue: "%d recording(s)", comment: "Category folder recording count. Parameter: recording count.")
        static let moveToCategory = L10n.resource("recordings.category.move_to", defaultValue: "Move to Category", comment: "Menu title for moving a recording into a category.")
        static let addRecordingsToCategory = L10n.resource("recordings.category.add_recordings", defaultValue: "Add Recordings", comment: "Action title to add recordings to the current category.")
        static let addRecordingsToCategoryFormat = L10n.resource("recordings.category.add_recordings.format", defaultValue: "Add to %@", comment: "Sheet title for adding recordings to a category. Parameter: category name.")
        static let addToCategory = L10n.resource("recordings.category.add_to", defaultValue: "Add to Category", comment: "Button accessibility label to add one recording to the current category.")
        static let noRecordingsToAdd = L10n.resource("recordings.category.no_recordings_to_add", defaultValue: "No Recordings to Add", comment: "Empty state when every recording is already in the current category.")
        static let summary = L10n.resource("recordings.edit.summary", defaultValue: "Summary", comment: "Summary field title.")
        static let editSummary = L10n.resource("recordings.edit.summary_action", defaultValue: "Edit Summary", comment: "Action title for editing a recording summary.")
        static let summaryPlaceholder = L10n.resource("recordings.edit.summary_placeholder", defaultValue: "Add a summary", comment: "Placeholder for the editable recording summary field.")
        static let tags = L10n.resource("recordings.edit.tags", defaultValue: "Tags", comment: "Tags field title.")
        static let notAdded = L10n.resource("recordings.edit.not_added", defaultValue: "Not Added", comment: "Status shown when no optional metadata has been added.")
        static let addLocation = L10n.resource("recordings.edit.add_location", defaultValue: "Add Location", comment: "Toggle title to add a recording location.")
        static let addTag = L10n.resource("recordings.edit.add_tag", defaultValue: "Add Tag", comment: "Tag entry placeholder.")
        static let noTags = L10n.resource("recordings.edit.no_tags", defaultValue: "No Tags", comment: "Empty state text when no tags exist.")
        static let currentLocation = L10n.resource("recordings.location.current", defaultValue: "Current Location", comment: "Fallback marker title for current location.")
        static let updateCurrentLocation = L10n.resource("recordings.location.update_current", defaultValue: "Update Current Location", comment: "Button title to update current location.")
        static let locationDenied = L10n.resource("recordings.location.denied", defaultValue: "Location Permission Denied", comment: "Status shown when location permission is denied.")
        static let locating = L10n.resource("recordings.location.locating", defaultValue: "Getting Location", comment: "Status shown while getting current location.")
        static let locationUnavailable = L10n.resource("recordings.location.unavailable", defaultValue: "Could Not Get Location", comment: "Location unavailable error.")
        static let mono = L10n.resource("recordings.audio.mono", defaultValue: "Mono", comment: "Audio channel layout text.")
        static let stereo = L10n.resource("recordings.audio.stereo", defaultValue: "Stereo", comment: "Audio channel layout text.")
        static let channelCountFormat = L10n.resource("recordings.audio.channel_count.format", defaultValue: "%d channels", comment: "Audio channel count. Parameter: channel count.")
        static let bitDepthFormat = L10n.resource("recordings.audio.bit_depth.format", defaultValue: "%d-bit", comment: "Audio bit depth. Parameter: bit depth.")
        static let compressedOrOtherFormat = L10n.resource("recordings.audio.compressed_or_other", defaultValue: "Compressed or Other Format", comment: "Audio format fallback name.")
        static let recordingFileMissing = L10n.resource("recordings.playback.file_missing", defaultValue: "Recording file does not exist", comment: "Playback error when audio file is missing.")
        static let playbackFailedFormat = L10n.resource("recordings.playback.failed.format", defaultValue: "Cannot play recording: %@", comment: "Playback failure. Parameter: error description.")
        static let playbackStartFailedFormat = L10n.resource("recordings.playback.start_failed.format", defaultValue: "Playback failed to start: %@", comment: "Playback start failure. Parameter: error description.")
        static let recordingFallback = L10n.resource("recordings.recording_fallback", defaultValue: "Recording", comment: "Fallback recording title.")
        static let recordingPlayback = L10n.resource("recordings.playback.title", defaultValue: "Recording Playback", comment: "Now Playing fallback subtitle.")
    }

    enum Source {
        static let title = L10n.resource(
            "source.title",
            defaultValue: "Source",
            comment: "Settings section title for source availability and licensing."
        )
        static let sourceAvailable = L10n.resource(
            "source.source_available",
            defaultValue: "Source Available",
            comment: "Short settings value describing the source license posture."
        )
        static let subtitle = L10n.resource(
            "source.subtitle",
            defaultValue: "Repository link and license information",
            comment: "Settings row subtitle for the source information page."
        )
        static let description = L10n.resource(
            "source.description",
            defaultValue: "LiveTranscriber source code is publicly available for learning, forks, and continued development.",
            comment: "Source information page description."
        )
        static let licenseNote = L10n.resource(
            "source.license_note",
            defaultValue: "The project uses a source-available license, not an OSI-approved open-source license; commercial forks or derivative products need to keep visible in-app attribution.",
            comment: "Source information page licensing note."
        )
        static let requiredAttribution = L10n.resource(
            "source.required_attribution",
            defaultValue: "Required attribution: Based on LiveTranscriber by William Li",
            comment: "Required attribution text for commercial forks."
        )
        static let repositoryTitle = L10n.resource(
            "source.repository_title",
            defaultValue: "GitHub Repository",
            comment: "External link title for the project repository."
        )
        static let designNotesTitle = L10n.resource(
            "source.design_notes_title",
            defaultValue: "Design Notes",
            comment: "External link title for the LiveTranscriber design notes article."
        )
    }

    enum RecordingStatus {
        static let ready = L10n.resource(
            "recording.status.ready",
            defaultValue: "Ready",
            comment: "Recording status when the recorder is idle and ready."
        )
        static let requestingPermission = L10n.resource(
            "recording.status.requesting_permission",
            defaultValue: "Requesting Permission",
            comment: "Recording status while requesting microphone and speech permissions."
        )
        static let checkingPermissions = L10n.resource(
            "recording.status.checking_permissions",
            defaultValue: "Checking permissions",
            comment: "Recording status while checking existing microphone and speech permissions."
        )
        static let configuringAudioInput = L10n.resource(
            "recording.status.configuring_audio_input",
            defaultValue: "Configuring microphone",
            comment: "Recording status while configuring the audio session and microphone input."
        )
        static let startingRecorder = L10n.resource(
            "recording.status.starting_recorder",
            defaultValue: "Starting recorder",
            comment: "Recording status while starting audio capture."
        )
        static let recording = L10n.resource(
            "recording.status.recording",
            defaultValue: "Recording",
            comment: "Recording status while recording is active."
        )
        static let paused = L10n.resource(
            "recording.status.paused",
            defaultValue: "Paused",
            comment: "Recording status when paused."
        )
        static let complete = L10n.resource(
            "recording.status.complete",
            defaultValue: "Transcription Complete",
            comment: "Recording status after transcription completes."
        )
        static let stopped = L10n.resource(
            "recording.status.stopped",
            defaultValue: "Stopped",
            comment: "Recording status after stopping without transcript completion."
        )
        static let preparingLanguageModel = L10n.resource(
            "recording.status.preparing_language_model",
            defaultValue: "Preparing language model",
            comment: "Recording status while preparing speech models."
        )
        static let downloadingLanguageModel = L10n.resource(
            "recording.status.downloading_language_model",
            defaultValue: "Downloading language model",
            comment: "Recording status while downloading a speech language model."
        )
        static let waitingForSpeech = L10n.resource(
            "recording.status.waiting_for_speech",
            defaultValue: "Waiting for speech",
            comment: "Placeholder shown while waiting for speech."
        )
    }

    enum Intelligence {
        static let appleModelTitle = L10n.resource(
            "intelligence.apple_model.title",
            defaultValue: "Apple Intelligence",
            comment: "Settings section title for Apple Intelligence summary availability."
        )
        static let available = L10n.resource(
            "intelligence.available",
            defaultValue: "Available",
            comment: "Apple Intelligence availability status."
        )
        static let unsupportedDevice = L10n.resource(
            "intelligence.unsupported_device",
            defaultValue: "Unsupported",
            comment: "Apple Intelligence availability status when device is unsupported."
        )
        static let disabled = L10n.resource(
            "intelligence.disabled",
            defaultValue: "Disabled",
            comment: "Apple Intelligence availability status when disabled."
        )
        static let modelNotReady = L10n.resource(
            "intelligence.model_not_ready",
            defaultValue: "Model Not Ready",
            comment: "Apple Intelligence availability status when model is not ready."
        )
        static let unavailable = L10n.resource(
            "intelligence.unavailable",
            defaultValue: "Unavailable",
            comment: "Apple Intelligence availability status when unavailable."
        )
        static let detailAvailable = L10n.resource(
            "intelligence.detail.available",
            defaultValue: "The Apple Intelligence on-device advanced model is available for summaries",
            comment: "Apple Intelligence detail when the model is available."
        )
        static let detailUnsupportedDevice = L10n.resource(
            "intelligence.detail.unsupported_device",
            defaultValue: "This device does not support the Apple Intelligence on-device advanced model",
            comment: "Apple Intelligence detail when the current device is not eligible."
        )
        static let detailDisabled = L10n.resource(
            "intelligence.detail.disabled",
            defaultValue: "Apple Intelligence is not enabled",
            comment: "Apple Intelligence detail when Apple Intelligence is disabled."
        )
        static let detailModelNotReady = L10n.resource(
            "intelligence.detail.model_not_ready",
            defaultValue: "The Apple Intelligence on-device model is not ready yet",
            comment: "Apple Intelligence detail when the model is not ready."
        )
        static let detailUnavailable = L10n.resource(
            "intelligence.detail.unavailable",
            defaultValue: "The Apple Intelligence on-device model is unavailable",
            comment: "Apple Intelligence detail when the model is unavailable for an unknown reason."
        )
        static let emptyTranscript = L10n.resource(
            "intelligence.error.empty_transcript",
            defaultValue: "No transcript text is available for analysis",
            comment: "Apple Intelligence analysis error."
        )
        static let emptySummary = L10n.resource(
            "intelligence.error.empty_summary",
            defaultValue: "No valid summary was generated",
            comment: "Apple Intelligence analysis error."
        )
        static let emptyTitle = L10n.resource(
            "intelligence.error.empty_title",
            defaultValue: "No valid title was generated",
            comment: "Apple Intelligence title generation error."
        )
        static let parseSummaryLabel = L10n.resource(
            "intelligence.parse.summary_label",
            defaultValue: "summary",
            comment: "Localized label used when recovering plain model output."
        )
        static let parseSummarySynonymLabel = L10n.resource(
            "intelligence.parse.summary_synonym_label",
            defaultValue: "summarization",
            comment: "Localized label used when recovering plain model output."
        )
        static let parseTitleLabel = L10n.resource(
            "intelligence.parse.title_label",
            defaultValue: "title",
            comment: "Localized label used when recovering plain model output."
        )
        static let parseTagsLabel = L10n.resource(
            "intelligence.parse.tags_label",
            defaultValue: "tags",
            comment: "Localized label used when recovering plain model output."
        )
        static let parseTopicTagsLabel = L10n.resource(
            "intelligence.parse.topic_tags_label",
            defaultValue: "topic tags",
            comment: "Localized label used when recovering plain model output."
        )
    }

    enum GeminiCloud {
        static let providerTitle = L10n.resource("gemini_cloud.provider.title", defaultValue: "Gemini Cloud", comment: "AI engine option for Gemini Cloud.")
        static let providerDetail = L10n.resource("gemini_cloud.provider.detail", defaultValue: "Use Gemini for cloud summaries, meeting analysis, and recording questions. Audio is uploaded only through the explicit Gemini recording action.", comment: "Gemini Cloud AI engine detail.")
        static let available = L10n.resource("gemini_cloud.available", defaultValue: "Gemini Cloud Ready", comment: "Overall intelligence status when a Gemini API key is configured.")
        static let availableDetail = L10n.resource("gemini_cloud.available.detail", defaultValue: "A Gemini API key is configured for explicitly selected cloud processing.", comment: "Overall intelligence detail when Gemini is configured.")
        static let settingsTitle = L10n.resource("gemini_cloud.settings.title", defaultValue: "Gemini Cloud", comment: "Settings section title for Gemini Cloud.")
        static let cloudModelTitle = L10n.resource("gemini_cloud.settings.cloud_model_title", defaultValue: "Cloud Model", comment: "Intelligence settings section title for cloud model submenus.")
        static let settingsErrorTitle = L10n.resource("gemini_cloud.settings.error_title", defaultValue: "Gemini Settings Failed", comment: "Alert title when the Gemini API key cannot be saved or removed.")
        static let submenuDescription = L10n.resource("gemini_cloud.settings.submenu_description", defaultValue: "Enable Gemini, manage the API key, and review token usage.", comment: "Subtitle for the Gemini Cloud settings submenu.")
        static let controlTitle = L10n.resource("gemini_cloud.settings.control_title", defaultValue: "Cloud Access", comment: "Gemini settings section title for its enable switch.")
        static let enableTitle = L10n.resource("gemini_cloud.settings.enable", defaultValue: "Enable Gemini Cloud", comment: "Toggle title that enables Gemini Cloud features.")
        static let enableDescription = L10n.resource("gemini_cloud.settings.enable.description", defaultValue: "Allow explicitly selected Gemini transcription and intelligence actions. Automatic mode remains local-only.", comment: "Gemini enable toggle description.")
        static let readyDescription = L10n.resource("gemini_cloud.settings.ready", defaultValue: "Gemini Cloud is enabled and an API key is configured.", comment: "Gemini ready status description.")
        static let notReadyDescription = L10n.resource("gemini_cloud.settings.not_ready", defaultValue: "Turn on Gemini Cloud and add an API key before using it.", comment: "Gemini unavailable status description.")
        static let apiConfigurationTitle = L10n.resource("gemini_cloud.settings.api_configuration", defaultValue: "API Configuration", comment: "Gemini settings API key section title.")
        static let statusOn = L10n.resource("gemini_cloud.settings.status.on", defaultValue: "On", comment: "Gemini settings submenu enabled status.")
        static let statusOff = L10n.resource("gemini_cloud.settings.status.off", defaultValue: "Off", comment: "Gemini settings submenu disabled status.")
        static let statusNeedsAPIKey = L10n.resource("gemini_cloud.settings.status.needs_api_key", defaultValue: "API Key Needed", comment: "Gemini settings submenu status when enabled without a key.")
        static let apiKey = L10n.resource("gemini_cloud.api_key", defaultValue: "Gemini API Key", comment: "Settings secure field title for the Gemini API key.")
        static let apiKeyPrompt = L10n.resource("gemini_cloud.api_key.prompt", defaultValue: "AIza...", comment: "Settings secure field prompt for a Gemini API key.")
        static let apiKeyDescription = L10n.resource("gemini_cloud.api_key.description", defaultValue: "The key is stored in Keychain and used directly by this iPhone to connect to Google's Gemini API.", comment: "Gemini BYOK storage explanation.")
        static let manualUploadDescription = L10n.resource("gemini_cloud.manual_upload.description", defaultValue: "Gemini receives audio and the current transcript draft only after you confirm Process with Gemini Cloud for a saved recording. Automatic mode never uploads content.", comment: "Gemini manual upload privacy explanation.")
        static let clearAPIKey = L10n.resource("gemini_cloud.api_key.clear", defaultValue: "Clear Gemini API Key", comment: "Button title for deleting the Gemini API key.")
        static let usageTitle = L10n.resource("gemini_cloud.usage.title", defaultValue: "Token Usage", comment: "Gemini token usage settings section title.")
        static let usageModel = L10n.resource("gemini_cloud.usage.model", defaultValue: "Model", comment: "Gemini usage model metric title.")
        static let usageRequests = L10n.resource("gemini_cloud.usage.requests", defaultValue: "Requests", comment: "Gemini cumulative request count metric title.")
        static let usageLastRequest = L10n.resource("gemini_cloud.usage.last_request", defaultValue: "Last Request Tokens", comment: "Gemini last request total token metric title.")
        static let usageTotalTokens = L10n.resource("gemini_cloud.usage.total_tokens", defaultValue: "Total Tokens", comment: "Gemini cumulative total token metric title.")
        static let usageInputTokens = L10n.resource("gemini_cloud.usage.input_tokens", defaultValue: "Input Tokens", comment: "Gemini cumulative input token metric title.")
        static let usageOutputTokens = L10n.resource("gemini_cloud.usage.output_tokens", defaultValue: "Output Tokens", comment: "Gemini cumulative output token metric title.")
        static let usageThoughtTokens = L10n.resource("gemini_cloud.usage.thought_tokens", defaultValue: "Thinking Tokens", comment: "Gemini cumulative thought token metric title.")
        static let usageCachedTokens = L10n.resource("gemini_cloud.usage.cached_tokens", defaultValue: "Cached Tokens", comment: "Gemini cumulative cached token metric title.")
        static let usageUpdatedFormat = L10n.resource("gemini_cloud.usage.updated.format", defaultValue: "Last updated: %@", comment: "Gemini usage last update text. Parameter: localized date and time.")
        static let usageLocalDescription = L10n.resource("gemini_cloud.usage.local_description", defaultValue: "Counts only Gemini requests made by this app on this device. Google AI Studio billing and quota remain authoritative.", comment: "Explanation of the locally tracked Gemini usage totals.")
        static let resetUsage = L10n.resource("gemini_cloud.usage.reset", defaultValue: "Reset Local Usage", comment: "Button title to reset locally tracked Gemini token usage.")
        static let invalidConfiguration = L10n.resource("gemini_cloud.error.invalid_configuration", defaultValue: "Gemini Cloud is not configured correctly.", comment: "Gemini configuration error.")
        static let disabledError = L10n.resource("gemini_cloud.error.disabled", defaultValue: "Turn on Gemini Cloud in Settings > Intelligence > Gemini Cloud first.", comment: "Gemini disabled error.")
        static let missingAPIKey = L10n.resource("gemini_cloud.error.missing_api_key", defaultValue: "Add a Gemini API key in Settings > Intelligence first.", comment: "Gemini missing API key error.")
        static let keychainUnavailable = L10n.resource("gemini_cloud.error.keychain_unavailable", defaultValue: "The Gemini API key could not be accessed in Keychain.", comment: "Gemini Keychain error.")
        static let audioFileUnavailable = L10n.resource("gemini_cloud.error.audio_unavailable", defaultValue: "The recording audio is unavailable or empty.", comment: "Gemini missing audio error.")
        static let unsupportedAudioFormat = L10n.resource("gemini_cloud.error.unsupported_audio", defaultValue: "The recording could not be converted to a Gemini-supported audio format.", comment: "Gemini unsupported audio error.")
        static let audioFileTooLarge = L10n.resource("gemini_cloud.error.audio_too_large", defaultValue: "The recording is too large for Gemini file upload.", comment: "Gemini audio size error.")
        static let fileProcessingFailed = L10n.resource("gemini_cloud.error.file_processing_failed", defaultValue: "Gemini could not process the uploaded audio file.", comment: "Gemini file processing error.")
        static let fileProcessingTimedOut = L10n.resource("gemini_cloud.error.file_processing_timeout", defaultValue: "Gemini timed out while preparing the uploaded audio file.", comment: "Gemini file processing timeout error.")
        static let requestFailedFormat = L10n.resource("gemini_cloud.error.request_failed.format", defaultValue: "Gemini request failed (HTTP %d).", comment: "Gemini HTTP error. Parameter: status code.")
        static let invalidResponse = L10n.resource("gemini_cloud.error.invalid_response", defaultValue: "Gemini returned a response the app could not read.", comment: "Gemini response decoding error.")
        static let invalidManualTranscriptJSON = L10n.resource("gemini_cloud.error.invalid_manual_transcript_json", defaultValue: "The pasted Gemini JSON could not be imported. Copy the complete JSON object and try again.", comment: "Error shown when manually pasted Gemini transcript JSON is incomplete or invalid.")
        static let emptyTranscript = L10n.resource("gemini_cloud.error.empty_transcript", defaultValue: "Gemini did not return any transcript text.", comment: "Gemini empty transcript error.")
        static let emptyResponse = L10n.resource("gemini_cloud.error.empty_response", defaultValue: "Gemini did not return a usable response.", comment: "Gemini empty response error.")
        static let transcriptBackupUnavailable = L10n.resource("gemini_cloud.error.backup_unavailable", defaultValue: "The transcript saved before Gemini processing is no longer available.", comment: "Missing pre-Gemini transcript backup error.")
    }

    enum LocalSummary {
        static let providerTitle = L10n.resource(
            "local_summary.provider.title",
            defaultValue: "AI Engine",
            comment: "Settings section title for selecting the default AI engine."
        )
        static let selectedProvider = L10n.resource(
            "local_summary.provider.selected",
            defaultValue: "Default Engine",
            comment: "Settings row title for the selected default summary engine."
        )
        static let providerAutomaticTitle = L10n.resource(
            "local_summary.provider.automatic.title",
            defaultValue: "Automatic",
            comment: "Summary engine option that automatically chooses an available local summary provider."
        )
        static let providerAutomaticDetail = L10n.resource(
            "local_summary.provider.automatic.detail",
            defaultValue: "Use Apple Intelligence when available, otherwise use the downloaded Local Qwen model.",
            comment: "Summary engine automatic option detail."
        )
        static let providerAppleTitle = L10n.resource(
            "local_summary.provider.apple.title",
            defaultValue: "Apple Intelligence",
            comment: "Summary engine option for Apple's on-device language model."
        )
        static let providerAppleDetail = L10n.resource(
            "local_summary.provider.apple.detail",
            defaultValue: "Use Apple's on-device language model for summaries and tags.",
            comment: "Summary engine Apple option detail."
        )
        static let providerLocalQwenTitle = L10n.resource(
            "local_summary.provider.local_qwen.title",
            defaultValue: "Local Qwen3",
            comment: "Summary engine option for the local Qwen model."
        )
        static let providerLocalQwenDetail = L10n.resource(
            "local_summary.provider.local_qwen.detail",
            defaultValue: "Use the selected downloaded Qwen GGUF model with embedded llama.cpp.",
            comment: "Summary engine Local Qwen option detail."
        )
        static let available = L10n.resource(
            "local_summary.available",
            defaultValue: "Local Qwen Ready",
            comment: "Overall intelligence status when local Qwen summaries are available."
        )
        static let availableDetail = L10n.resource(
            "local_summary.available.detail",
            defaultValue: "Apple Intelligence is unavailable, but Qwen3 summaries can run on this iPhone with embedded llama.cpp.",
            comment: "Overall intelligence detail when local Qwen summaries are available."
        )
        static let modelTitle = L10n.resource(
            "local_summary.model.title",
            defaultValue: "Local Summary Model",
            comment: "Settings section title for local summary model management."
        )
        static let selectedModel = L10n.resource(
            "local_summary.model.selected",
            defaultValue: "Summary Model",
            comment: "Settings metric title for the selected local summary model."
        )
        static let modelStatus = L10n.resource(
            "local_summary.model.status",
            defaultValue: "Model Status",
            comment: "Settings metric title for local summary model status."
        )
        static let modelReady = L10n.resource(
            "local_summary.model.ready",
            defaultValue: "Ready",
            comment: "Local summary model status when a model is available."
        )
        static let modelNotInstalled = L10n.resource(
            "local_summary.model.not_installed",
            defaultValue: "Not Installed",
            comment: "Local summary model status when a model is not installed."
        )
        static let modelDownloadedDetailFormat = L10n.resource(
            "local_summary.model.downloaded_detail.format",
            defaultValue: "%@ is downloaded on this iPhone (%@).",
            comment: "Local summary model downloaded detail. Parameters: model name, file size."
        )
        static let modelBundledDetailFormat = L10n.resource(
            "local_summary.model.bundled_detail.format",
            defaultValue: "%@ is bundled with this app (%@).",
            comment: "Local summary model bundled detail. Parameters: model name, file size."
        )
        static let modelMissingDetailFormat = L10n.resource(
            "local_summary.model.missing_detail.format",
            defaultValue: "Download %@ (%@) before using local summaries.",
            comment: "Local summary model missing detail. Parameters: model name, expected size."
        )
        static let downloadSelectedModel = L10n.resource(
            "local_summary.model.download_selected",
            defaultValue: "Download Qwen Model",
            comment: "Settings button title to download the selected local summary model."
        )
        static let deleteModelDownload = L10n.resource(
            "local_summary.model.delete_download",
            defaultValue: "Delete Qwen Download",
            comment: "Settings button title to delete the downloaded local summary model."
        )
        static let downloadingModelFormat = L10n.resource(
            "local_summary.model.downloading.format",
            defaultValue: "Downloading %.0f%%",
            comment: "Local summary model download progress. Parameter: percent complete."
        )
        static let downloadFailed = L10n.resource(
            "local_summary.model.download_failed",
            defaultValue: "Summary Model Download Failed",
            comment: "Alert title when a local summary model download fails."
        )
        static let deleteFailed = L10n.resource(
            "local_summary.model.delete_failed",
            defaultValue: "Summary Model Delete Failed",
            comment: "Alert title when deleting a local summary model fails."
        )
        static let runtimePending = L10n.resource(
            "local_summary.runtime.pending",
            defaultValue: "Qwen3 summaries run on this iPhone with embedded llama.cpp after the model is downloaded.",
            comment: "Settings status explaining that local summary inference runs on device."
        )
        static let runtimeUnavailable = L10n.resource(
            "local_summary.error.runtime_unavailable",
            defaultValue: "llama.cpp is not embedded in this build.",
            comment: "Local summary error when the native runtime cannot be loaded."
        )
        static let missingModel = L10n.resource(
            "local_summary.error.missing_model",
            defaultValue: "Download the Qwen local summary model in Settings before running local summaries.",
            comment: "Local summary error when no model file can be found."
        )
        static let modelDownloadFailed = L10n.resource(
            "local_summary.error.model_download_failed",
            defaultValue: "The Qwen local summary model download did not produce a valid GGUF model file.",
            comment: "Local summary invalid downloaded model error."
        )
        static let modelQwen3Title = L10n.resource(
            "local_summary.model.qwen3_1_7b_q4.title",
            defaultValue: "Qwen3 1.7B Q4_K_M",
            comment: "Local summary Qwen3 model name."
        )
        static let modelQwen3Detail = L10n.resource(
            "local_summary.model.qwen3_1_7b_q4.detail",
            defaultValue: "Multilingual offline summary model in GGUF Q4_K_M format.",
            comment: "Local summary Qwen3 model detail."
        )
    }

    enum Greeting {
        static let morning = L10n.resource("greeting.morning", defaultValue: "Good Morning!", comment: "Assistant greeting shown in the morning.")
        static let afternoon = L10n.resource("greeting.afternoon", defaultValue: "Good Afternoon!", comment: "Assistant greeting shown in the afternoon.")
        static let evening = L10n.resource("greeting.evening", defaultValue: "Good Evening!", comment: "Assistant greeting shown in the evening.")
    }

    enum AudioSession {
        static let recordingInProgress = L10n.resource(
            "audio_session.error.recording_in_progress",
            defaultValue: "Recording is currently using the audio session.",
            comment: "Playback error shown when recording already owns the audio session."
        )
    }

    enum StructuredRuntime {
        static let missingSymbolFormat = L10n.resource(
            "structured_runtime.error.missing_symbol.format",
            defaultValue: "Missing structured FoundationModels symbol: %@",
            comment: "Structured FoundationModels runtime error. Parameter: missing symbol name."
        )
        static let emptyResponse = L10n.resource(
            "structured_runtime.error.empty_response",
            defaultValue: "Structured FoundationModels returned an empty response.",
            comment: "Structured FoundationModels runtime error when no response is returned."
        )
    }

    enum Siri {
        static let noSummary = L10n.resource("siri.no_summary", defaultValue: "No summary is available for this recording.", comment: "Siri response when a recording has no summary.")
        static let noTranscript = L10n.resource("siri.no_transcript", defaultValue: "No transcript is available for this recording.", comment: "Siri response when a recording has no transcript.")
        static let searchNoMatches = L10n.resource("siri.search.no_matches", defaultValue: "No matching recordings were found.", comment: "Siri response when recording search has no matches.")
        static let searchMatchesFormat = L10n.resource("siri.search.matches.format", defaultValue: "Matching recordings: %d. %@.", comment: "Siri search result response. Parameters: result count and a comma-separated list of recording titles.")
        static let transcriptTruncated = L10n.resource("siri.transcript_truncated", defaultValue: "The transcript is longer, so I read the beginning. Open the recording to review the rest.", comment: "Siri message appended when a transcript is too long to read in full.")
    }

    enum ICloud {
        static let noRecordings = L10n.resource(
            "recordings.none",
            defaultValue: "No Recordings",
            comment: "Status shown when there are no saved recordings."
        )
        static let localPrivateContainer = L10n.resource(
            "storage.local_private_container",
            defaultValue: "Local Private Container",
            comment: "Storage display name for local app-private storage."
        )
        static let privateContainer = L10n.resource(
            "icloud.private_container",
            defaultValue: "Private iCloud Container",
            comment: "Storage display name for app-private iCloud storage."
        )
        static let disabled = L10n.resource(
            "storage.status.disabled",
            defaultValue: "Disabled",
            comment: "Generic disabled status."
        )
        static let enabled = L10n.resource(
            "storage.status.enabled",
            defaultValue: "Enabled",
            comment: "Generic enabled status."
        )
        static let switching = L10n.resource(
            "storage.status.switching",
            defaultValue: "Switching",
            comment: "Status shown while switching storage locations."
        )
        static let waitingForICloud = L10n.resource(
            "icloud.waiting_for_icloud",
            defaultValue: "Waiting for iCloud",
            comment: "Status shown while waiting for iCloud availability."
        )
        static let waitingToUpload = L10n.resource(
            "icloud.waiting_to_upload",
            defaultValue: "Waiting to Upload",
            comment: "Status shown while waiting for iCloud upload."
        )
        static let uploading = L10n.resource(
            "icloud.uploading",
            defaultValue: "Uploading",
            comment: "Status while uploading to iCloud."
        )
        static let uploadedToICloud = L10n.resource(
            "icloud.uploaded_to_icloud",
            defaultValue: "Uploaded to iCloud",
            comment: "Status when a recording has uploaded to iCloud."
        )
        static let uploadFailed = L10n.resource(
            "icloud.upload_failed",
            defaultValue: "Upload Failed",
            comment: "Status when iCloud upload failed."
        )
        static let allUploaded = L10n.resource(
            "icloud.all_uploaded",
            defaultValue: "All Uploaded",
            comment: "Status when every recording has uploaded to iCloud."
        )
        static let noRecordingsToSync = L10n.resource(
            "icloud.no_recordings_to_sync",
            defaultValue: "There are no recordings to sync.",
            comment: "Sync summary detail shown when there are no recordings."
        )
        static let localOnly = L10n.resource(
            "icloud.local_only",
            defaultValue: "Local Only",
            comment: "Status shown when a recording is only stored locally."
        )
        static let recordingLocalOnly = L10n.resource(
            "icloud.recording_local_only",
            defaultValue: "This recording is still in the local app-private container.",
            comment: "Per-recording detail shown when a recording has not moved to iCloud."
        )
        static let recordingStaysLocal = L10n.resource(
            "icloud.container_unavailable.recording_stays_local",
            defaultValue: "The iCloud container is currently unavailable, so this recording stays local for now.",
            comment: "Per-recording detail shown when the iCloud container is unavailable."
        )
        static let recordingWaitingUpload = L10n.resource(
            "icloud.recording_waiting_upload",
            defaultValue: "This recording is in the private iCloud container and is waiting for the system to upload it.",
            comment: "Per-recording detail shown when recording files are waiting for iCloud upload."
        )
        static let recordingUploaded = L10n.resource(
            "icloud.recording_uploaded",
            defaultValue: "This recording's audio and transcript files have uploaded to iCloud.",
            comment: "Per-recording detail shown when recording files have uploaded to iCloud."
        )
        static let uploadFailedDetail = L10n.resource(
            "icloud.upload_failed.detail",
            defaultValue: "iCloud upload failed",
            comment: "Per-recording detail shown when iCloud upload failed and no detailed error is available."
        )
        static let detailSwitchingStorage = L10n.resource(
            "icloud.detail.switching_storage",
            defaultValue: "Switching storage location while keeping existing recordings.",
            comment: "Storage detail shown while moving between local and iCloud storage."
        )
        static let detailDisabled = L10n.resource(
            "icloud.detail.disabled",
            defaultValue: "iCloud is off. Recording files and the index are stored in the local app-private container.",
            comment: "Storage detail shown when iCloud storage is disabled."
        )
        static let detailEnabled = L10n.resource(
            "icloud.detail.enabled",
            defaultValue: "iCloud is on. Recording files are saved in the Data directory of the app-private iCloud container, and the index syncs through a CloudKit private database.",
            comment: "Storage detail shown when iCloud storage is enabled and available."
        )
        static let detailContainerUnavailable = L10n.resource(
            "icloud.detail.container_unavailable",
            defaultValue: "iCloud is on, but the iCloud container is not currently reachable. Until it is available, recordings are kept in the local app-private container.",
            comment: "Storage detail shown when iCloud is enabled but the container is unavailable."
        )
        static let disabledAllLocal = L10n.resource(
            "icloud.disabled_all_local",
            defaultValue: "iCloud is off. All recordings are stored only in the local app-private container.",
            comment: "Sync summary detail shown when iCloud is disabled."
        )
        static let enabledButUnavailableLocalFirst = L10n.resource(
            "icloud.enabled_but_unavailable_local_first",
            defaultValue: "iCloud is on, but the iCloud container is not currently reachable. Recordings are kept local for now.",
            comment: "Sync summary detail shown when iCloud is enabled but unavailable."
        )
        static let filesUploadedFormat = L10n.resource(
            "icloud.files_uploaded.format",
            defaultValue: "%d/%d files uploaded",
            comment: "iCloud file upload progress. Parameters: uploaded file count, total file count."
        )
        static let localRecordingsCountFormat = L10n.resource(
            "icloud.local_recordings_count.format",
            defaultValue: "%d local recordings",
            comment: "Number of recordings stored locally. Parameter: recording count."
        )
        static let uploadFailedCountFormat = L10n.resource(
            "icloud.upload_failed_count.format",
            defaultValue: "%d upload failed",
            comment: "Number of recordings with failed iCloud upload. Parameter: failed recording count."
        )
        static let uploadedCountFormat = L10n.resource(
            "icloud.uploaded_count.format",
            defaultValue: "%d/%d Uploaded",
            comment: "Number of recordings uploaded out of total. Parameters: uploaded count, total count."
        )
        static let syncSummaryCountsFormat = L10n.resource(
            "icloud.sync_summary_counts.format",
            defaultValue: "Uploaded %d, uploading %d, waiting %d, failed %d, local %d",
            comment: "Detailed iCloud sync summary. Parameters: uploaded, uploading, waiting, failed, local."
        )
    }
}
