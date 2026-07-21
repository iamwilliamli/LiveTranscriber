import SwiftUI
import TranscriberDomain

enum MacOnboardingState {
    static let completedDefaultsKey = "onboarding.introduction.completed.v1"
}

enum MacSidebarDestination: String, CaseIterable, Identifiable {
    case transcribe
    case recordings
    case settings

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .transcribe:
            return L10n.App.transcribeTab
        case .recordings:
            return L10n.App.recordingsTab
        case .settings:
            return L10n.App.settingsTab
        }
    }

    var systemImage: String {
        switch self {
        case .transcribe:
            return "waveform.and.mic"
        case .recordings:
            return "folder"
        case .settings:
            return "gearshape"
        }
    }
}

@MainActor
final class MacAppRouter: ObservableObject {
    @Published var requestedDestination: MacSidebarDestination?
    @Published var selectedRecordingID: RecordingItem.ID?
    @Published var pendingImportURLs: [URL] = []
    @Published var pendingRecordingDraft: RecordingDraft?
    @Published var shouldStartRecording = false
    @Published var shouldStopRecording = false

    func handle(_ url: URL) {
        if url.isFileURL {
            pendingImportURLs.append(url)
            requestedDestination = .recordings
            return
        }

        guard url.scheme?.lowercased() == "livetranscriber",
              let host = url.host?.lowercased() else {
            return
        }

        switch host {
        case "recording":
            guard let identifier = url.pathComponents.dropFirst().first,
                  let recordingID = UUID(uuidString: identifier) else {
                return
            }
            selectedRecordingID = recordingID
            requestedDestination = .recordings
        case "record", "transcribe":
            requestedDestination = .transcribe
            if URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(where: { $0.name == "start" && $0.value != "0" }) == true {
                shouldStartRecording = true
            }
        case "stop-recording":
            requestedDestination = .transcribe
            shouldStopRecording = true
        case "recordings", "files":
            requestedDestination = .recordings
        case "capture":
            requestedDestination = .transcribe
        case "capture-library":
            requestedDestination = .recordings
        case "settings":
            requestedDestination = .settings
        default:
            break
        }
    }
}

struct MacRootView: View {
    @EnvironmentObject private var recordingStore: RecordingStore
    @EnvironmentObject private var transcriber: LiveTranscriptionManager
    @EnvironmentObject private var router: MacAppRouter
    @EnvironmentObject private var systemAudioCapture: MacSystemAudioCaptureController
    @State private var selection: MacSidebarDestination? = .transcribe

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(MacSidebarDestination.allCases) { destination in
                        Label {
                            Text(destination.title)
                        } icon: {
                            Image(systemName: destination.systemImage)
                        }
                        .tag(destination)
                    }
                } header: {
                    Text(MacL10n.workspace)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(Text(MacL10n.appName))
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            switch selection ?? .transcribe {
            case .transcribe:
                MacTranscriptionView(
                    transcriber: transcriber,
                    recordingStore: recordingStore,
                    systemAudioCapture: systemAudioCapture,
                    pendingDraft: $router.pendingRecordingDraft,
                    externalStartRequested: $router.shouldStartRecording,
                    externalStopRequested: $router.shouldStopRecording
                )
            case .recordings:
                MacRecordingsView(
                    store: recordingStore,
                    transcriber: transcriber,
                    selectedRecordingID: $router.selectedRecordingID,
                    pendingImportURLs: $router.pendingImportURLs
                )
            case .settings:
                MacSettingsView()
                    .environmentObject(recordingStore)
                    .environmentObject(transcriber)
            }
        }
        .task {
            await recordingStore.reload()
            await transcriber.refreshSupportedLanguages()
            applyRouterState()
        }
        .onChange(of: router.requestedDestination) { _, destination in
            if let destination {
                selection = destination
            }
        }
    }

    private func applyRouterState() {
        if let requestedDestination = router.requestedDestination {
            selection = requestedDestination
        }
    }
}

struct MacSettingsView: View {
    var body: some View {
        TabView {
            MacTranscriptionSettingsPane()
                .tabItem {
                    Label {
                        Text(L10n.Settings.transcription)
                    } icon: {
                        Image(systemName: "waveform")
                    }
                }

            MacIntelligenceSettingsPane()
                .tabItem {
                    Label {
                        Text(L10n.Settings.intelligence)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }

            MacRecordingSettingsPane()
                .tabItem {
                    Label {
                        Text(L10n.Settings.recording)
                    } icon: {
                        Image(systemName: "mic")
                    }
                }

            MacFilesSettingsPane()
                .tabItem {
                    Label {
                        Text(L10n.Settings.files)
                    } icon: {
                        Image(systemName: "externaldrive")
                    }
                }

            MacPrivacySettingsPane()
                .tabItem {
                    Label {
                        Text(L10n.Settings.privacy)
                    } icon: {
                        Image(systemName: "hand.raised")
                    }
                }

            MacHelpSettingsPane()
                .tabItem {
                    Label {
                        Text(MacL10n.helpAndFeedback)
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                }

            MacDeveloperSettingsPane()
                .tabItem {
                    Label {
                        Text(L10n.Settings.developerOptions)
                    } icon: {
                        Image(systemName: "hammer")
                    }
                }
        }
        .frame(minWidth: 640, minHeight: 520)
        .navigationTitle(Text(MacL10n.settingsTitle))
    }
}

struct MacOnboardingView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    let onComplete: () -> Void

    @StateObject private var mossModel = MacMOSSModelController()
    @State private var selectedSummaryModel = LocalSummaryModelManager.selectedModel
    @State private var summaryModelStatus = LocalSummaryModelManager.currentStatus()
    @State private var summaryDownloadProgress: Double?
    @State private var errorMessage: String?

    private let features: [(String, LocalizedStringResource, LocalizedStringResource, Color)] = [
        ("waveform.and.mic", L10n.Onboarding.liveTitle, L10n.Onboarding.liveDetail, AppTheme.brand),
        ("folder.badge.gearshape", L10n.Onboarding.recordingsTitle, L10n.Onboarding.recordingsDetail, AppTheme.info),
        ("lock.shield", L10n.Onboarding.privacyTitle, L10n.Onboarding.privacyDetail, AppTheme.success),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.brand.opacity(0.16),
                    AppTheme.purple.opacity(0.10),
                    AppTheme.groupedBackground,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    onboardingHero
                    featureGrid
                    quickSetup
                    onboardingActions
                }
                .padding(32)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            await transcriber.refreshSupportedLanguages()
            mossModel.refresh()
            selectedSummaryModel = LocalSummaryModelManager.selectedModel
            summaryModelStatus = LocalSummaryModelManager.currentStatus()
        }
        .alert(
            String(localized: MacL10n.actionFailed),
            isPresented: Binding(
                get: { errorMessage != nil || mossModel.errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                        mossModel.errorMessage = nil
                        mossModel.errorTitle = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? mossModel.errorMessage ?? "")
        }
    }

    private var onboardingHero: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 112, height: 112)
                    .shadow(color: AppTheme.brand.opacity(0.24), radius: 28, y: 12)

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(AppTheme.brand)
            }

            Text(L10n.Onboarding.title)
                .font(.system(size: 38, weight: .bold, design: .rounded))

            Text(L10n.Onboarding.caption)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)

            HStack(spacing: 8) {
                onboardingChip(L10n.Onboarding.heroChipLive, icon: "dot.radiowaves.left.and.right", tint: AppTheme.brand)
                onboardingChip(L10n.Onboarding.heroChipMOSS, icon: "person.2", tint: AppTheme.purple)
                onboardingChip(L10n.Onboarding.heroChipPrivate, icon: "lock.fill", tint: AppTheme.success)
            }
        }
        .padding(.top, 12)
    }

    private var featureGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: feature.0)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(feature.3)
                        .frame(width: 50, height: 50)
                        .background(feature.3.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))

                    Text(feature.1)
                        .font(.headline)
                    Text(feature.2)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var quickSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(L10n.Onboarding.setupTitle)
                    .font(.title3.bold())
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(AppTheme.brand)
            }

            Form {
                Picker(selection: Binding(
                    get: { transcriber.selectedLanguageID },
                    set: { transcriber.selectedLanguageID = $0 }
                )) {
                    ForEach(transcriber.supportedLanguages.isEmpty ? TranscriptionLanguage.fallbackOptions : transcriber.supportedLanguages) { language in
                        Text(verbatim: language.displayName)
                            .tag(language.id)
                    }
                } label: {
                    Text(L10n.Onboarding.languageTitle)
                }

                Picker(selection: Binding(
                    get: { transcriber.selectedAudioFormat },
                    set: { transcriber.selectedAudioFormat = $0 }
                )) {
                    ForEach(RecordingAudioFormat.allCases) { format in
                        Text(format.title)
                            .tag(format)
                    }
                } label: {
                    Text(L10n.Onboarding.formatTitle)
                }

                modelSetupRow(
                    title: L10n.Onboarding.mossModelTitle,
                    detail: mossModel.status.detailText,
                    status: mossModel.status.statusText,
                    isAvailable: mossModel.status.isAvailable,
                    progress: mossModel.isDownloading ? mossModel.downloadProgress : nil,
                    actionTitle: L10n.MOSSLocal.downloadModel,
                    action: mossModel.download
                )

                Picker(selection: Binding(
                    get: { selectedSummaryModel.id },
                    set: { modelID in
                        guard let model = LocalSummaryModelManager.availableModels.first(where: { $0.id == modelID }) else {
                            return
                        }
                        selectedSummaryModel = model
                        LocalSummaryModelManager.selectModel(model)
                        summaryModelStatus = LocalSummaryModelManager.status(for: model)
                    }
                )) {
                    ForEach(LocalSummaryModelManager.availableModels) { model in
                        Text(verbatim: model.displayName)
                            .tag(model.id)
                    }
                } label: {
                    Text(L10n.LocalSummary.modelTitle)
                }

                modelSetupRow(
                    title: L10n.LocalSummary.modelStatus,
                    detail: summaryModelStatus.detailText,
                    status: summaryModelStatus.statusText,
                    isAvailable: summaryModelStatus.isAvailable,
                    progress: summaryDownloadProgress,
                    actionTitle: L10n.LocalSummary.downloadSelectedModel,
                    action: downloadSummaryModel
                )
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(minHeight: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var onboardingActions: some View {
        VStack(spacing: 10) {
            Button {
                onComplete()
            } label: {
                Label {
                    Text(L10n.Onboarding.cta)
                } icon: {
                    Image(systemName: "waveform.and.mic")
                }
                .font(.headline)
                .frame(maxWidth: 420)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text(L10n.Onboarding.footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func modelSetupRow(
        title: LocalizedStringResource,
        detail: String,
        status: String,
        isAvailable: Bool,
        progress: Double?,
        actionTitle: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            LabeledContent {
                Text(verbatim: status)
                    .foregroundStyle(isAvailable ? AppTheme.success : .secondary)
            } label: {
                Text(title)
            }
            Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: progress)
            } else if !isAvailable {
                Button(action: action) {
                    Text(actionTitle)
                }
            }
        }
    }

    private func onboardingChip(
        _ text: LocalizedStringResource,
        icon: String,
        tint: Color
    ) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func downloadSummaryModel() {
        summaryDownloadProgress = 0
        let model = selectedSummaryModel
        Task {
            do {
                summaryModelStatus = try await LocalSummaryModelManager.download(model: model) { progress in
                    Task { @MainActor in
                        summaryDownloadProgress = progress
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                summaryModelStatus = LocalSummaryModelManager.status(for: model)
            }
            summaryDownloadProgress = nil
        }
    }
}
