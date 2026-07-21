import SwiftUI
import TranscriberDomain

private enum MacSidebarDestination: String, CaseIterable, Identifiable {
    case library
    case capture

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .library:
            return MacL10n.library
        case .capture:
            return MacL10n.capture
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            return "rectangle.stack"
        case .capture:
            return "rectangle.inset.filled.and.person.filled"
        }
    }
}

struct MacRootView: View {
    @State private var selection: MacSidebarDestination? = .library

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(MacSidebarDestination.allCases) { destination in
                        Label {
                            Text(destination.title)
                        } icon: {
                            Image(systemName: destination.systemImage)
                        }
                        .tag(destination)
                    }
                } header: {
                    Text(MacL10n.workspace)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(Text(MacL10n.appName))
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            switch selection ?? .library {
            case .library:
                MacLibraryView()
            case .capture:
                MacCaptureFoundationView()
            }
        }
    }
}

private struct MacCaptureFoundationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MacL10n.captureTitle)
                        .font(.largeTitle.bold())
                    Text(MacL10n.captureDetail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 16) {
                    MacFoundationCard(
                        icon: "macwindow.on.rectangle",
                        title: MacL10n.screenCapture,
                        detail: MacL10n.screenCaptureDetail
                    )
                    MacFoundationCard(
                        icon: "waveform.badge.mic",
                        title: MacL10n.audioCapture,
                        detail: MacL10n.audioCaptureDetail
                    )
                }

                Label {
                    Text(MacL10n.foundationStatus)
                } icon: {
                    Image(systemName: "hammer")
                }
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .padding(32)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle(Text(MacL10n.captureTitle))
    }
}

private struct MacFoundationCard: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.title3.bold())

            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }
}

struct MacSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(MacL10n.nativeMacOS)
                } label: {
                    Text(MacL10n.platform)
                }

                LabeledContent {
                    Text(verbatim: "v\(TranscriberDomainSchema.currentVersion)")
                        .monospacedDigit()
                } label: {
                    Text(MacL10n.domainSchema)
                }
            } header: {
                Text(MacL10n.foundation)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 240)
        .navigationTitle(Text(MacL10n.settingsTitle))
    }
}
