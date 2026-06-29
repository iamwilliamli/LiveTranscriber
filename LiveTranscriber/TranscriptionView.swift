import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore
    @State private var savedRecordingName: String?
    @State private var completionDrop: RecordingCompletionDrop?
    @State private var completionDropIsVisible = false
    @State private var completionDropIsFlying = false
    @State private var completionDropTask: Task<Void, Never>?

    private var isCompletingRecording: Bool {
        completionDrop != nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    recorderCard
                        .scaleEffect(completionDropIsVisible ? 0.96 : 1, anchor: .top)
                        .opacity(completionDropIsFlying ? 0.58 : 1)

                    transcriptCard
                        .opacity(completionDropIsFlying ? 0.45 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, transcriber.isRecording ? 126 : 112)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                floatingRecorderDock
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                completionDropOverlay
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: transcriber.isRecording)
            .animation(.snappy(duration: 0.2, extraBounce: 0.02), value: transcriber.isPaused)
            .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: completionDropIsVisible)
            .animation(.smooth(duration: 0.58), value: completionDropIsFlying)
        }
        .task {
            await transcriber.refreshSupportedLanguages()
        }
    }

    @ViewBuilder
    private var completionDropOverlay: some View {
        GeometryReader { proxy in
            if let completionDrop {
                let targetY = max(proxy.size.height - 176, 180)
                let expandedWidth = max(220, min(proxy.size.width - 48, 330))

                VStack {
                    RecordingCompletionDropCard(
                        drop: completionDrop,
                        isFlying: completionDropIsFlying
                    )
                    .frame(
                        maxWidth: completionDropIsFlying ? 76 : expandedWidth
                    )
                    .scaleEffect(completionDropIsFlying ? 0.62 : 1)
                    .opacity(completionDropIsVisible ? 1 : 0)
                    .offset(y: completionDropIsFlying ? targetY : 104)
                    .shadow(color: Color.black.opacity(completionDropIsFlying ? 0.12 : 0.18), radius: completionDropIsFlying ? 10 : 20, y: completionDropIsFlying ? 4 : 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .allowsHitTesting(false)
        .zIndex(10)
    }

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("实时转录", systemImage: "waveform.and.mic")
                        .font(.redditSans(.headline, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(transcriber.statusText)
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(transcriber.isRecording && !transcriber.isPaused ? AppTheme.danger : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                RecordingStateBadge(
                    isRecording: transcriber.isRecording,
                    isPaused: transcriber.isPaused,
                    isPreparing: transcriber.isPreparing
                )
            }

            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(formatDuration(transcriber.elapsedSeconds))
                    .font(.redditSans(size: 56, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(transcriber.selectedAudioFormat.badgeText)
                    .font(.redditSans(.caption2, weight: .bold))
                    .foregroundStyle(AppTheme.brand)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(AppTheme.brand.opacity(0.12), in: Capsule())
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                languageMenu

                StatusPill(
                    systemImage: "text.alignleft",
                    title: "\(transcriber.transcriptLines.count)",
                    tint: AppTheme.info
                )

                Spacer(minLength: 0)
            }

            if let savedRecordingName {
                Label(String(format: String(localized: "已保存: %@"), savedRecordingName), systemImage: "checkmark.circle.fill")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.success)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText = transcriber.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private var languageMenu: some View {
        Menu {
                ForEach(transcriber.supportedLanguages) { language in
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
        } label: {
            StatusPill(
                systemImage: "globe",
                title: transcriber.selectedLanguage.displayName,
                tint: AppTheme.info
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing)
    }

    @ViewBuilder
    private var floatingRecorderDock: some View {
        if transcriber.isRecording {
            HStack(spacing: 10) {
                FloatingControlButton(
                    title: transcriber.isPaused ? "继续" : "暂停",
                    systemImage: transcriber.isPaused ? "play.fill" : "pause.fill",
                    tint: .primary,
                    background: Color.secondary.opacity(0.14)
                ) {
                    togglePause()
                }

                FloatingControlButton(
                    title: "停止",
                    systemImage: "stop.fill",
                    tint: .white,
                    background: AppTheme.danger
                ) {
                    stopRecording()
                }
            }
            .padding(8)
            .floatingDockSurface()
        } else {
            Button {
                startRecording()
            } label: {
                HStack(spacing: 12) {
                    if transcriber.isPreparing {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else if isCompletingRecording {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 20, weight: .semibold))
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }

                    Text(isCompletingRecording ? LocalizedStringKey("保存录音") : LocalizedStringKey("开始录音"))
                        .font(.redditSans(.subheadline, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(AppTheme.danger, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: AppTheme.danger.opacity(0.24), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(transcriber.isPreparing || isCompletingRecording)
        }
    }

    private func startRecording() {
        guard !isCompletingRecording else {
            return
        }
        HapticFeedback.play(.recordingStart)
        savedRecordingName = nil
        Task {
            await transcriber.startRecording()
        }
    }

    private func togglePause() {
        HapticFeedback.play(transcriber.isPaused ? .recordingResume : .recordingPause)
        Task {
            if transcriber.isPaused {
                await transcriber.resumeRecording()
            } else {
                await transcriber.pauseRecording()
            }
        }
    }

    private func stopRecording() {
        HapticFeedback.play(.recordingStop)
        Task {
            if let draft = await transcriber.stopRecording(),
               let saved = await recordingStore.save(draft) {
                savedRecordingName = saved.audioFileName
                HapticFeedback.play(.recordingSaved)
                beginCompletionDrop(for: saved)
            } else {
                HapticFeedback.play(.warning)
            }
        }
    }

    private func beginCompletionDrop(for item: RecordingItem) {
        completionDropTask?.cancel()
        completionDrop = RecordingCompletionDrop(
            fileName: item.audioFileName,
            durationText: formatDuration(item.durationSeconds),
            lineCount: item.lineCount
        )
        completionDropIsVisible = false
        completionDropIsFlying = false

        withAnimation(.snappy(duration: 0.2, extraBounce: 0.04)) {
            completionDropIsVisible = true
        }

        completionDropTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.smooth(duration: 0.72)) {
                completionDropIsFlying = true
            }

            try? await Task.sleep(for: .milliseconds(720))
            guard !Task.isCancelled else {
                return
            }

            transcriber.clearTranscript()
            savedRecordingName = nil

            withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                completionDropIsVisible = false
            }

            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                return
            }

            completionDrop = nil
            completionDropIsFlying = false
            completionDropTask = nil
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("转录文本", systemImage: "text.alignleft")
                    .font(.redditSans(.headline))
                Spacer()
                Text("\(transcriber.transcriptLines.count)")
                    .font(.redditSans(.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !transcriber.transcriptLines.isEmpty {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            Color.clear
                                .frame(height: 1)
                                .id("transcript-top")

                            ForEach(transcriber.transcriptLines.reversed()) { line in
                                TranscriptionLineRow(line: line)
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: transcriber.transcriptLines.count) { _, _ in
                            withAnimation(.snappy(duration: 0.2)) {
                                scrollProxy.scrollTo("transcript-top", anchor: .top)
                            }
                        }
                }
            } else {
                EmptyStateView(icon: "quote.bubble", title: "暂无文本")
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
        .cardSurface()
    }

    private func formatDuration(_ seconds: Int) -> String {
        TranscriptionLine.formatTimestamp(Double(seconds))
    }
}

private struct RecordingCompletionDrop: Identifiable {
    let id = UUID()
    let fileName: String
    let durationText: String
    let lineCount: Int
}

private struct RecordingCompletionDropCard: View {
    let drop: RecordingCompletionDrop
    let isFlying: Bool

    var body: some View {
        HStack(spacing: isFlying ? 0 : 12) {
            ZStack {
                RoundedRectangle(cornerRadius: isFlying ? 18 : AppTheme.compactCornerRadius, style: .continuous)
                    .fill(AppTheme.success.opacity(0.14))

                Image(systemName: "waveform.badge.checkmark")
                    .font(.system(size: isFlying ? 20 : 22, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
            }
            .frame(width: isFlying ? 42 : 48, height: isFlying ? 42 : 48)

            if !isFlying {
                VStack(alignment: .leading, spacing: 5) {
                    Text("已保存到录音文件")
                        .font(.redditSans(.caption2, weight: .bold))
                        .foregroundStyle(AppTheme.success)
                        .lineLimit(1)

                    Text(drop.fileName)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Label(drop.durationText, systemImage: "clock")
                        Label("\(drop.lineCount)", systemImage: "text.alignleft")
                    }
                    .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))

                Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, isFlying ? 6 : 12)
        .frame(height: isFlying ? 54 : 76)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: isFlying ? 28 : AppTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isFlying ? 28 : AppTheme.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct TranscriptionLineRow: View {
    let line: TranscriptionLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.timestampText)
                .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                .foregroundStyle(line.isFinal ? AppTheme.brand : AppTheme.warning)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background((line.isFinal ? AppTheme.brand : AppTheme.warning).opacity(0.12), in: Capsule())

            Text(line.text)
                .font(.redditSans(.body))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private struct RecordingStateBadge: View {
    let isRecording: Bool
    let isPaused: Bool
    let isPreparing: Bool

    private var title: LocalizedStringKey {
        if isPreparing {
            return "正在请求权限"
        }
        if isRecording {
            return isPaused ? "已暂停" : "正在录音"
        }
        return "准备就绪"
    }

    private var tint: Color {
        if isRecording && !isPaused {
            return AppTheme.danger
        }
        if isPreparing {
            return AppTheme.warning
        }
        return AppTheme.success
    }

    var body: some View {
        Label(title, systemImage: isRecording && !isPaused ? "record.circle" : "checkmark.circle")
            .font(.redditSans(.caption2, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct StatusPill: View {
    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.redditSans(.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(tint.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct FloatingControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.redditSans(.subheadline, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func cardSurface() -> some View {
        background(AppTheme.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 7, y: 2)
    }

    func floatingDockSurface() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
    }
}

#if DEBUG
#Preview("Transcription") {
    TranscriptionView(
        transcriber: LiveTranscriptionManager(),
        recordingStore: RecordingStore()
    )
    .font(.redditSans(.body))
    .tint(AppTheme.brand)
}
#endif
