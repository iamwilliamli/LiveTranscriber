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
    @State private var player = RecordingPlaybackController()

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

    private var uncategorizedCount: Int {
        store.recordings.filter { $0.categoryName == nil }.count
    }

    private var selectedCategoryTitle: String {
        switch categoryFilter {
        case .all:
            return String(localized: L10n.Recordings.allRecordings)
        case .uncategorized:
            return String(localized: L10n.Recordings.uncategorized)
        case .named(let name):
            return name
        }
    }

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 340, idealWidth: 370, maxWidth: 440)

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
            .frame(minWidth: 500, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
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
        .onChange(of: selectedRecordingID) { _, newValue in
            if newValue == nil {
                player.unload()
            }
        }
        .onDisappear {
            player.unload()
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Recordings.title)
                            .font(.redditSans(.title3, weight: .bold))
                        Text(
                            String(
                                format: String(localized: L10n.Recordings.categoryCountFormat),
                                store.recordings.count
                            )
                        )
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 10)

                    Button {
                        isShowingCategoryOrganizer = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: L10n.Recordings.organize))
                }

                categoryBrowser
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            HStack {
                Text(verbatim: selectedCategoryTitle)
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(verbatim: "\(filteredRecordings.count)")
                    .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredRecordings) { item in
                        Button {
                            selectedRecordingID = item.id
                        } label: {
                            MacRecordingListRow(
                                item: item,
                                isSelected: selectedRecordingID == item.id
                            )
                        }
                        .buttonStyle(MacRecordingCardButtonStyle())
                        .accessibilityAddTraits(
                            selectedRecordingID == item.id ? .isSelected : []
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .overlay {
                if filteredRecordings.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(
                                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? L10n.Recordings.noRecordings
                                    : L10n.Recordings.noSearchResults
                            )
                        } icon: {
                            Image(
                                systemName: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "waveform.slash"
                                    : "magnifyingglass"
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(AppTheme.groupedBackground)
    }

    private var categoryBrowser: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                MacRecordingCategoryButton(
                    title: String(localized: L10n.Recordings.allRecordings),
                    count: store.recordings.count,
                    systemImage: "square.grid.2x2",
                    tint: AppTheme.brand,
                    isSelected: categoryFilter == .all
                ) {
                    categoryFilter = .all
                }

                if uncategorizedCount > 0 {
                    MacRecordingCategoryButton(
                        title: String(localized: L10n.Recordings.uncategorized),
                        count: uncategorizedCount,
                        systemImage: "tray",
                        tint: .secondary,
                        isSelected: categoryFilter == .uncategorized
                    ) {
                        categoryFilter = .uncategorized
                    }
                }

                ForEach(categoryNames, id: \.self) { name in
                    let appearance = RecordingCategoryAppearanceCatalog.appearance(for: name)
                    MacRecordingCategoryButton(
                        title: name,
                        count: recordingCount(in: name),
                        systemImage: appearance.iconName,
                        tint: appearance.color,
                        isSelected: categoryFilter == .named(name)
                    ) {
                        categoryFilter = .named(name)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func recordingCount(in categoryName: String) -> Int {
        let key = categoryName.normalizedForRecordingSearch
        return store.recordings.filter {
            $0.categoryName?.normalizedForRecordingSearch == key
        }.count
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

private struct MacRecordingCategoryButton: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(verbatim: "\(count)")
                        .font(.redditSans(.caption2).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(
                isSelected ? tint.opacity(0.13) : AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.55) : AppTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MacRecordingCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
            )
    }
}

private struct MacRecordingListRow: View {
    let item: RecordingItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                        .fill(AppTheme.brand.opacity(0.12))
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.brand)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(verbatim: item.displayName)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if item.isTranscriptLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(item.createdAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .font(.redditSans(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailingStatus
            }

            MacRecordingMetadataStrip(item: item)

            if !item.combinedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(item.combinedTags.prefix(4)), id: \.self) { tag in
                            Text(verbatim: tag)
                                .font(.redditSans(.caption2, weight: .semibold))
                                .foregroundStyle(AppTheme.info)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(AppTheme.info.opacity(0.11), in: Capsule())
                        }
                    }
                }
                .scrollClipDisabled()
            }

            if let importStatus = item.importStatus {
                if importStatus.isFailed {
                    Label {
                        Text(verbatim: importStatus.message)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.danger)
                    .lineLimit(2)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: importStatus.progress)
                        Text(verbatim: importStatus.message)
                            .font(.redditSans(.caption2, weight: .semibold))
                            .foregroundStyle(AppTheme.info)
                            .lineLimit(1)
                    }
                }
            } else if let summary = item.intelligence?.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !item.transcriptPreview.isEmpty {
                Text(verbatim: item.transcriptPreview)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? AppTheme.brand.opacity(0.10) : AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.brand.opacity(0.62) : AppTheme.cardBorder,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .shadow(
            color: isSelected ? AppTheme.brand.opacity(0.08) : AppTheme.cardShadow,
            radius: isSelected ? 5 : AppTheme.cardShadowRadius,
            y: AppTheme.cardShadowYOffset
        )
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if item.importStatus?.isFailed == true {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
                .frame(width: 25, height: 25)
        } else if item.importStatus != nil {
            ProgressView()
                .controlSize(.small)
                .frame(width: 25, height: 25)
        } else {
            Text(TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 25)
                .background(Color.secondary.opacity(0.10), in: Capsule())
        }
    }
}

private struct MacRecordingMetadataStrip: View {
    let item: RecordingItem

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                MacRecordingMetadataChip(
                    systemImage: "globe",
                    text: item.localizedLanguageName
                )
                MacRecordingMetadataChip(
                    systemImage: "text.alignleft",
                    text: "\(item.lineCount)"
                )
                if let projectName = item.projectName {
                    MacRecordingMetadataChip(systemImage: "briefcase", text: projectName)
                }
                if let categoryName = item.categoryName {
                    let appearance = RecordingCategoryAppearanceCatalog.appearance(for: categoryName)
                    MacRecordingMetadataChip(
                        systemImage: appearance.iconName,
                        text: categoryName,
                        tint: appearance.color
                    )
                }
                if let placeName = item.location?.placeName {
                    MacRecordingMetadataChip(
                        systemImage: "mappin.and.ellipse",
                        text: placeName
                    )
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct MacRecordingMetadataChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(verbatim: text)
                .font(.redditSans(.caption2, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 21)
        .background(tint.opacity(0.09), in: Capsule())
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
