import MapKit
import SwiftUI
import TranscriberDomain
import UniformTypeIdentifiers

/// RecordingStore-backed library with feature parity to the iOS recordings tab:
/// search, categories, playback, transcript display and editing, AI analysis,
/// chat, export, and every retranscription engine.
struct MacRecordingsView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @Binding var selectedRecordingID: RecordingItem.ID?
    @Binding var pendingImportURLs: [URL]
    @StateObject private var player = RecordingPlaybackController()

    @State private var searchText = ""
    @State private var categoryFilter: MacRecordingCategoryFilter = .all
    @State private var isImportingRecording = false
    @State private var isShowingCategoryOrganizer = false
    @State private var isShowingRecordingMap = false
    @State private var categoryRevision = 0
    @State private var actionErrorMessage: String?

    private var filteredRecordings: [RecordingItem] {
        var items = store.recordings
        switch categoryFilter {
        case .all:
            break
        case .uncategorized:
            items = items.filter { $0.categoryName == nil }
        case .named(let name):
            let key = name.normalizedForRecordingSearch
            items = items.filter { $0.categoryName?.normalizedForRecordingSearch == key }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }
        let normalizedQuery = query.normalizedForRecordingSearch
        return items.filter { item in
            store.normalizedSearchText(for: item).contains(normalizedQuery)
        }
    }

    private var selectedRecording: RecordingItem? {
        guard let selectedRecordingID else {
            return nil
        }
        return store.recording(withID: selectedRecordingID)
    }

    private var categoryNames: [String] {
        _ = categoryRevision
        return RecordingCategoryCatalog.allNames(recordings: store.recordings)
    }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)

            Group {
                if let item = selectedRecording {
                    MacRecordingDetailView(
                        item: item,
                        store: store,
                        transcriber: transcriber,
                        player: player
                    )
                    .id(item.id)
                } else {
                    ContentUnavailableView {
                        Label {
                            Text(L10n.Recordings.noRecordings)
                        } icon: {
                            Image(systemName: "waveform")
                        }
                    }
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(Text(L10n.App.recordingsTab))
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker(selection: $categoryFilter) {
                        Text(L10n.Recordings.allRecordings)
                            .tag(MacRecordingCategoryFilter.all)
                        Text(L10n.Recordings.uncategorized)
                            .tag(MacRecordingCategoryFilter.uncategorized)
                        ForEach(categoryNames, id: \.self) { name in
                            Text(verbatim: name)
                                .tag(MacRecordingCategoryFilter.named(name))
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button {
                        isShowingCategoryOrganizer = true
                    } label: {
                        Label {
                            Text(L10n.Recordings.organize)
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                } label: {
                    Label {
                        Text(L10n.Recordings.categories)
                    } icon: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                }

                Button {
                    isImportingRecording = true
                } label: {
                    Label {
                        Text(L10n.Recordings.importRecording)
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }

                Button {
                    isShowingRecordingMap = true
                } label: {
                    Label {
                        Text(L10n.Recordings.mapTitle)
                    } icon: {
                        Image(systemName: "map")
                    }
                }
                .disabled(!store.recordings.contains(where: { $0.location != nil }))

                Button {
                    Task {
                        await store.reload()
                    }
                } label: {
                    Label(MacL10n.refreshLibrary, systemImage: "arrow.clockwise")
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingRecording,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                return
            }
            importRecordings(from: urls)
        }
        .sheet(isPresented: $isShowingCategoryOrganizer) {
            MacCategoryOrganizer(store: store) {
                categoryRevision += 1
                if case .named(let name) = categoryFilter,
                   !categoryNames.contains(where: {
                       $0.normalizedForRecordingSearch == name.normalizedForRecordingSearch
                   }) {
                    categoryFilter = .all
                }
            }
        }
        .sheet(isPresented: $isShowingRecordingMap) {
            MacRecordingsMapView(
                recordings: store.recordings,
                onSelect: { item in
                    selectedRecordingID = item.id
                    isShowingRecordingMap = false
                }
            )
        }
        .alert(
            String(localized: MacL10n.actionFailed),
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .task {
            consumePendingImportURLs()
        }
        .onChange(of: pendingImportURLs) { _, _ in
            consumePendingImportURLs()
        }
    }

    private var listPane: some View {
        List(selection: $selectedRecordingID) {
            ForEach(filteredRecordings) { item in
                MacRecordingListRow(item: item)
                    .tag(item.id)
            }
        }
        .overlay {
            if filteredRecordings.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(L10n.Recordings.noRecordings)
                    } icon: {
                        Image(systemName: "waveform.slash")
                    }
                }
            }
        }
    }

    private func consumePendingImportURLs() {
        guard !pendingImportURLs.isEmpty else {
            return
        }
        let urls = pendingImportURLs
        pendingImportURLs = []
        importRecordings(from: urls)
    }

    private func importRecordings(from urls: [URL]) {
        Task {
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
                    let imported: RecordingItem?
                    if contentType?.conforms(to: .movie) == true {
                        imported = try await store.importVideoRecording(from: url)
                    } else {
                        imported = try await store.importRecording(from: url)
                    }
                    if let imported {
                        selectedRecordingID = imported.id
                    }
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct MacCategoryOrganizer: View {
    @ObservedObject var store: RecordingStore
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var categoryNames: [String] = []
    @State private var selectedName: String?
    @State private var editedName = ""
    @State private var newName = ""
    @State private var iconName = RecordingCategoryAppearance.defaultValue.iconName
    @State private var iconColor = RecordingCategoryAppearance.defaultValue.color
    @State private var errorMessage: String?
    @State private var categoryPendingDeletion: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.Recordings.organize)
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(L10n.Common.done)
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            HSplitView {
                VStack(spacing: 10) {
                    List(selection: $selectedName) {
                        ForEach(categoryNames, id: \.self) { name in
                            let appearance = RecordingCategoryAppearanceCatalog.appearance(for: name)
                            Label {
                                Text(verbatim: name)
                            } icon: {
                                Image(systemName: appearance.iconName)
                                    .foregroundStyle(appearance.color)
                            }
                            .tag(String?.some(name))
                        }
                    }

                    HStack {
                        TextField(text: $newName) {
                            Text(L10n.Recordings.categoryNamePlaceholder)
                        }
                        Button {
                            createCategory()
                        } label: {
                            Label {
                                Text(L10n.Recordings.newCategory)
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding([.horizontal, .bottom], 12)
                }
                .frame(minWidth: 260, idealWidth: 300)

                Group {
                    if let selectedName {
                        Form {
                            TextField(text: $editedName) {
                                Text(L10n.Recordings.categoryName)
                            }

                            Picker(selection: $iconName) {
                                ForEach(RecordingCategoryAppearance.availableIconNames, id: \.self) { icon in
                                    Label(icon, systemImage: icon)
                                        .tag(icon)
                                }
                            } label: {
                                Text(L10n.Recordings.categoryIcon)
                            }

                            ColorPicker(selection: $iconColor, supportsOpacity: false) {
                                Text(L10n.Recordings.categoryIconColor)
                            }

                            if let errorMessage {
                                Label {
                                    Text(verbatim: errorMessage)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle")
                                }
                                .foregroundStyle(AppTheme.danger)
                            }

                            HStack {
                                Button(role: .destructive) {
                                    categoryPendingDeletion = selectedName
                                } label: {
                                    Text(L10n.Recordings.deleteCategory)
                                }

                                Spacer()

                                Button {
                                    saveCategory(originalName: selectedName)
                                } label: {
                                    Text(L10n.Common.save)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .formStyle(.grouped)
                    } else {
                        ContentUnavailableView {
                            Label {
                                Text(L10n.Recordings.categories)
                            } icon: {
                                Image(systemName: "folder")
                            }
                        }
                    }
                }
                .frame(minWidth: 340)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .task {
            refreshCategories(selecting: nil)
        }
        .onChange(of: selectedName) { _, name in
            loadEditor(for: name)
        }
        .confirmationDialog(
            String(localized: L10n.Recordings.deleteCategory),
            isPresented: Binding(
                get: { categoryPendingDeletion != nil },
                set: { if !$0 { categoryPendingDeletion = nil } }
            )
        ) {
            Button(String(localized: L10n.Recordings.deleteCategory), role: .destructive) {
                if let categoryPendingDeletion {
                    deleteCategory(categoryPendingDeletion)
                }
            }
            Button(String(localized: L10n.Common.cancel), role: .cancel) {}
        } message: {
            if let categoryPendingDeletion {
                Text(
                    verbatim: localizedFormat(
                        L10n.Recordings.deleteCategoryConfirmationFormat,
                        categoryPendingDeletion,
                        recordingCount(in: categoryPendingDeletion)
                    )
                )
            }
        }
    }

    private func refreshCategories(selecting requestedName: String?) {
        categoryNames = RecordingCategoryCatalog.allNames(recordings: store.recordings)
        if let requestedName,
           let matchingName = categoryNames.first(where: {
               $0.normalizedForRecordingSearch == requestedName.normalizedForRecordingSearch
           }) {
            selectedName = matchingName
        } else if let selectedName, categoryNames.contains(selectedName) {
            self.selectedName = selectedName
        } else {
            selectedName = categoryNames.first
        }
        loadEditor(for: selectedName)
    }

    private func loadEditor(for name: String?) {
        guard let name else {
            editedName = ""
            return
        }
        let appearance = RecordingCategoryAppearanceCatalog.appearance(for: name)
        editedName = name
        iconName = appearance.iconName
        iconColor = appearance.color
        errorMessage = nil
    }

    private func createCategory() {
        guard let cleanedName = RecordingItem.normalizedCategoryName(newName) else {
            return
        }
        guard !categoryNames.contains(where: {
            $0.normalizedForRecordingSearch == cleanedName.normalizedForRecordingSearch
        }) else {
            errorMessage = String(localized: L10n.Recordings.categoryExists)
            return
        }
        _ = RecordingCategoryCatalog.register(cleanedName)
        newName = ""
        refreshCategories(selecting: cleanedName)
        onChange()
    }

    private func saveCategory(originalName: String) {
        guard let cleanedName = RecordingItem.normalizedCategoryName(editedName) else {
            return
        }
        let duplicate = categoryNames.contains {
            $0.normalizedForRecordingSearch == cleanedName.normalizedForRecordingSearch
                && $0.normalizedForRecordingSearch != originalName.normalizedForRecordingSearch
        }
        guard !duplicate else {
            errorMessage = String(localized: L10n.Recordings.categoryExists)
            return
        }

        do {
            if cleanedName != originalName {
                _ = try store.renameCategory(named: originalName, to: cleanedName)
                RecordingCategoryCatalog.rename(originalName, to: cleanedName)
            } else {
                _ = RecordingCategoryCatalog.register(cleanedName)
            }
            RecordingCategoryAppearanceCatalog.set(
                RecordingCategoryAppearance(iconName: iconName, color: iconColor),
                for: cleanedName,
                removing: originalName
            )
            refreshCategories(selecting: cleanedName)
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCategory(_ name: String) {
        do {
            _ = try store.removeCategory(named: name)
            RecordingCategoryCatalog.remove(name)
            RecordingCategoryAppearanceCatalog.remove(name)
            categoryPendingDeletion = nil
            selectedName = nil
            refreshCategories(selecting: nil)
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordingCount(in categoryName: String) -> Int {
        let key = categoryName.normalizedForRecordingSearch
        return store.recordings.filter {
            $0.categoryName?.normalizedForRecordingSearch == key
        }.count
    }
}

enum MacRecordingCategoryFilter: Hashable {
    case all
    case uncategorized
    case named(String)
}

private struct MacRecordingListRow: View {
    let item: RecordingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: item.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if item.isTranscriptLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text(item.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Text(TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                    .monospacedDigit()
                if let categoryName = item.categoryName {
                    Label {
                        Text(verbatim: categoryName)
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let importStatus = item.importStatus {
                if importStatus.isFailed {
                    Label {
                        Text(verbatim: importStatus.message)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: importStatus.progress)
                        Text(verbatim: importStatus.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if let summary = item.intelligence?.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !item.transcriptPreview.isEmpty {
                Text(verbatim: item.transcriptPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MacRecordingsMapView: View {
    let recordings: [RecordingItem]
    let onSelect: (RecordingItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRecordingID: RecordingItem.ID?

    private var locatedRecordings: [RecordingItem] {
        recordings.filter { $0.location != nil }
    }

    private var selectedRecording: RecordingItem? {
        locatedRecordings.first { $0.id == selectedRecordingID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if locatedRecordings.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(L10n.Recordings.noLocatedRecordings)
                        } icon: {
                            Image(systemName: "map")
                        }
                    }
                } else {
                    Map(initialPosition: .region(mapRegion)) {
                        ForEach(locatedRecordings) { item in
                            if let location = item.location {
                                Annotation(
                                    item.displayName,
                                    coordinate: CLLocationCoordinate2D(
                                        latitude: location.latitude,
                                        longitude: location.longitude
                                    )
                                ) {
                                    Button {
                                        selectedRecordingID = item.id
                                    } label: {
                                        Image(
                                            systemName: selectedRecordingID == item.id
                                                ? "waveform.circle.fill"
                                                : "waveform.circle"
                                        )
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(.white, AppTheme.brand)
                                        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let selectedRecording {
                            Button {
                                onSelect(selectedRecording)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "waveform")
                                        .font(.title2)
                                        .foregroundStyle(AppTheme.brand)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: selectedRecording.displayName)
                                            .font(.headline)
                                        HStack(spacing: 8) {
                                            if let location = selectedRecording.location {
                                                Label {
                                                    Text(
                                                        verbatim: location.placeName
                                                            ?? "\(location.latitude.formatted(.number.precision(.fractionLength(4)))), \(location.longitude.formatted(.number.precision(.fractionLength(4))))"
                                                    )
                                                } icon: {
                                                    Image(systemName: "mappin.and.ellipse")
                                                }
                                            }
                                            Label(
                                                TranscriptionLine.formatTimestamp(Double(selectedRecording.durationSeconds)),
                                                systemImage: "clock"
                                            )
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title2)
                                }
                                .padding(14)
                                .frame(maxWidth: 520)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .padding(18)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: L10n.Recordings.mapTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.Common.done)
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var mapRegion: MKCoordinateRegion {
        guard let first = locatedRecordings.first?.location else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        let locations = locatedRecordings.compactMap(\.location)
        let latitudes = locations.map(\.latitude)
        let longitudes = locations.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLatitude - minLatitude) * 1.8),
                longitudeDelta: max(0.01, (maxLongitude - minLongitude) * 1.8)
            )
        )
    }
}
