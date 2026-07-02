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

    enum Settings {
        static let title = L10n.resource("settings.title", defaultValue: "Settings", comment: "Settings screen title.")
        static let transcription = L10n.resource("settings.transcription", defaultValue: "Transcription", comment: "Settings section title for transcription.")
        static let recording = L10n.resource("settings.recording", defaultValue: "Recording", comment: "Settings section title for recording.")
        static let files = L10n.resource("settings.files", defaultValue: "Files", comment: "Settings section title for files.")
        static let privacy = L10n.resource("settings.privacy", defaultValue: "Privacy", comment: "Settings section title for privacy.")
        static let localProcessing = L10n.resource("settings.local_processing", defaultValue: "Local Processing", comment: "Privacy setting value and section title.")
        static let developerOptions = L10n.resource("settings.developer_options", defaultValue: "Developer Options", comment: "Developer options settings title.")
        static let languageAndModel = L10n.resource("settings.subtitle.language_model", defaultValue: "Language and transcription model", comment: "Settings row subtitle.")
        static let audioFormatAndBehavior = L10n.resource("settings.subtitle.audio_format_behavior", defaultValue: "Audio format and recording behavior", comment: "Settings row subtitle.")
        static let storageLocationAndCount = L10n.resource("settings.subtitle.storage_location_count", defaultValue: "Storage location and recording count", comment: "Settings row subtitle.")
        static let dataBoundariesAndPermissions = L10n.resource("settings.subtitle.data_boundaries_permissions", defaultValue: "Data boundaries and permission usage", comment: "Settings row subtitle.")
        static let deviceAndPipelineDiagnostics = L10n.resource("settings.subtitle.device_pipeline_diagnostics", defaultValue: "Device and pipeline diagnostics", comment: "Settings row subtitle.")
        static let transcriptionLanguage = L10n.resource("settings.transcription_language", defaultValue: "Transcription Language", comment: "Settings row title for transcription language.")
        static let nextStartUsesLanguage = L10n.resource("settings.next_start_uses_language", defaultValue: "The selected language will be used next time recording starts", comment: "Transcription language row subtitle.")
        static let cannotChangeLanguageWhileRecording = L10n.resource("settings.cannot_change_language_while_recording", defaultValue: "Language cannot be changed while recording", comment: "Warning shown while recording.")
        static let recordingFormat = L10n.resource("settings.recording_format", defaultValue: "Recording Format", comment: "Settings row title for recording format.")
        static let cannotChangeFormatWhileRecording = L10n.resource("settings.cannot_change_format_while_recording", defaultValue: "Format cannot be changed while recording", comment: "Warning shown while recording.")
        static let noDeveloperServers = L10n.resource("settings.privacy.no_developer_servers", defaultValue: "No developer-operated servers, third-party analytics, ads, tracking, or custom network requests are used.", comment: "Privacy explanation.")
        static let onDeviceProcessing = L10n.resource("settings.privacy.on_device_processing", defaultValue: "Recordings, transcripts, summaries, and tags are processed on device with Apple system frameworks.", comment: "Privacy explanation.")
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

    enum SpeechText {
        static let runtimeInputWaitingRecording = L10n.resource("speech.runtime_input.waiting_recording", defaultValue: "Runtime Analyzer input: waiting for recording", comment: "Developer speech pipeline diagnostic.")
        static let runtimeInputWaitingFirstBuffer = L10n.resource("speech.runtime_input.waiting_first_buffer", defaultValue: "Runtime Analyzer input: waiting for first buffer", comment: "Developer speech pipeline diagnostic.")
        static let runtimeInputMicToAnalyzerFormat = L10n.resource("speech.runtime_input.mic_to_analyzer.format", defaultValue: "Runtime Analyzer input: Mic %@ -> Analyzer %@", comment: "Developer speech pipeline diagnostic. Parameters: mic format, analyzer format.")
        static let recordingStartFailedFormat = L10n.resource("speech.error.recording_start_failed.format", defaultValue: "Recording failed to start: %@", comment: "Recording start error. Parameter: error description.")
        static let recordingResumeFailed = L10n.resource("speech.error.recording_resume_failed", defaultValue: "Recording resume failed", comment: "Recording resume error.")
        static let recordingResumeFailedFormat = L10n.resource("speech.error.recording_resume_failed.format", defaultValue: "Recording resume failed: %@", comment: "Recording resume error. Parameter: error description.")
        static let speechRestricted = L10n.resource("speech.error.restricted", defaultValue: "Speech recognition is restricted by the system", comment: "Speech permission error.")
        static let speechDenied = L10n.resource("speech.error.denied", defaultValue: "Speech recognition permission was denied", comment: "Speech permission error.")
        static let microphoneDenied = L10n.resource("speech.error.microphone_denied", defaultValue: "Microphone permission was denied", comment: "Microphone permission error.")
        static let compatiblePipelineDetail = L10n.resource("speech.pipeline.compatible.detail", defaultValue: "Uses 16 kHz mono Int16 input to keep iOS 26/27 timestamps stable.", comment: "Speech pipeline mode detail.")
        static let nativePipelineDetail = L10n.resource("speech.pipeline.native.detail", defaultValue: "Uses the iOS 27 compatibleWith converter so the system chooses the Speech input pipeline.", comment: "Speech pipeline mode detail.")
        static let supportedPipelinesIOS27 = L10n.resource("speech.pipeline.supported.ios27", defaultValue: "Supported pipelines: iOS 27 Native AnalyzerInputConverter; Compatible AVAudioConverter", comment: "Developer speech pipeline diagnostic.")
        static let analyzerAdaptiveIOS27 = L10n.resource("speech.pipeline.analyzer_adaptive.ios27", defaultValue: "Analyzer input: iOS 27 system-adaptive. Actual Hz is shown by Runtime Analyzer input while recording.", comment: "Developer speech pipeline diagnostic.")
        static let analyzerFixed16K = L10n.resource("speech.pipeline.analyzer_fixed_16k", defaultValue: "Analyzer input: 16 kHz / mono / Int16 PCM", comment: "Developer speech pipeline diagnostic.")
        static let supportedPipelinesIOS26 = L10n.resource("speech.pipeline.supported.ios26", defaultValue: "Supported pipelines: iOS 26 AVAudioConverter fallback", comment: "Developer speech pipeline diagnostic.")
        static let cannotReadMicrophone = L10n.resource("speech.error.cannot_read_microphone", defaultValue: "Could not read microphone input", comment: "Speech pipeline error.")
        static let analyzerUnavailable = L10n.resource("speech.error.analyzer_unavailable", defaultValue: "Speech analyzer unavailable", comment: "Speech pipeline error.")
        static let unsupportedLanguage = L10n.resource("speech.error.unsupported_language", defaultValue: "This language is not supported", comment: "Speech pipeline error.")
        static let stereoUnsupported = L10n.resource("speech.error.stereo_unsupported", defaultValue: "The current microphone does not support AVCapture stereo capture", comment: "Speech pipeline error.")
        static let compatiblePipelineTitle = L10n.resource("speech.pipeline.compatible.title", defaultValue: "Compatible Pipeline", comment: "Speech pipeline mode title.")
        static let nativePipelineTitle = L10n.resource("speech.pipeline.native.title", defaultValue: "iOS 27 Native Pipeline", comment: "Speech pipeline mode title.")
        static let activeNativeCompatibleWith = L10n.resource("speech.pipeline.active.native_compatible_with", defaultValue: "iOS 27 Native compatibleWith", comment: "Active speech pipeline diagnostic value.")
        static let activeCompatibleAVAudioConverter = L10n.resource("speech.pipeline.active.compatible_avaudio_converter", defaultValue: "iOS 27 Compatible AVAudioConverter", comment: "Active speech pipeline diagnostic value.")
        static let activeIOS26AVAudioConverter = L10n.resource("speech.pipeline.active.ios26_avaudio_converter", defaultValue: "iOS 26 AVAudioConverter", comment: "Active speech pipeline diagnostic value.")
    }

    enum Import {
        static let importingRecording = L10n.resource("import.status.importing_recording", defaultValue: "Importing recording", comment: "Import status message.")
        static let preparingTranscription = L10n.resource("import.status.preparing_transcription", defaultValue: "Preparing transcription", comment: "Import status message.")
        static let transcribing = L10n.resource("import.status.transcribing", defaultValue: "Transcribing", comment: "Import status message.")
        static let emptyRecordingName = L10n.resource("import.error.empty_recording_name", defaultValue: "Recording name cannot be empty", comment: "Recording detail validation error.")
        static let duplicateRecordingName = L10n.resource("import.error.duplicate_recording_name", defaultValue: "A recording file with this name already exists", comment: "Recording detail validation error.")
        static let recordingFileNotFound = L10n.resource("import.error.recording_file_not_found", defaultValue: "Recording file could not be found", comment: "Recording detail validation error.")
        static let noRecognizedText = L10n.resource("import.error.no_recognized_text", defaultValue: "No text was recognized in the imported recording", comment: "Import transcription error.")
        static let saveFailed = L10n.resource("import.error.save_failed", defaultValue: "Imported recording could not be saved", comment: "Import save error.")
    }

    enum Recordings {
        static let title = L10n.resource("recordings.title", defaultValue: "Recordings", comment: "Recordings list screen title.")
        static let searchPrompt = L10n.resource("recordings.search_prompt", defaultValue: "Search recordings or transcripts", comment: "Search prompt on recordings list.")
        static let chooseTranscriptionLanguage = L10n.resource("recordings.choose_transcription_language", defaultValue: "Choose Transcription Language", comment: "Dialog title for choosing a transcription language.")
        static let importRecording = L10n.resource("recordings.import_recording", defaultValue: "Import Recording", comment: "Import recording action or dialog message.")
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
        static let retranscribe = L10n.resource("recordings.retranscribe", defaultValue: "Transcribe Again", comment: "Action title to retranscribe a recording.")
        static let analyze = L10n.resource("recordings.analyze", defaultValue: "Analyze", comment: "Analyze action title.")
        static let noLocatedRecordings = L10n.resource("recordings.no_located_recordings", defaultValue: "No Recordings with Location", comment: "Empty state title for map with no located recordings.")
        static let mapTitle = L10n.resource("recordings.map_title", defaultValue: "Recording Map", comment: "Recording map screen title.")
        static let analyzing = L10n.resource("recordings.analyzing", defaultValue: "Analyzing", comment: "Status shown while analyzing.")
        static let audioParameters = L10n.resource("recordings.audio_parameters", defaultValue: "Audio Parameters", comment: "Audio parameters screen or section title.")
        static let renameFailed = L10n.resource("recordings.rename_failed", defaultValue: "Rename Failed", comment: "Alert title for rename failure.")
        static let rename = L10n.resource("recordings.rename", defaultValue: "Rename", comment: "Rename action title.")
        static let shareAudio = L10n.resource("recordings.share_audio", defaultValue: "Share Audio", comment: "Share audio action title.")
        static let shareTranscript = L10n.resource("recordings.share_transcript", defaultValue: "Share Transcript Text", comment: "Share transcript text action title.")
        static let share = L10n.resource("recordings.share", defaultValue: "Share", comment: "Share menu title.")
        static let copied = L10n.resource("recordings.copied", defaultValue: "Copied", comment: "Status shown after copying.")
        static let intelligenceAnalysis = L10n.resource("recordings.intelligence_analysis", defaultValue: "Intelligent Analysis", comment: "Intelligent analysis action title.")
        static let intelligenceSummary = L10n.resource("recordings.intelligence_summary", defaultValue: "Summary", comment: "Intelligent summary section title.")
        static let noSummary = L10n.resource("recordings.no_summary", defaultValue: "No Summary", comment: "Empty state title when no summary exists.")
        static let sampleRate = L10n.resource("recordings.audio.sample_rate", defaultValue: "Sample Rate", comment: "Audio parameter row title.")
        static let channels = L10n.resource("recordings.audio.channels", defaultValue: "Channels", comment: "Audio parameter row title.")
        static let encoding = L10n.resource("recordings.audio.encoding", defaultValue: "Encoding", comment: "Audio parameter row title.")
        static let processingFormat = L10n.resource("recordings.audio.processing_format", defaultValue: "Processing Format", comment: "Audio parameter row title.")
        static let pcmBitDepth = L10n.resource("recordings.audio.pcm_bit_depth", defaultValue: "PCM Bit Depth", comment: "Audio parameter row title.")
        static let audioDuration = L10n.resource("recordings.audio.duration", defaultValue: "Audio Duration", comment: "Audio parameter row title.")
        static let audioFrames = L10n.resource("recordings.audio.frames", defaultValue: "Audio Frames", comment: "Audio parameter row title.")
        static let fileSize = L10n.resource("recordings.audio.file_size", defaultValue: "File Size", comment: "Audio parameter row title.")
        static let iCloudSync = L10n.resource("recordings.audio.icloud_sync", defaultValue: "iCloud Sync", comment: "Audio parameter row title.")
        static let readingAudioParameters = L10n.resource("recordings.audio.reading_parameters", defaultValue: "Reading audio parameters", comment: "Status shown while reading audio parameters.")
        static let pause = L10n.resource("recordings.playback.pause", defaultValue: "Pause", comment: "Playback pause button accessibility label.")
        static let play = L10n.resource("recordings.playback.play", defaultValue: "Play", comment: "Playback play button accessibility label.")
        static let transcript = L10n.resource("recordings.transcript", defaultValue: "Transcript", comment: "Transcript section title.")
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
