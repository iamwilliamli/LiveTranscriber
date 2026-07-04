import SwiftUI

struct TranscriptLineEditSheet: View {
    let timeText: String
    @Binding var text: String
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Label(timeText, systemImage: "text.alignleft")
                    .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: L10n.Recordings.transcriptLineText), systemImage: "pencil")
                        .font(.redditSans(.subheadline, weight: .semibold))

                    TextEditor(text: $text)
                        .font(.redditSans(.body))
                        .lineSpacing(4)
                        .frame(minHeight: 180)
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
