import SwiftUI
import UIKit

private enum SettingsRoute: Hashable {
    case transcription
    case transcriptionLanguage
    case recording
    case recordingFormat
    case files
    case privacy
    case developer
    case speechPipelineMode
}

struct SettingsView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink(value: SettingsRoute.transcription) {
                        SettingsNavigationRow(
                            icon: "captions.bubble",
                            title: "转录",
                            value: transcriber.selectedLanguage.displayName,
                            subtitle: "语言和转录模型",
                            tint: AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.recording) {
                        SettingsNavigationRow(
                            icon: "waveform.badge.mic",
                            title: "录音",
                            value: transcriber.selectedAudioFormat.title,
                            subtitle: "音频格式和录音行为",
                            tint: AppTheme.brand
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.files) {
                        SettingsNavigationRow(
                            icon: "folder",
                            title: "文件",
                            value: recordingStore.storageDisplayName,
                            subtitle: "保存位置和录音数量",
                            tint: AppTheme.success
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.privacy) {
                        SettingsNavigationRow(
                            icon: "lock.shield",
                            title: "隐私",
                            value: String(localized: "本地处理"),
                            subtitle: "数据边界和权限用途",
                            tint: AppTheme.success
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.developer) {
                        SettingsNavigationRow(
                            icon: "wrench.and.screwdriver",
                            title: "开发者选项",
                            value: transcriber.speechPipelineDiagnostics.activePipelineName,
                            subtitle: "设备和 Pipeline 诊断",
                            tint: AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()
                }
                .padding()
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
        }
        .task {
            await transcriber.refreshSupportedLanguages()
            await recordingStore.reload()
            recordingStore.refreshIntelligenceAvailability()
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .transcription:
            transcriptionSettingsPage
        case .transcriptionLanguage:
            transcriptionLanguagePage
        case .recording:
            recordingSettingsPage
        case .recordingFormat:
            recordingFormatPage
        case .files:
            fileSettingsPage
        case .privacy:
            privacySettingsPage
        case .developer:
            developerSettingsPage
        case .speechPipelineMode:
            speechPipelineModePage
        }
    }

    private var transcriptionSettingsPage: some View {
        SettingsDetailPage(title: "转录") {
            SettingsSection(title: "转录", systemImage: "captions.bubble", tint: AppTheme.info) {
                NavigationLink(value: SettingsRoute.transcriptionLanguage) {
                    SettingsNavigationRow(
                        icon: "globe",
                        title: "转录语言",
                        value: transcriber.selectedLanguage.displayName,
                        subtitle: "下次开始录音时使用所选语言",
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
    }

    private var transcriptionLanguagePage: some View {
        SettingsDetailPage(title: "转录语言") {
            SettingsSection(title: "转录语言", systemImage: "globe", tint: AppTheme.info) {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        transcriber.selectedLanguageID = language.id
                    } label: {
                        SettingsSelectionRow(
                            icon: "globe",
                            title: language.displayName,
                            subtitle: language.id,
                            isSelected: language.id == transcriber.selectedLanguageID,
                            tint: AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(transcriber.isRecording || transcriber.isPreparing)
                }
            }
        }
    }

    private var recordingSettingsPage: some View {
        SettingsDetailPage(title: "录音") {
            SettingsSection(title: "录音", systemImage: "waveform.badge.mic", tint: AppTheme.brand) {
                NavigationLink(value: SettingsRoute.recordingFormat) {
                    SettingsNavigationRow(
                        icon: "waveform.badge.mic",
                        title: "录音格式",
                        value: transcriber.selectedAudioFormat.title,
                        subtitle: LocalizedStringKey(transcriber.selectedAudioFormat.detail),
                        tint: AppTheme.brand
                    )
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                if transcriber.isRecording || transcriber.isPreparing {
                    SettingsStatusRow(icon: "lock.fill", text: "录音中不能切换格式", tint: AppTheme.warning)
                }
            }
        }
    }

    private var recordingFormatPage: some View {
        SettingsDetailPage(title: "录音格式") {
            SettingsSection(title: "录音格式", systemImage: "waveform.badge.mic", tint: AppTheme.brand) {
                ForEach(RecordingAudioFormat.allCases) { format in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        transcriber.selectedAudioFormat = format
                    } label: {
                        SettingsSelectionRow(
                            icon: format == .wav ? "waveform" : "waveform.badge.plus",
                            title: format.title,
                            subtitle: format.detail,
                            isSelected: format == transcriber.selectedAudioFormat,
                            tint: AppTheme.brand
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(transcriber.isRecording || transcriber.isPreparing)
                }
            }
        }
    }

    private var fileSettingsPage: some View {
        SettingsDetailPage(title: "文件") {
            fileSection
        }
    }

    private var developerSettingsPage: some View {
        SettingsDetailPage(title: "开发者选项") {
            developerSection
        }
    }

    private var privacySettingsPage: some View {
        SettingsDetailPage(title: "隐私") {
            SettingsSection(title: "本地处理", systemImage: "lock.shield", tint: AppTheme.success) {
                SettingsStatusRow(
                    icon: "server.rack",
                    text: "不使用开发者服务器、第三方分析、广告、追踪或自定义网络请求。",
                    tint: AppTheme.success
                )

                SettingsStatusRow(
                    icon: "waveform.badge.mic",
                    text: "录音、转录文本、摘要和标签使用 Apple 系统框架在设备上处理。",
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "person.crop.circle.badge.xmark",
                    text: "音频和转录不会上传到开发者服务器，开发者无法访问用户内容。",
                    tint: AppTheme.success
                )
            }

            SettingsSection(title: "存储", systemImage: "internaldrive", tint: AppTheme.info) {
                SettingsMetricRow(
                    icon: "folder",
                    title: "当前位置",
                    value: recordingStore.storageDisplayName,
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "icloud",
                    text: "录音文件保存在 app 私有存储；启用 iCloud 时同步到 app 私有 iCloud container 的 Data 目录，不暴露到 iCloud Drive 文件夹。",
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "list.bullet.rectangle",
                    text: "录音索引用 SwiftData 存储，并通过 CloudKit private database 同步到用户自己的 iCloud。",
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "trash",
                    text: "删除录音会删除 app 管理的音频文件和转录文本。",
                    tint: AppTheme.danger
                )
            }

            SettingsSection(title: "权限用途", systemImage: "checkmark.shield", tint: AppTheme.brand) {
                SettingsStatusRow(
                    icon: "mic",
                    text: "麦克风权限只用于录音和实时转录。",
                    tint: AppTheme.brand
                )

                SettingsStatusRow(
                    icon: "captions.bubble",
                    text: "语音识别权限只用于把用户选择的录音转成文本。",
                    tint: AppTheme.brand
                )

                SettingsStatusRow(
                    icon: "location",
                    text: "位置权限只在保存录音时选择添加地理位置时使用。",
                    tint: AppTheme.brand
                )

                SettingsStatusRow(
                    icon: "camera",
                    text: "相机不用于拍照或录像；相机权限说明仅用于满足 Apple capture framework 的审核要求。",
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "waveform.circle",
                    text: "后台音频只用于录音或播放继续进行，不用于其他后台任务。",
                    tint: AppTheme.warning
                )
            }
        }
    }

    private var speechPipelineModePage: some View {
        SettingsDetailPage(title: "语音 Pipeline 模式") {
            SettingsSection(title: "语音 Pipeline 模式", systemImage: "waveform.path.ecg", tint: AppTheme.brand) {
                ForEach(SpeechPipelineMode.allCases) { mode in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        transcriber.selectedSpeechPipelineMode = mode
                    } label: {
                        SettingsSelectionRow(
                            icon: mode == .nativeIOS27 ? "sparkles" : "checkmark.shield",
                            title: mode.title,
                            subtitle: mode.detail,
                            isSelected: mode == transcriber.selectedSpeechPipelineMode,
                            tint: mode.isSupportedOnCurrentOS ? AppTheme.brand : AppTheme.warning
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!mode.isSupportedOnCurrentOS || transcriber.isRecording || transcriber.isPreparing)
                }

                if transcriber.isRecording || transcriber.isPreparing {
                    SettingsStatusRow(icon: "lock.fill", text: "录音中不能切换 Pipeline", tint: AppTheme.warning)
                }
            }
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

    private var developerSection: some View {
        let availability = recordingStore.intelligenceAvailability
        let tint = availability.isAvailable ? AppTheme.success : AppTheme.warning
        let device = DeveloperDeviceInfo.current
        let pipeline = transcriber.speechPipelineDiagnostics

        return SettingsSection(title: "开发者选项", systemImage: "wrench.and.screwdriver", tint: AppTheme.purple) {
            SettingsMetricRow(
                icon: "iphone",
                title: "设备",
                value: device.modelIdentifier,
                tint: AppTheme.info
            )

            SettingsMetricRow(
                icon: "gearshape",
                title: "系统版本",
                value: device.systemVersion,
                tint: AppTheme.info
            )

            SettingsMetricRow(
                icon: "waveform.path.ecg",
                title: "当前语音 Pipeline",
                value: pipeline.activePipelineName,
                tint: AppTheme.brand
            )

            NavigationLink(value: SettingsRoute.speechPipelineMode) {
                SettingsNavigationRow(
                    icon: "slider.horizontal.3",
                    title: "语音 Pipeline 模式",
                    value: pipeline.configuredPipelineName,
                    subtitle: "切换兼容模式或 iOS 27 Native 模式",
                    tint: AppTheme.brand
                )
            }
            .buttonStyle(.plain)
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            SettingsStatusRow(
                icon: "slider.horizontal.3",
                text: LocalizedStringKey(pipeline.supportedPipelinesText),
                tint: AppTheme.brand
            )

            SettingsStatusRow(
                icon: "waveform",
                text: LocalizedStringKey(pipeline.analyzerFormatText),
                tint: AppTheme.info
            )

            SettingsStatusRow(
                icon: "waveform.path",
                text: LocalizedStringKey(pipeline.runtimeAnalyzerFormatText),
                tint: AppTheme.info
            )

            Toggle(isOn: $transcriber.isLoudnessProcessingEnabled) {
                HStack(alignment: .top, spacing: 10) {
                    SettingsIcon(systemImage: "waveform.badge.plus", tint: AppTheme.warning)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("响度处理")
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("开启后会在录音结束、导入和详情页补处理时做文件级响度归一化；关闭时保留 Stereo Capture 原始音量")
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.switch)
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            SettingsMetricRow(
                icon: "sparkles",
                title: "高端模型",
                value: availability.statusText,
                tint: tint
            )

            SettingsStatusRow(
                icon: availability.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                text: LocalizedStringKey(availability.detailText),
                tint: tint
            )
        }
    }
}

private struct DeveloperDeviceInfo {
    var modelIdentifier: String
    var systemVersion: String

    static var current: DeveloperDeviceInfo {
        DeveloperDeviceInfo(
            modelIdentifier: machineIdentifier(),
            systemVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        )
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { reboundPointer in
                String(cString: reboundPointer)
            }
        }
    }
}

private struct SettingsDetailPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding()
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    let subtitle: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.redditSans(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsSelectionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
