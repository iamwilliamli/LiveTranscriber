import SwiftUI

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
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedSpeaker: TranscriptSpeakerEditOption? {
        (speakerOptions + [newSpeakerOption]).first { $0.id == selectedSpeakerID }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Label(timeText, systemImage: "text.alignleft")
                    .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)

                if showsSpeakerEditor {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: L10n.Recordings.transcriptSpeaker), systemImage: "person.wave.2")
                            .font(.redditSans(.subheadline, weight: .semibold))

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
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                selectedSpeaker?.tint.opacity(0.08) ?? AppTheme.cardBackground,
                                in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                                    .stroke(selectedSpeaker?.tint.opacity(0.24) ?? AppTheme.cardBorder, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(L10n.Recordings.transcriptSpeaker))
                        .accessibilityValue(
                            Text(selectedSpeaker?.displayName ?? String(localized: L10n.Recordings.transcriptNoSpeaker))
                        )

                        Text(L10n.Recordings.transcriptSpeakerCurrentSegmentDetail)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: L10n.Recordings.transcriptLineText), systemImage: "pencil")
                        .font(.redditSans(.subheadline, weight: .semibold))

                    TextEditor(text: $text)
                        .font(.redditSans(.body))
                        .lineSpacing(4)
                        .frame(minHeight: showsSpeakerEditor ? 130 : 180)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(String(localized: L10n.Recordings.editTranscriptLine))
            .navigationBarTitleDisplayMode(.inline)
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
}
