import SwiftUI
import TranscriberDomain

/// Edit-details sheet mirroring the iOS RecordingEditSheet: name with AI
/// suggestion, language, category, tags, key points, and summary.
struct MacRecordingEditSheet: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationProvider: MacRecordingLocationProvider
    @State private var name: String
    @State private var categoryName: String?
    @State private var newCategoryName = ""
    @State private var tagsText: String
    @State private var keyPoints: String
    @State private var summary: String
    @State private var languageID: String
    @State private var includesLocation: Bool
    @State private var isGeneratingTitle = false

    init(item: RecordingItem, store: RecordingStore, onError: @escaping (String) -> Void) {
        self.item = item
        self.store = store
        self.onError = onError
        _locationProvider = StateObject(
            wrappedValue: MacRecordingLocationProvider(recordingLocation: item.location)
        )
        _name = State(initialValue: item.displayName)
        _categoryName = State(initialValue: item.categoryName)
        _tagsText = State(initialValue: (item.manualTags ?? []).joined(separator: ", "))
        _keyPoints = State(initialValue: item.keyPoints ?? "")
        _summary = State(initialValue: item.intelligence?.summary ?? "")
        _languageID = State(initialValue: item.languageID)
        _includesLocation = State(initialValue: item.location != nil)
    }

    private var categories: [String] {
        RecordingCategoryCatalog.allNames(recordings: store.recordings)
    }

    private var languageOptions: [TranscriptionLanguage] {
        TranscriptionLanguage.baseLanguageOptions(
            from: TranscriptionLanguage.fallbackOptions,
            including: item.languageID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 40, height: 40)
                    .background(
                        AppTheme.brand.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.Recordings.editDetails)
                        .font(.title2.bold())

                    Text(verbatim: item.displayName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EditorSheetSection(
                        title: String(localized: L10n.Recordings.recordingName),
                        systemImage: "captions.bubble.fill",
                        tint: AppTheme.brand
                    ) {
                        HStack(spacing: 8) {
                            TextField(text: $name) {
                                Text(L10n.Recordings.recordingName)
                            }
                            .font(.headline)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 46)
                            .editorSheetInputSurface(tint: AppTheme.brand)

                            if store.intelligenceAvailability.isAvailable {
                                Button {
                                    generateTitle()
                                } label: {
                                    if isGeneratingTitle {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isGeneratingTitle)
                                .help(String(localized: L10n.Recordings.generateTagsAndSummary))
                            }
                        }
                    }

                    EditorSheetSection(
                        title: String(localized: L10n.Recordings.categoryName),
                        systemImage: "folder.fill",
                        tint: AppTheme.info
                    ) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(L10n.Settings.transcriptionLanguage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Picker(selection: $languageID) {
                                    ForEach(languageOptions) { language in
                                        Text(verbatim: language.displayName)
                                            .tag(language.id)
                                    }
                                    if !languageOptions.contains(where: { $0.id == languageID }) {
                                        Text(verbatim: TranscriptionLanguage(id: languageID).displayName)
                                            .tag(languageID)
                                    }
                                } label: {
                                    EmptyView()
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 7) {
                                Text(L10n.Recordings.categoryName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Picker(selection: $categoryName) {
                                    Text(L10n.Recordings.uncategorized)
                                        .tag(String?.none)
                                    ForEach(categories, id: \.self) { category in
                                        Text(verbatim: category)
                                            .tag(String?.some(category))
                                    }
                                } label: {
                                    EmptyView()
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text(L10n.Recordings.newCategory)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField(text: $newCategoryName) {
                                Text(L10n.Recordings.categoryNamePlaceholder)
                            }
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .editorSheetInputSurface()
                        }
                    }

                    EditorSheetSection(
                        title: String(localized: L10n.Recordings.keyPoints),
                        systemImage: "list.bullet.clipboard.fill",
                        tint: AppTheme.purple
                    ) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(L10n.Recordings.tags)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField(text: $tagsText) {
                                Text(L10n.Recordings.tags)
                            }
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .editorSheetInputSurface()
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text(L10n.Recordings.keyPoints)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $keyPoints)
                                .font(.body)
                                .lineSpacing(3)
                                .frame(minHeight: 92)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .editorSheetInputSurface()
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text(L10n.Recordings.intelligenceSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $summary)
                                .font(.body)
                                .lineSpacing(3)
                                .frame(minHeight: 130)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .editorSheetInputSurface()
                        }
                    }

                    EditorSheetSection(
                        title: String(localized: L10n.Recordings.addLocation),
                        systemImage: "location.fill",
                        tint: AppTheme.success
                    ) {
                        Toggle(isOn: $includesLocation) {
                            Text(L10n.Recordings.addLocation)
                        }

                        if includesLocation {
                            MacRecordingLocationPreview(provider: locationProvider)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppTheme.groupedBackground)

            Divider()

            HStack {
                Button {
                    dismiss()
                } label: {
                    Text(L10n.Common.cancel)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    save()
                } label: {
                    Text(L10n.Common.save)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 620)
        .onChange(of: includesLocation) { _, isEnabled in
            if isEnabled {
                locationProvider.requestLocation()
            } else {
                locationProvider.reset()
            }
        }
    }

    private func generateTitle() {
        isGeneratingTitle = true
        Task {
            defer { isGeneratingTitle = false }
            do {
                let suggestion = try await store.generateSuggestedTitle(for: item)
                name = suggestion.title
                if tagsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tagsText = suggestion.tags.joined(separator: ", ")
                }
                if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let suggestedSummary = suggestion.summary {
                    summary = suggestedSummary
                }
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func save() {
        let manualTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedNewCategory = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = trimmedNewCategory.isEmpty ? categoryName : trimmedNewCategory
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeyPoints = keyPoints.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try store.updateDetails(
                for: item,
                proposedName: name,
                manualTags: manualTags,
                summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                projectName: item.projectName,
                categoryName: resolvedCategory,
                keyPoints: trimmedKeyPoints.isEmpty ? nil : trimmedKeyPoints,
                location: includesLocation ? locationProvider.recordingLocation : nil,
                language: TranscriptionLanguage(id: languageID)
            )
            dismiss()
        } catch {
            onError(error.localizedDescription)
        }
    }
}

/// Read-only audio file parameters sheet mirroring the iOS audio info view.
struct MacAudioInfoSheet: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore

    @Environment(\.dismiss) private var dismiss
    @State private var info: RecordingAudioFileInfo?
    @State private var loadErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.Recordings.audioParameters)
                .font(.title2.bold())
                .padding(.bottom, 14)

            Group {
                if let info {
                    Form {
                        LabeledContent {
                            Text(verbatim: info.fileName)
                        } label: {
                            Text(L10n.Recordings.fileName)
                        }
                        LabeledContent {
                            Text(verbatim: info.fileFormatName)
                        } label: {
                            Text(L10n.Recordings.fileFormat)
                        }
                        LabeledContent {
                            Text(verbatim: info.fileSampleRateText)
                        } label: {
                            Text(L10n.Recordings.sampleRate)
                        }
                        LabeledContent {
                            Text(verbatim: info.channelLayoutText)
                        } label: {
                            Text(L10n.Recordings.channels)
                        }
                        if let bitDepth = info.bitDepth {
                            LabeledContent {
                                Text(verbatim: localizedFormat(L10n.Recordings.bitDepthFormat, bitDepth))
                            } label: {
                                Text(L10n.Recordings.encoding)
                            }
                        }
                        if let encoderBitRate = info.encoderBitRate {
                            LabeledContent {
                                Text(verbatim: "\(encoderBitRate / 1_000) kbps")
                            } label: {
                                Text(L10n.Recordings.bitRate)
                            }
                        }
                        LabeledContent {
                            Text(verbatim: "\(info.frameCount)")
                                .monospacedDigit()
                        } label: {
                            Text(L10n.Recordings.audioFrames)
                        }
                        LabeledContent {
                            Text(verbatim: TranscriptionLine.formatTimestamp(info.durationSeconds))
                                .monospacedDigit()
                        } label: {
                            Text(L10n.Recordings.audioDuration)
                        }
                        if let fileSize = info.fileSize {
                            LabeledContent {
                                Text(
                                    verbatim: ByteCountFormatter.string(
                                        fromByteCount: fileSize,
                                        countStyle: .file
                                    )
                                )
                            } label: {
                                Text(L10n.Recordings.fileSize)
                            }
                        }
                        if let creationDate = info.fileCreationDate {
                            LabeledContent {
                                Text(creationDate, format: .dateTime.year().month().day().hour().minute())
                            } label: {
                                Text(L10n.Recordings.fileCreationDate)
                            }
                        }
                    }
                    .formStyle(.grouped)
                } else if let loadErrorMessage {
                    Label {
                        Text(verbatim: loadErrorMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(L10n.Common.close)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(22)
        .frame(minWidth: 460, minHeight: 420)
        .task {
            do {
                info = try RecordingAudioFileInfo(url: store.audioURL(for: item))
            } catch {
                loadErrorMessage = error.localizedDescription
            }
        }
    }
}
