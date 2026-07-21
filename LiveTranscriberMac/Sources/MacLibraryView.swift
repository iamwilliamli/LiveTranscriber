import Combine
import Foundation
import SwiftUI
import TranscriberDomain
import UniformTypeIdentifiers

@MainActor
final class MacLibraryViewModel: ObservableObject {
    @Published private(set) var sessions: [RecordingSession] = []
    @Published var selectedSessionID: RecordingSession.ID?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var sourceName = "iCloud Drive"
    @Published private(set) var sourcePath: String?
    @Published private(set) var transcriptText: String?
    @Published private(set) var isLoadingTranscript = false

    let library = MacRecordingLibrary()

    var selectedSession: RecordingSession? {
        guard let selectedSessionID else {
            return nil
        }
        return sessions.first(where: { $0.id == selectedSessionID })
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let location = try await library.location()
            sourceName = location.kind == .iCloud ? "iCloud Drive" : "Selected Folder"
            sourcePath = location.directoryURL.path
            let loadedSessions = try await library.recordingSessions()
            sessions = loadedSessions
            if let selectedSessionID,
               loadedSessions.contains(where: { $0.id == selectedSessionID }) {
                self.selectedSessionID = selectedSessionID
            } else {
                selectedSessionID = loadedSessions.first?.id
            }
        } catch {
            sessions = []
            selectedSessionID = nil
            transcriptText = nil
            errorMessage = error.localizedDescription
        }
    }

    func selectDirectory(_ url: URL) async {
        do {
            try await library.selectDirectory(url)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func useICloudDirectory() async {
        await library.useICloudDirectory()
        await reload()
    }

    func loadSelectedTranscript() async {
        let requestedSessionID = selectedSessionID
        guard let session = selectedSession,
              let transcriptAsset = session.assets.first(where: { $0.kind == .transcript }) else {
            transcriptText = nil
            isLoadingTranscript = false
            return
        }

        isLoadingTranscript = true
        defer { isLoadingTranscript = false }
        do {
            let url = try await library.recordingAssetURL(
                sessionID: session.id,
                assetID: transcriptAsset.id
            )
            let text = try await Task.detached(priority: .utility) {
                try String(contentsOf: url, encoding: .utf8)
            }.value
            guard selectedSessionID == requestedSessionID else {
                return
            }
            transcriptText = text
        } catch {
            guard selectedSessionID == requestedSessionID else {
                return
            }
            transcriptText = nil
        }
    }
}

struct MacLibraryView: View {
    @StateObject private var model = MacLibraryViewModel()
    @StateObject private var player = MacRecordingPlayer()
    @State private var isSelectingDirectory = false

    var body: some View {
        HSplitView {
            libraryList
                .frame(minWidth: 280, idealWidth: 330, maxWidth: 420)

            Group {
                if let session = model.selectedSession {
                    MacRecordingDetailView(
                        session: session,
                        transcriptText: model.transcriptText,
                        isLoadingTranscript: model.isLoadingTranscript,
                        library: model.library,
                        player: player
                    )
                } else if model.isLoading {
                    ProgressView(MacL10n.loadingLibrary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(Text(MacL10n.libraryTitle))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.reload() }
                } label: {
                    Label(MacL10n.refreshLibrary, systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)

                Menu {
                    Button {
                        isSelectingDirectory = true
                    } label: {
                        Label(MacL10n.chooseFolder, systemImage: "folder")
                    }

                    Button {
                        Task { await model.useICloudDirectory() }
                    } label: {
                        Label(MacL10n.useICloud, systemImage: "icloud")
                    }
                } label: {
                    Label(MacL10n.librarySource, systemImage: "externaldrive.connected.to.line.below")
                }
            }
        }
        .fileImporter(
            isPresented: $isSelectingDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else {
                return
            }
            Task { await model.selectDirectory(url) }
        }
        .task {
            await model.reload()
        }
        .task(id: model.selectedSessionID) {
            await model.loadSelectedTranscript()
        }
    }

    private var libraryList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: model.sourceName == "iCloud Drive" ? "icloud" : "folder")
                    Text(model.sourceName)
                        .font(.headline)
                    Spacer()
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let sourcePath = model.sourcePath {
                    Text(sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            List(selection: $model.selectedSessionID) {
                ForEach(model.sessions) { session in
                    MacRecordingRow(session: session)
                        .tag(session.id)
                }
            }
            .overlay {
                if model.sessions.isEmpty, model.isLoading {
                    ProgressView()
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                model.errorMessage == nil ? MacL10n.noRecordings : MacL10n.libraryUnavailable,
                systemImage: model.errorMessage == nil ? "waveform.slash" : "icloud.slash"
            )
        } description: {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
            } else {
                Text(MacL10n.noRecordingsDetail)
            }
        } actions: {
            Button(MacL10n.chooseFolder) {
                isSelectingDirectory = true
            }
        }
    }
}

private struct MacRecordingRow: View {
    let session: RecordingSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.assets.contains(where: { $0.kind.isVideo })
                ? "video.fill"
                : "waveform")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(session.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    if session.durationSeconds > 0 {
                        Text(TranscriptionLine.formatTimestamp(session.durationSeconds))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MacRecordingDetailView: View {
    let session: RecordingSession
    let transcriptText: String?
    let isLoadingTranscript: Bool
    let library: MacRecordingLibrary
    @ObservedObject var player: MacRecordingPlayer

    private var isCurrentSession: Bool {
        player.currentSessionID == session.id
    }

    private var displayedDuration: Double {
        if isCurrentSession, player.duration > 0 {
            return player.duration
        }
        return max(session.durationSeconds, 0)
    }

    private var displayedTime: Double {
        isCurrentSession ? player.currentTime : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.largeTitle.bold())
                        .textSelection(.enabled)
                    Text(session.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }

                playbackCard
                assetSection
                transcriptSection
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var playbackCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    Task {
                        await player.toggle(session: session, library: library)
                    }
                } label: {
                    Image(systemName: isCurrentSession && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(player.isPreparing)

                Slider(
                    value: Binding(
                        get: { min(displayedTime, max(displayedDuration, 0)) },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(displayedDuration, 1)
                )
                .disabled(!isCurrentSession || displayedDuration <= 0)

                Text(
                    "\(TranscriptionLine.formatTimestamp(displayedTime)) / \(TranscriptionLine.formatTimestamp(displayedDuration))"
                )
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if player.isPreparing {
                ProgressView(MacL10n.preparingPlayback)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorMessage = player.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var assetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MacL10n.assets)
                .font(.title3.bold())
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(session.assets) { asset in
                    Label(assetLabel(asset.kind), systemImage: assetIcon(asset.kind))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                        .help(asset.relativePath)
                }
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MacL10n.transcript)
                .font(.title3.bold())
            if isLoadingTranscript {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let transcriptText, !transcriptText.isEmpty {
                Text(transcriptText)
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text(MacL10n.noTranscript)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func assetLabel(_ kind: RecordingAssetKind) -> String {
        switch kind {
        case .primaryAudio: return "Audio"
        case .microphoneAudio: return "Microphone"
        case .systemAudio: return "System Audio"
        case .mixedAudio: return "Mixed Audio"
        case .screenVideo: return "Screen Video"
        case .cameraVideo: return "Camera Video"
        case .transcript: return "Transcript"
        case .thumbnail: return "Thumbnail"
        case .attachment: return "Attachment"
        }
    }

    private func assetIcon(_ kind: RecordingAssetKind) -> String {
        switch kind {
        case .primaryAudio, .mixedAudio: return "waveform"
        case .microphoneAudio: return "mic"
        case .systemAudio: return "speaker.wave.2"
        case .screenVideo: return "display"
        case .cameraVideo: return "video"
        case .transcript: return "text.alignleft"
        case .thumbnail: return "photo"
        case .attachment: return "paperclip"
        }
    }
}
