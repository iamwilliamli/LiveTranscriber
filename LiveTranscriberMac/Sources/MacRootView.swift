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
    @StateObject private var captureController = MacScreenCaptureController()

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
                MacCaptureView(
                    controller: captureController,
                    onOpenLibrary: { selection = .library }
                )
            }
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
