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
            Text(L10n.Recordings.editDetails)
                .font(.title2.bold())
                .padding(.bottom, 14)

            Form {
                HStack {
                    TextField(text: $name) {
                        Text(L10n.Recordings.recordingName)
                    }

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
                        .disabled(isGeneratingTitle)
                        .help(String(localized: L10n.Recordings.generateTagsAndSummary))
                    }
                }

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
                    Text(L10n.Settings.transcriptionLanguage)
                }

                Picker(selection: $categoryName) {
                    Text(L10n.Recordings.uncategorized)
                        .tag(String?.none)
                    ForEach(categories, id: \.self) { category in
                        Text(verbatim: category)
                            .tag(String?.some(category))
                    }
                } label: {
                    Text(L10n.Recordings.categoryName)
                }

                TextField(text: $newCategoryName) {
                    Text(L10n.Recordings.categoryNamePlaceholder)
                }

                TextField(text: $tagsText) {
                    Text(L10n.Recordings.tags)
                }

                TextField(text: $keyPoints, axis: .vertical) {
                    Text(L10n.Recordings.keyPoints)
                }
                .lineLimit(2...4)

                TextField(text: $summary, axis: .vertical) {
                    Text(L10n.Recordings.intelligenceSummary)
                }
                .lineLimit(3...6)

                Toggle(isOn: $includesLocation) {
                    Text(L10n.Recordings.addLocation)
                }

                if includesLocation {
                    MacRecordingLocationPreview(provider: locationProvider)
                }
            }
            .formStyle(.grouped)

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
            }
            .padding(.top, 14)
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 480)
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
