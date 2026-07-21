import SwiftUI
import TranscriberDomain

struct MacCaptureView: View {
    @ObservedObject var controller: MacScreenCaptureController
    let onOpenLibrary: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MacL10n.captureTitle)
                        .font(.largeTitle.bold())
                    Text(MacL10n.captureDetail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                sourceCard
                optionsCard
                captureControl

                if let warningMessage = controller.warningMessage {
                    Label(warningMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if let errorMessage = controller.errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
                if let result = controller.latestResult {
                    completionCard(result)
                }
            }
            .padding(32)
            .frame(maxWidth: 880, alignment: .leading)
        }
        .navigationTitle(Text(MacL10n.captureTitle))
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(MacL10n.captureSource)
                        .font(.title3.bold())
                    Text(controller.selectedSourceName ?? String(localized: MacL10n.noCaptureSource))
                        .foregroundStyle(controller.selectedSourceName == nil ? .secondary : .primary)
                }

                Spacer()

                Button(MacL10n.chooseCaptureSource) {
                    controller.presentSourcePicker()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.canChooseSource)
            }

            Text(MacL10n.captureSourceDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(MacL10n.audioTracks)
                .font(.title3.bold())

            Toggle(isOn: $controller.capturesSystemAudio) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MacL10n.systemAudio)
                        Text(MacL10n.systemAudioDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "speaker.wave.2")
                }
            }

            Divider()

            Toggle(isOn: $controller.capturesMicrophone) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MacL10n.microphoneAudio)
                        Text(MacL10n.microphoneAudioDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "mic")
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(controller.phase == .starting
            || controller.phase == .recording
            || controller.phase == .stopping)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var captureControl: some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    if controller.phase == .recording || controller.phase == .starting {
                        await controller.stopCapture()
                    } else {
                        await controller.startCapture()
                    }
                }
            } label: {
                Label(
                    captureButtonTitle,
                    systemImage: controller.phase == .recording ? "stop.fill" : "record.circle"
                )
                .font(.headline)
                .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.phase == .recording ? .red : .accentColor)
            .controlSize(.large)
            .disabled(!captureButtonEnabled)

            VStack(alignment: .leading, spacing: 3) {
                Text(captureStatusText)
                    .font(.headline)
                Text(TranscriptionLine.formatTimestamp(controller.elapsedSeconds))
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(controller.phase == .recording ? .red : .secondary)
            }

            Spacer()

            if controller.phase == .starting || controller.phase == .stopping {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .padding(.vertical, 2)
    }

    private func completionCard(_ result: MacCaptureResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(MacL10n.captureSaved, systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)

            Text(result.session.title)
                .font(.headline)
            HStack(spacing: 12) {
                Label(
                    TranscriptionLine.formatTimestamp(result.session.durationSeconds),
                    systemImage: "clock"
                )
                Label(
                    String.localizedStringWithFormat(
                        String(localized: MacL10n.savedAssetCount),
                        result.session.assets.count
                    ),
                    systemImage: "square.stack.3d.up"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button(MacL10n.openLibrary) {
                    onOpenLibrary()
                }
                .buttonStyle(.borderedProminent)

                Button(MacL10n.newCapture) {
                    controller.resetCompletion()
                }
            }
        }
        .padding(20)
        .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.green.opacity(0.25), lineWidth: 1)
        }
    }

    private var captureButtonTitle: LocalizedStringResource {
        switch controller.phase {
        case .starting: return MacL10n.startingCapture
        case .recording: return MacL10n.stopCapture
        case .stopping: return MacL10n.savingCapture
        case .idle, .sourceSelected, .completed, .failed: return MacL10n.startCapture
        }
    }

    private var captureStatusText: LocalizedStringResource {
        switch controller.phase {
        case .idle: return MacL10n.captureIdle
        case .sourceSelected: return MacL10n.captureReady
        case .starting: return MacL10n.startingCapture
        case .recording: return MacL10n.captureRecording
        case .stopping: return MacL10n.savingCapture
        case .completed: return MacL10n.captureComplete
        case .failed: return MacL10n.captureFailed
        }
    }

    private var captureButtonEnabled: Bool {
        switch controller.phase {
        case .recording:
            return true
        case .sourceSelected, .completed, .failed:
            return controller.canStart
        case .idle, .starting, .stopping:
            return false
        }
    }
}
