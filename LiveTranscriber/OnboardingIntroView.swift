import SwiftUI

enum OnboardingState {
    static let completedDefaultsKey = "onboarding.introduction.completed.v1"
}

struct OnboardingIntroView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    let onComplete: () -> Void

    @State private var selectedPage: Int? = 0
    @State private var isHeroAnimated = false
    @State private var mossLocalModelStatus = MOSSLocalModelManager.currentStatus()
    @State private var isDownloadingMOSSLocalModel = false
    @State private var mossLocalDownloadProgress: Double = 0
    @State private var mossLocalDownloadErrorMessage: String?
    @State private var selectedLocalSummaryModel = LocalSummaryModelManager.selectedModel
    @State private var localSummaryModelStatus = LocalSummaryModelManager.currentStatus()
    @State private var isDownloadingLocalSummaryModel = false
    @State private var localSummaryDownloadProgress: Double = 0
    @State private var localSummaryDownloadErrorMessage: String?

    private let contentMargin: CGFloat = 20

    private let featurePages: [OnboardingFeaturePage] = [
        OnboardingFeaturePage(
            icon: "waveform.and.mic",
            titleResource: L10n.Onboarding.liveTitle,
            detailResource: L10n.Onboarding.liveDetail,
            tint: AppTheme.brand
        ),
        OnboardingFeaturePage(
            icon: "folder.badge.gearshape",
            titleResource: L10n.Onboarding.recordingsTitle,
            detailResource: L10n.Onboarding.recordingsDetail,
            tint: AppTheme.info
        ),
        OnboardingFeaturePage(
            icon: "lock.shield",
            titleResource: L10n.Onboarding.privacyTitle,
            detailResource: L10n.Onboarding.privacyDetail,
            tint: AppTheme.success
        )
    ]

    var body: some View {
        ZStack {
            OnboardingAnimatedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    hero
                        .padding(.top, 24)

                    featureCarousel

                    quickSetup

                    privacyNote
                        .padding(.bottom, 116)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, contentMargin)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            bottomActions
        }
        .task {
            await transcriber.refreshSupportedLanguages()
            refreshMOSSLocalModelStatus()
            refreshLocalSummaryModelStatus()
            withAnimation(.smooth(duration: 0.7)) {
                isHeroAnimated = true
            }
        }
        .alert(
            String(localized: L10n.MOSSLocal.downloadFailed),
            isPresented: Binding(
                get: { mossLocalDownloadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        mossLocalDownloadErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(mossLocalDownloadErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.LocalSummary.downloadFailed),
            isPresented: Binding(
                get: { localSummaryDownloadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        localSummaryDownloadErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(localSummaryDownloadErrorMessage ?? "")
        }
    }

    private var hero: some View {
        let heroBrightness = isHeroAnimated ? 0.03 : -0.02

        return VStack(spacing: 18) {
            OnboardingSplashHero(isAnimated: isHeroAnimated)
                .frame(height: 360)
                .visualEffect { content, geometry in
                    content
                        .scaleEffect(min(max(max(geometry.size.height, 1) / 360, 0.96), 1.04))
                        .brightness(heroBrightness)
                }

            VStack(spacing: 8) {
                Text(L10n.Onboarding.title)
                    .font(.redditSans(.largeTitle, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(L10n.Onboarding.caption)
                    .font(.redditSans(.body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var featureCarousel: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: contentMargin) {
                        ForEach(Array(featurePages.enumerated()), id: \.offset) { index, page in
                            OnboardingFeatureCard(page: page)
                                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                .scrollPosition(id: $selectedPage)
            }
            .frame(height: 224)

            HStack(spacing: 6) {
                ForEach(featurePages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == (selectedPage ?? 0) ? AppTheme.brand : Color.secondary.opacity(0.28))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var quickSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(L10n.Onboarding.setupTitle)
                    .font(.redditSans(.headline, weight: .semibold))
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(AppTheme.brand)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                OnboardingSettingMenuRow(
                    icon: "globe",
                    titleResource: L10n.Onboarding.languageTitle,
                    value: transcriber.selectedLanguage.displayName,
                    tint: AppTheme.info
                ) {
                    ForEach(onboardingLanguages) { language in
                        Button {
                            HapticFeedback.play(.menuSelection)
                            transcriber.selectedLanguageID = language.id
                        } label: {
                            Label(
                                language.displayName,
                                systemImage: language.id == transcriber.selectedLanguageID ? "checkmark" : "globe"
                            )
                        }
                    }
                }

                quickSetupDivider

                audioFormatSetup

                quickSetupDivider

                mossDownloadSetup

                quickSetupDivider

                localSummaryDownloadSetup
            }
            .background(
                AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var privacyNote: some View {
        Label {
            Text(L10n.Onboarding.footer)
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "iphone.and.arrow.forward")
                .foregroundStyle(AppTheme.success)
        }
        .padding(.horizontal, 6)
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Button {
                HapticFeedback.play(.primaryAction)
                onComplete()
            } label: {
                Label(String(localized: L10n.Onboarding.cta), systemImage: "waveform.and.mic")
                    .font(.redditSans(.headline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                HapticFeedback.play(.menuSelection)
                onComplete()
            } label: {
                Text(L10n.Onboarding.useDefaults)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, contentMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private var onboardingLanguages: [TranscriptionLanguage] {
        transcriber.supportedLanguages.isEmpty ? TranscriptionLanguage.fallbackOptions : transcriber.supportedLanguages
    }

    private var audioFormatBinding: Binding<RecordingAudioFormat> {
        Binding {
            transcriber.selectedAudioFormat
        } set: { newValue in
            HapticFeedback.play(.menuSelection)
            transcriber.selectedAudioFormat = newValue
        }
    }

    private var audioFormatSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 28, height: 28)

                Text(L10n.Onboarding.formatTitle)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Picker("", selection: audioFormatBinding) {
                ForEach(RecordingAudioFormat.allCases) { format in
                    Text(format.title)
                        .tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.leading, 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var quickSetupDivider: some View {
        Divider()
            .padding(.leading, 54)
    }

    private var mossDownloadSetup: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingRecommendedSettingRow(
                icon: "person.2",
                titleResource: L10n.Onboarding.mossModelTitle,
                value: String(localized: L10n.MOSSLocal.modelName),
                badgeResource: L10n.Onboarding.recommended,
                tint: AppTheme.purple
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: mossLocalModelStatus.isAvailable ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(mossLocalModelStatus.isAvailable ? AppTheme.success : AppTheme.info)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(mossLocalStatusValue)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(mossLocalModelStatus.detailText)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                if isDownloadingMOSSLocalModel {
                    ProgressView(value: mossLocalDownloadProgress)
                        .tint(AppTheme.purple)
                }

                if !mossLocalModelStatus.isAvailable {
                    Button {
                        downloadMOSSLocalModel()
                    } label: {
                        Label(mossLocalDownloadButtonTitle, systemImage: "arrow.down.circle.fill")
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                    .disabled(isDownloadingMOSSLocalModel)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var mossLocalStatusValue: String {
        if isDownloadingMOSSLocalModel {
            return String(
                format: String(localized: L10n.MOSSLocal.downloadingModelFormat),
                mossLocalDownloadProgress * 100
            )
        }
        return mossLocalModelStatus.statusText
    }

    private var mossLocalDownloadButtonTitle: String {
        String(
            format: String(localized: L10n.Onboarding.downloadMOSSFormat),
            MOSSLocalModelManager.expectedSizeText
        )
    }

    private var localSummaryDownloadSetup: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingSettingMenuRow(
                icon: "brain.head.profile",
                titleResource: L10n.LocalSummary.modelTitle,
                value: selectedLocalSummaryModel.displayName,
                tint: AppTheme.purple
            ) {
                ForEach(LocalSummaryModelManager.availableModels) { model in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        LocalSummaryModelManager.selectModel(model)
                        selectedLocalSummaryModel = model
                        localSummaryModelStatus = LocalSummaryModelManager.status(for: model)
                    } label: {
                        Label(
                            model.displayName,
                            systemImage: model.id == selectedLocalSummaryModel.id ? "checkmark" : "brain.head.profile"
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: localSummaryModelStatus.isAvailable ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(localSummaryModelStatus.isAvailable ? AppTheme.success : AppTheme.info)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(localSummaryStatusValue)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(localSummaryModelStatus.detailText)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }

                if isDownloadingLocalSummaryModel {
                    ProgressView(value: localSummaryDownloadProgress)
                        .tint(AppTheme.purple)
                }

                if !localSummaryModelStatus.isAvailable {
                    Button {
                        downloadLocalSummaryModel()
                    } label: {
                        Label(String(localized: L10n.LocalSummary.downloadSelectedModel), systemImage: "arrow.down.circle.fill")
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                    .disabled(isDownloadingLocalSummaryModel)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var localSummaryStatusValue: String {
        if isDownloadingLocalSummaryModel {
            return String(
                format: String(localized: L10n.LocalSummary.downloadingModelFormat),
                localSummaryDownloadProgress * 100
            )
        }
        return localSummaryModelStatus.statusText
    }

    private func refreshMOSSLocalModelStatus() {
        mossLocalModelStatus = MOSSLocalModelManager.currentStatus()
    }

    private func refreshLocalSummaryModelStatus() {
        selectedLocalSummaryModel = LocalSummaryModelManager.selectedModel
        localSummaryModelStatus = LocalSummaryModelManager.currentStatus()
    }

    private func downloadMOSSLocalModel() {
        guard !isDownloadingMOSSLocalModel else {
            return
        }

        isDownloadingMOSSLocalModel = true
        mossLocalDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await MOSSLocalModelManager.download { progress in
                    Task { @MainActor in
                        mossLocalDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    mossLocalModelStatus = status
                    isDownloadingMOSSLocalModel = false
                    mossLocalDownloadProgress = 1
                    HapticFeedback.play(.menuSelection)
                }
            } catch {
                await MainActor.run {
                    mossLocalModelStatus = MOSSLocalModelManager.currentStatus()
                    isDownloadingMOSSLocalModel = false
                    mossLocalDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func downloadLocalSummaryModel() {
        guard !isDownloadingLocalSummaryModel else {
            return
        }

        isDownloadingLocalSummaryModel = true
        localSummaryDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        let model = selectedLocalSummaryModel
        Task {
            do {
                let status = try await LocalSummaryModelManager.download(model: model) { progress in
                    Task { @MainActor in
                        localSummaryDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    selectedLocalSummaryModel = status.model
                    localSummaryModelStatus = status
                    isDownloadingLocalSummaryModel = false
                    localSummaryDownloadProgress = 1
                    HapticFeedback.play(.menuSelection)
                }
            } catch {
                await MainActor.run {
                    isDownloadingLocalSummaryModel = false
                    localSummaryDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

}

private struct OnboardingFeaturePage {
    let icon: String
    let titleResource: LocalizedStringResource
    let detailResource: LocalizedStringResource
    let tint: Color
}

private struct OnboardingAnimatedBackground: View {
    var body: some View {
        Color(.systemGroupedBackground)
    }
}

private struct OnboardingSplashHero: View {
    let isAnimated: Bool

    private let cards: [OnboardingSplashCardModel] = [
        OnboardingSplashCardModel(
            icon: "waveform.and.mic",
            titleResource: L10n.Onboarding.carouselCaptureTitle,
            detailResource: L10n.Onboarding.carouselCaptureDetail,
            tint: AppTheme.brand
        ),
        OnboardingSplashCardModel(
            icon: "folder.badge.gearshape",
            titleResource: L10n.Onboarding.carouselLibraryTitle,
            detailResource: L10n.Onboarding.carouselLibraryDetail,
            tint: AppTheme.info
        ),
        OnboardingSplashCardModel(
            icon: "person.2",
            titleResource: L10n.Onboarding.carouselMOSSTitle,
            detailResource: L10n.Onboarding.carouselMOSSDetail,
            tint: AppTheme.purple
        ),
        OnboardingSplashCardModel(
            icon: "lock.shield",
            titleResource: L10n.Onboarding.carouselPrivateTitle,
            detailResource: L10n.Onboarding.carouselPrivateDetail,
            tint: AppTheme.success
        )
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(Color.black)
                .overlay {
                    LinearGradient(
                        colors: [
                            AppTheme.brand.opacity(0.50),
                            AppTheme.info.opacity(0.30),
                            AppTheme.purple.opacity(0.45),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.82)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.28), radius: 28, y: 14)

            VStack(spacing: 0) {
                GeometryReader { geometry in
                    TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let itemWidth = min(max(geometry.size.width * 0.54, 154), 214)
                        let offset = CGFloat(time.truncatingRemainder(dividingBy: 8) / 8) * itemWidth
                        let centerX = geometry.size.width / 2
                        let centerY = geometry.size.height / 2

                        ZStack {
                            ForEach(-3...6, id: \.self) { virtualIndex in
                                let cardIndex = positiveModulo(virtualIndex, cards.count)
                                let card = cards[cardIndex]
                                let x = CGFloat(virtualIndex) * itemWidth - offset
                                let phase = x / max(geometry.size.width, 1)
                                let distance = abs(phase)

                                OnboardingSplashCard(card: card)
                                    .frame(width: itemWidth - 18, height: 210)
                                    .scaleEffect(1 - min(distance * 0.16, 0.18))
                                    .rotationEffect(.degrees(Double(phase) * 7))
                                    .opacity(1 - min(Double(distance) * 0.62, 0.62))
                                    .position(x: centerX + x, y: centerY)
                                    .zIndex(1 - Double(distance))
                            }
                        }
                        .drawingGroup()
                    }
                }
                .frame(height: 244)

                VStack(spacing: 10) {
                    Text(L10n.Onboarding.heroSplashTitle)
                        .font(.redditSans(.title2, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .opacity(isAnimated ? 1 : 0)
                        .offset(y: isAnimated ? 0 : 10)

                    Text(L10n.Onboarding.heroSplashCaption)
                        .font(.redditSans(.subheadline))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 22)
                        .opacity(isAnimated ? 1 : 0)
                        .offset(y: isAnimated ? 0 : 14)
                }
                .padding(.bottom, 18)

                HStack(spacing: 8) {
                    OnboardingTranscriptChip(textResource: L10n.Onboarding.heroChipLive, icon: "dot.radiowaves.left.and.right", tint: AppTheme.brand)
                    OnboardingTranscriptChip(textResource: L10n.Onboarding.heroChipMOSS, icon: "person.2", tint: AppTheme.purple)
                    OnboardingTranscriptChip(textResource: L10n.Onboarding.heroChipPrivate, icon: "lock.fill", tint: AppTheme.success)
                }
                .padding(.bottom, 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .animation(.smooth(duration: 0.8), value: isAnimated)
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        (value % divisor + divisor) % divisor
    }
}

private struct OnboardingSplashCardModel {
    let icon: String
    let titleResource: LocalizedStringResource
    let detailResource: LocalizedStringResource
    let tint: Color
}

private struct OnboardingSplashCard: View {
    let card: OnboardingSplashCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    .fill(card.tint.opacity(0.24))
                Image(systemName: card.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 62, height: 62)

            Spacer(minLength: 0)

            OnboardingStaticWaveformBars(tint: card.tint)
                .frame(height: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(card.titleResource)
                    .font(.redditSans(.headline, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(card.detailResource)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: card.tint.opacity(0.35), radius: 16, y: 8)
    }
}

private struct OnboardingStaticWaveformBars: View {
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<24, id: \.self) { index in
                let phase = Double(index) * 0.54
                let sineLift = (sin(phase) + 1) * 13
                let cosineLift = (cos(phase * 0.7) + 1) * 4
                let height = CGFloat(8 + sineLift + cosineLift)

                Capsule()
                    .fill(index.isMultiple(of: 4) ? tint : Color.white.opacity(0.62))
                    .frame(width: 4, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingTranscriptChip: View {
    let textResource: LocalizedStringResource
    let icon: String
    let tint: Color

    var body: some View {
        Label {
            Text(textResource)
                .font(.redditSans(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct OnboardingFeatureCard: View {
    let page: OnboardingFeaturePage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    .fill(page.tint.opacity(0.14))
                Image(systemName: page.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(page.tint)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(page.titleResource)
                    .font(.redditSans(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.detailResource)
                    .font(.redditSans(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

private struct OnboardingRecommendedSettingRow: View {
    let icon: String
    let titleResource: LocalizedStringResource
    let value: String
    let badgeResource: LocalizedStringResource
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(titleResource)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(badgeResource)
                        .font(.redditSans(.caption2, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(tint.opacity(0.12), in: Capsule())
                }

                Text(value)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct OnboardingSettingMenuRow<Content: View>: View {
    let icon: String
    let titleResource: LocalizedStringResource
    let value: String
    let tint: Color
    let content: () -> Content

    init(
        icon: String,
        titleResource: LocalizedStringResource,
        value: String,
        tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.titleResource = titleResource
        self.value = value
        self.tint = tint
        self.content = content
    }

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleResource)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(value)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Onboarding") {
    OnboardingIntroView(transcriber: LiveTranscriptionManager()) {}
}
#endif
