import SwiftUI

struct SettingsView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    transcriptionSection
                    recordingSection
                    fileSection
                }
                .padding()
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await transcriber.refreshSupportedLanguages()
            await recordingStore.reload()
        }
    }

    private var transcriptionSection: some View {
        SettingsSection(title: "转录", systemImage: "captions.bubble", tint: AppTheme.info) {
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
                SettingsActionRow(
                    icon: "globe",
                    title: "转录语言",
                    value: transcriber.selectedLanguage.displayName,
                    tint: AppTheme.info
                )
            }
            .buttonStyle(.plain)
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            if transcriber.isRecording || transcriber.isPreparing {
                SettingsStatusRow(icon: "lock.fill", text: "录音中不能切换语言", tint: AppTheme.warning)
            }
        }
    }

    private var recordingSection: some View {
        SettingsSection(title: "录音", systemImage: "waveform.badge.mic", tint: AppTheme.brand) {
            HStack(spacing: 10) {
                SettingsIcon(systemImage: "waveform.badge.mic", tint: AppTheme.brand)

                Text("录音格式")
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)
            }

            Picker("录音格式", selection: $transcriber.selectedAudioFormat) {
                ForEach(RecordingAudioFormat.allCases) { format in
                    Text(format.title)
                        .tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(transcriber.isRecording || transcriber.isPreparing)
            .onChange(of: transcriber.selectedAudioFormat) { _, _ in
                HapticFeedback.play(.menuSelection)
            }

            SettingsStatusRow(
                icon: "info.circle",
                text: LocalizedStringKey(transcriber.selectedAudioFormat.detail),
                tint: AppTheme.brand
            )
        }
    }

    private var fileSection: some View {
        SettingsSection(title: "文件", systemImage: "folder", tint: AppTheme.success) {
            SettingsMetricRow(
                icon: "number",
                title: "录音数量",
                value: "\(recordingStore.recordings.count)",
                tint: AppTheme.success
            )

            SettingsMetricRow(
                icon: "icloud",
                title: "存储位置",
                value: recordingStore.storageDisplayName,
                tint: AppTheme.info
            )
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettingsIcon(systemImage: systemImage, tint: tint)

                Text(title)
                    .font(.redditSans(.headline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)
            }

            content
        }
        .settingsSurface()
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            Text(title)
                .font(.redditSans(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.redditSans(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 42)
        .contentShape(Rectangle())
    }
}

private struct SettingsMetricRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            Text(title)
                .font(.redditSans(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.redditSans(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsStatusRow: View {
    let icon: String
    let text: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
    }
}

private extension View {
    func settingsSurface() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 7, y: 2)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(
        transcriber: LiveTranscriptionManager(),
        recordingStore: RecordingStore()
    )
    .font(.redditSans(.body))
    .tint(AppTheme.brand)
}
#endif
