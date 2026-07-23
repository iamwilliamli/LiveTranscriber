import SwiftUI
import TranscriberDomain

enum MacOnboardingState {
    static let completedDefaultsKey = "onboarding.introduction.completed.v1"
}

enum MacAppLanguage: String, CaseIterable, Identifiable {
    static let defaultsKey = "app.interfaceLanguage"
    static let selectionAtLaunch = selected

    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case german = "de"
    case dutch = "nl"

    var id: Self { self }

    static var selected: MacAppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let language = MacAppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    var locale: Locale {
        guard let localeIdentifier else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: localeIdentifier)
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english, .simplifiedChinese, .traditionalChinese, .japanese, .german, .dutch:
            return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: MacL10n.followSystemLanguage)
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .japanese:
            return "日本語"
        case .german:
            return "Deutsch"
        case .dutch:
            return "Nederlands"
        }
    }

    func applyBundlePreference() {
        if let localeIdentifier {
            UserDefaults.standard.set([localeIdentifier], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
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
    @EnvironmentObject private var recordingStore: RecordingStore
    @EnvironmentObject private var transcriber: LiveTranscriptionManager
    @AppStorage(MacAppLanguage.defaultsKey) private var appLanguageRawValue = MacAppLanguage.system.rawValue
    @State private var selection: MacSettingsDestination = .general

    var body: some View {
        HSplitView {
            settingsNavigation
                .frame(minWidth: 270, idealWidth: 305, maxWidth: 350)

            VStack(spacing: 0) {
                settingsDetailHeader
                Divider()
                selectedPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.groupedBackground)
        }
        .frame(minWidth: 800, minHeight: 560)
        .navigationTitle(Text(MacL10n.settingsTitle))
    }

    private var settingsNavigation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Settings.title)
                        .font(.redditSans(.title2, weight: .bold))
                    Label {
                        Text(L10n.Settings.localProcessing)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                    }
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)

                ForEach(MacSettingsDestination.sidebarDestinations) { destination in
                    Button {
                        selection = destination
                    } label: {
                        MacSettingsNavigationRow(
                            destination: destination,
                            value: value(for: destination),
                            isSelected: destination == .about
                                ? selection.isAboutDestination
                                : selection == destination
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(AppTheme.groupedBackground)
    }

    private var settingsDetailHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: selection.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(selection.tint)
                .frame(width: 44, height: 44)
                .background(
                    selection.tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.redditSans(.title3, weight: .bold))
                Text(selection.subtitle)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            let currentValue = value(for: selection)
            if !currentValue.isEmpty {
                Text(verbatim: currentValue)
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(selection.tint)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(selection.tint.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .background(AppTheme.cardBackground)
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selection {
        case .general:
            MacGeneralSettingsPane()
        case .transcription:
            MacTranscriptionSettingsPane()
        case .recording:
            MacRecordingSettingsPane()
        case .intelligence:
            MacIntelligenceSettingsPane()
        case .files:
            MacFilesSettingsPane()
        case .privacy:
            MacPrivacySettingsPane()
        case .developer:
            MacDeveloperSettingsPane()
        case .about:
            MacAboutSettingsPane(
                openPrivacy: { selection = .privacy },
                openDeveloperOptions: { selection = .developer }
            )
        }
    }

    private func value(for destination: MacSettingsDestination) -> String {
        switch destination {
        case .general:
            return (MacAppLanguage(rawValue: appLanguageRawValue) ?? .system).displayName
        case .transcription:
            return transcriber.selectedLanguage.displayName
        case .recording:
            return transcriber.selectedAudioFormat.title
        case .intelligence:
            return recordingStore.intelligenceAvailability.statusText
        case .files:
            return recordingStore.storageDisplayName
        case .privacy:
            return String(localized: L10n.Settings.localProcessing)
        case .developer:
            return transcriber.speechPipelineDiagnostics.activePipelineName
        case .about:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            return version.map { "v\($0)" } ?? ""
        }
    }
}

private enum MacSettingsDestination: String, CaseIterable, Identifiable {
    case general
    case transcription
    case recording
    case intelligence
    case files
    case privacy
    case developer
    case about

    var id: Self { self }

    static let sidebarDestinations: [Self] = [
        .general,
        .transcription,
        .recording,
        .intelligence,
        .files,
        .about,
    ]

    var isAboutDestination: Bool {
        self == .about || self == .privacy || self == .developer
    }

    var title: LocalizedStringResource {
        switch self {
        case .general: MacL10n.generalSettings
        case .transcription: L10n.Settings.transcription
        case .recording: L10n.Settings.recording
        case .intelligence: L10n.Settings.intelligence
        case .files: L10n.Settings.files
        case .privacy: L10n.Settings.privacy
        case .developer: L10n.Settings.developerOptions
        case .about: L10n.Settings.about
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .general: MacL10n.generalSettingsSubtitle
        case .transcription: L10n.Settings.languageAndModel
        case .recording: L10n.Settings.audioFormatAndBehavior
        case .intelligence: L10n.Settings.summariesAndLocalModels
        case .files: L10n.Settings.storageLocationAndCount
        case .privacy: L10n.Settings.dataBoundariesAndPermissions
        case .developer: L10n.Settings.deviceAndPipelineDiagnostics
        case .about: L10n.Settings.aboutSubtitle
        }
    }

    var systemImage: String {
        switch self {
        case .general: "globe"
        case .transcription: "captions.bubble"
        case .recording: "waveform.badge.mic"
        case .intelligence: "sparkles"
        case .files: "folder"
        case .privacy: "lock.shield"
        case .developer: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: AppTheme.brand
        case .transcription: AppTheme.info
        case .recording: AppTheme.brand
        case .intelligence: AppTheme.purple
        case .files: AppTheme.success
        case .privacy: AppTheme.success
        case .developer: AppTheme.purple
        case .about: AppTheme.brand
        }
    }
}

private struct MacSettingsNavigationRow: View {
    let destination: MacSettingsDestination
    let value: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(destination.tint)
                .frame(width: 30, height: 30)
                .background(
                    destination.tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(destination.title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(destination.subtitle)
                    .font(.redditSans(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !value.isEmpty {
                Text(verbatim: value)
                    .font(.redditSans(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 82, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? destination.tint : Color.secondary.opacity(0.7))
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? destination.tint.opacity(0.11) : AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? destination.tint.opacity(0.55) : AppTheme.cardBorder,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .shadow(
            color: isSelected ? destination.tint.opacity(0.07) : AppTheme.cardShadow,
            radius: isSelected ? 5 : AppTheme.cardShadowRadius,
            y: AppTheme.cardShadowYOffset
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
