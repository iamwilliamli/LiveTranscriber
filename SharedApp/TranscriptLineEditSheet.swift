import SwiftUI

enum TranscriptSpeakerApplyScope: String, CaseIterable, Identifiable {
    case currentOnly
    case matchingFollowing

    var id: String { rawValue }
}

struct EditorSheetSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let detail: String?
    private let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color = AppTheme.brand,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }
}

private struct EditorSheetInputSurfaceModifier: ViewModifier {
    let tint: Color?

    private var backgroundColor: Color {
        tint?.opacity(0.08) ?? AppTheme.elevatedBackground
    }

    private var borderColor: Color {
        tint?.opacity(0.22) ?? AppTheme.subtleBorder
    }

    func body(content: Content) -> some View {
        content
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }
}

extension View {
    func editorSheetInputSurface(tint: Color? = nil) -> some View {
        modifier(EditorSheetInputSurfaceModifier(tint: tint))
    }
}

struct TranscriptSpeakerEditOption: Identifiable {
    let id: String
    let displayName: String
    let tint: Color
}

struct TranscriptLineEditSheet: View {
    let timeText: String
    @Binding var text: String
    @Binding var selectedSpeakerID: String?
    let speakerOptions: [TranscriptSpeakerEditOption]
    let newSpeakerOption: TranscriptSpeakerEditOption
    let showsSpeakerEditor: Bool
    let originalSpeakerID: String?
    let followingSpeakerSegmentCount: Int
    @Binding var speakerApplyScope: TranscriptSpeakerApplyScope
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    init(
        timeText: String,
        text: Binding<String>,
        selectedSpeakerID: Binding<String?>,
        speakerOptions: [TranscriptSpeakerEditOption],
        newSpeakerOption: TranscriptSpeakerEditOption,
        showsSpeakerEditor: Bool,
        originalSpeakerID: String? = nil,
        followingSpeakerSegmentCount: Int = 0,
        speakerApplyScope: Binding<TranscriptSpeakerApplyScope> = .constant(.currentOnly),
        isSaving: Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.timeText = timeText
        _text = text
        _selectedSpeakerID = selectedSpeakerID
        self.speakerOptions = speakerOptions
        self.newSpeakerOption = newSpeakerOption
        self.showsSpeakerEditor = showsSpeakerEditor
        self.originalSpeakerID = originalSpeakerID
        self.followingSpeakerSegmentCount = followingSpeakerSegmentCount
        _speakerApplyScope = speakerApplyScope
        self.isSaving = isSaving
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedSpeaker: TranscriptSpeakerEditOption? {
        (speakerOptions + [newSpeakerOption]).first { $0.id == selectedSpeakerID }
    }

    private var hasSpeakerChange: Bool {
        let original = TranscriptSpeakerNaming.normalizedID(originalSpeakerID)
        let selected = TranscriptSpeakerNaming.normalizedID(selectedSpeakerID)
        switch (original, selected) {
        case let (original?, selected?):
            return original.caseInsensitiveCompare(selected) != .orderedSame
        case (nil, nil):
            return false
        default:
            return true
        }
    }

    private var showsSpeakerApplyScope: Bool {
        showsSpeakerEditor && hasSpeakerChange && followingSpeakerSegmentCount > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(timeText, systemImage: "clock")
                        .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.info)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(AppTheme.info.opacity(0.10), in: Capsule())

                    if showsSpeakerEditor {
                        EditorSheetSection(
                            title: String(localized: L10n.Recordings.transcriptSpeaker),
                            systemImage: "person.wave.2.fill",
                            tint: selectedSpeaker?.tint ?? AppTheme.info,
                            detail: String(localized: L10n.Recordings.transcriptSpeakerCurrentSegmentDetail)
                        ) {
                            Menu {
                                Button {
                                    HapticFeedback.play(.menuSelection)
                                    selectedSpeakerID = nil
                                } label: {
                                    Label(
                                        String(localized: L10n.Recordings.transcriptNoSpeaker),
                                        systemImage: selectedSpeakerID == nil ? "checkmark" : "person.slash"
                                    )
                                }

                                if !speakerOptions.isEmpty {
                                    Divider()
                                }

                                ForEach(speakerOptions) { option in
                                    Button {
                                        HapticFeedback.play(.menuSelection)
                                        selectedSpeakerID = option.id
                                    } label: {
                                        Label(
                                            option.displayName,
                                            systemImage: selectedSpeakerID == option.id ? "checkmark" : "person.fill"
                                        )
                                    }
                                }

                                Divider()

                                Button {
                                    HapticFeedback.play(.menuSelection)
                                    selectedSpeakerID = newSpeakerOption.id
                                } label: {
                                    Label(
                                        String(localized: L10n.Recordings.transcriptNewSpeaker),
                                        systemImage: selectedSpeakerID == newSpeakerOption.id ? "checkmark" : "person.badge.plus"
                                    )
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(selectedSpeaker?.tint ?? Color.secondary.opacity(0.45))
                                        .frame(width: 9, height: 9)

                                    Text(selectedSpeaker?.displayName ?? String(localized: L10n.Recordings.transcriptNoSpeaker))
                                        .font(.redditSans(.body, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 13)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .editorSheetInputSurface(tint: selectedSpeaker?.tint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(L10n.Recordings.transcriptSpeaker))
                            .accessibilityValue(
                                Text(selectedSpeaker?.displayName ?? String(localized: L10n.Recordings.transcriptNoSpeaker))
                            )

                            if showsSpeakerApplyScope {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.Recordings.transcriptSpeakerPropagationTitle)
                                        .font(.redditSans(.caption, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    VStack(spacing: 0) {
                                        speakerScopeButton(
                                            .currentOnly,
                                            title: String(localized: L10n.Recordings.transcriptSpeakerPropagationCurrentOnlyAction)
                                        )

                                        Divider()
                                            .padding(.leading, 42)

                                        speakerScopeButton(
                                            .matchingFollowing,
                                            title: localizedFormat(
                                                L10n.Recordings.transcriptSpeakerPropagationFollowingActionFormat,
                                                followingSpeakerSegmentCount
                                            )
                                        )
                                    }
                                    .editorSheetInputSurface()
                                }
                            }
                        }
                    }

                    EditorSheetSection(
                        title: String(localized: L10n.Recordings.transcriptLineText),
                        systemImage: "text.cursor",
                        tint: AppTheme.brand
                    ) {
                        TextEditor(text: $text)
                            .font(.redditSans(.body))
                            .lineSpacing(4)
                            .frame(minHeight: showsSpeakerEditor ? 150 : 220)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .editorSheetInputSurface()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(String(localized: L10n.Recordings.editTranscriptLine))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: L10n.Common.cancel)) {
                        onCancel()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.Common.save)) {
                        onSave()
                    }
                    .disabled(isSaving || trimmedText.isEmpty)
                }
            }
        }
    }

    private func speakerScopeButton(
        _ scope: TranscriptSpeakerApplyScope,
        title: String
    ) -> some View {
        Button {
            HapticFeedback.play(.menuSelection)
            speakerApplyScope = scope
        } label: {
            HStack(spacing: 11) {
                Image(systemName: speakerApplyScope == scope ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(speakerApplyScope == scope ? AppTheme.info : Color.secondary)

                Text(title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TranscriptSpeakerListEditSheet: View {
    let speakers: [TranscriptSpeakerPresentation]
    @Binding var namesBySpeakerID: [String: String]
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedSpeakerID: String?

    private var hasEmptyName: Bool {
        speakers.contains { speaker in
            trimmedName(for: speaker).isEmpty
        }
    }

    private var hasChanges: Bool {
        speakers.contains { speaker in
            trimmedName(for: speaker) != speaker.displayName
        }
    }

    private var canSave: Bool {
        !isSaving && !hasEmptyName && hasChanges
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                EditorSheetSection(
                    title: String(localized: L10n.Recordings.transcriptEditSpeakers),
                    systemImage: "person.2.fill",
                    tint: AppTheme.info,
                    detail: String(localized: L10n.Recordings.transcriptEditSpeakersDetail)
                ) {
                    VStack(spacing: 0) {
                        ForEach(Array(speakers.enumerated()), id: \.element.id) { index, speaker in
                            speakerRow(speaker, index: index)

                            if index < speakers.count - 1 {
                                Divider()
                                    .padding(.leading, 54)
                            }
                        }
                    }
                    .editorSheetInputSurface()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(String(localized: L10n.Recordings.transcriptEditSpeakers))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: L10n.Common.cancel)) {
                        onCancel()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.Common.save)) {
                        onSave()
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 360)
        #endif
    }

    private func speakerRow(
        _ speaker: TranscriptSpeakerPresentation,
        index: Int
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(speaker.tint.opacity(0.14))

                Circle()
                    .stroke(speaker.tint.opacity(0.24), lineWidth: 1)

                Text(verbatim: "\(index + 1)")
                    .font(.redditSans(.caption, weight: .bold))
                    .foregroundStyle(speaker.tint)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            TextField(
                String(localized: L10n.Recordings.transcriptSpeakerName),
                text: nameBinding(for: speaker)
            )
            .font(.redditSans(.body, weight: .semibold))
            .textFieldStyle(.plain)
            .focused($focusedSpeakerID, equals: speaker.id)
            #if os(iOS)
            .textInputAutocapitalization(.words)
            .submitLabel(index == speakers.count - 1 ? .done : .next)
            #endif
            .onSubmit {
                focusNextSpeaker(after: index)
            }

            if trimmedName(for: speaker).isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(AppTheme.danger)
                    .accessibilityLabel(Text(L10n.Recordings.transcriptSpeakerName))
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 58)
    }

    private func nameBinding(for speaker: TranscriptSpeakerPresentation) -> Binding<String> {
        Binding(
            get: {
                namesBySpeakerID[speaker.id] ?? speaker.displayName
            },
            set: {
                namesBySpeakerID[speaker.id] = $0
            }
        )
    }

    private func trimmedName(for speaker: TranscriptSpeakerPresentation) -> String {
        (namesBySpeakerID[speaker.id] ?? speaker.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func focusNextSpeaker(after index: Int) {
        guard index + 1 < speakers.count else {
            focusedSpeakerID = nil
            return
        }
        focusedSpeakerID = speakers[index + 1].id
    }
}
