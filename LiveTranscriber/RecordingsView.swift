import AVFoundation
import CoreLocation
import MapKit
import SwiftUI
import Translation
import UIKit
import UniformTypeIdentifiers

struct RecordingsView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @Binding var searchText: String
    @Binding var selectedRecording: RecordingItem?
    @ObservedObject var player: RecordingPlaybackController
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var analyzingRecordingID: RecordingItem.ID?
    @State private var analysisErrorMessage: String?
    @State private var transcriptionErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @FocusState private var searchFieldIsFocused: Bool

    private var filteredRecordings: [RecordingItem] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else {
            return store.recordings
        }

        return store.recordings.filter { item in
            recording(item, matches: query)
        }
    }

    var body: some View {
        recordingsList
        .background(AppTheme.groupedBackground)
        .task {
            await transcriber.refreshSupportedLanguages()
            await store.reload()
            store.refreshIntelligenceAvailability()
        }
        .alert(
            "分析失败",
            isPresented: Binding(
                get: { analysisErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        analysisErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(analysisErrorMessage ?? "")
        }
        .alert(
            "转录失败",
            isPresented: Binding(
                get: { transcriptionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        transcriptionErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(transcriptionErrorMessage ?? "")
        }
        .alert(
            "删除录音",
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteRequest = nil
                    }
                }
            )
        ) {
            Button("删除", role: .destructive) {
                if let request = deleteRequest {
                    delete(request.item)
                    deleteRequest = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "确定要删除 %@ 吗？"), deleteRequest?.item.audioFileName ?? ""))
        }
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var recordingsList: some View {
        List {
            recordingsSearchField
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))

            if store.recordings.isEmpty {
                EmptyStateView(icon: "waveform.path.badge.plus", title: "暂无录音文件")
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if filteredRecordings.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "没有找到录音")
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredRecordings) { item in
                    recordingRow(for: item)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
    }

    private func recordingRow(for item: RecordingItem) -> some View {
        RecordingRow(
            item: item,
            isAnalyzing: analyzingRecordingID == item.id,
            showsIntelligence: store.intelligenceAvailability.isAvailable
        ) {
            openRecording(item)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .contextMenu {
            Button {
                HapticFeedback.play(.copy)
                UIPasteboard.general.string = store.transcriptText(for: item)
            } label: {
                Label("复制转录文本", systemImage: "doc.on.doc")
            }

            if store.intelligenceAvailability.isAvailable {
                Button {
                    analyze(item)
                } label: {
                    Label(item.intelligence == nil ? "生成标签和总结" : "重新分析", systemImage: "sparkles")
                }
                .disabled(analyzingRecordingID != nil)
            }

            Menu {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        retranscribe(item, language: language)
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language.id == item.languageID ? "checkmark" : "globe"
                        )
                    }
                }
            } label: {
                Label("重新转录", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(item.importStatus?.isFailed == false || transcriber.isRecording || transcriber.isPreparing)

            Button(role: .destructive) {
                requestDelete(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(item.importStatus?.isFailed == false)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if store.intelligenceAvailability.isAvailable {
                Button {
                    analyze(item)
                } label: {
                    Label("分析", systemImage: "sparkles")
                }
                .tint(AppTheme.info)
                .disabled(analyzingRecordingID != nil)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                requestDelete(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(AppTheme.danger)
            .disabled(item.importStatus?.isFailed == false)
        }
    }

    private var recordingsSearchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("搜索录音或转录", text: $searchText)
                .font(.redditSans(.subheadline))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFieldIsFocused)
                .onSubmit {
                    searchFieldIsFocused = false
                }

            if searchFieldIsFocused || !searchText.isEmpty {
                Button {
                    HapticFeedback.play(.menuSelection)
                    if searchText.isEmpty {
                        searchFieldIsFocused = false
                    } else {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func analyze(_ item: RecordingItem) {
        guard store.intelligenceAvailability.isAvailable else {
            HapticFeedback.play(.blocked)
            return
        }
        guard analyzingRecordingID == nil else {
            HapticFeedback.play(.blocked)
            return
        }

        analyzingRecordingID = item.id
        Task {
            HapticFeedback.play(.analysisStart)
            do {
                _ = try await store.analyzeIntelligence(for: item)
                HapticFeedback.play(.analysisComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            analyzingRecordingID = nil
        }
    }

    private func openRecording(_ item: RecordingItem) {
        selectedRecording = item
    }

    private func retranscribe(_ item: RecordingItem, language: TranscriptionLanguage) {
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        Task {
            HapticFeedback.play(.retranscribeStart)
            do {
                try await store.retranscribe(item, language: language)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func requestDelete(_ item: RecordingItem) {
        guard store.recording(withID: item.id) != nil else {
            HapticFeedback.play(.warning)
            return
        }
        deleteRequest = RecordingDeleteRequest(item: item)
        HapticFeedback.play(.deleteRequested)
    }

    private func delete(_ item: RecordingItem) {
        do {
            if selectedRecording?.id == item.id {
                selectedRecording = nil
            }
            if analyzingRecordingID == item.id {
                analyzingRecordingID = nil
            }
            try store.delete(item)
            HapticFeedback.play(.deleteConfirmed)
        } catch {
            deleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func recording(_ item: RecordingItem, matches query: String) -> Bool {
        store.normalizedSearchText(for: item).contains(query)
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.normalizedForRecordingSearch
    }
}

private struct RecordingDeleteRequest: Identifiable {
    let item: RecordingItem

    var id: RecordingItem.ID {
        item.id
    }
}

struct RecordingMapView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPoint: RecordingMapPoint?
    @State private var selectedRecording: RecordingItem?

    private var points: [RecordingMapPoint] {
        store.recordings.compactMap { item in
            guard let location = item.location else {
                return nil
            }
            return RecordingMapPoint(item: item, location: location)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if points.isEmpty {
                    EmptyStateView(icon: "map", title: "暂无带位置的录音")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.groupedBackground)
                } else {
                    Map(initialPosition: .region(mapRegion)) {
                        ForEach(points) { point in
                            Annotation(point.title, coordinate: point.coordinate) {
                                Button {
                                    HapticFeedback.play(.navigation)
                                    selectedPoint = point
                                } label: {
                                    Image(systemName: selectedPoint?.id == point.id ? "waveform.circle.fill" : "waveform.circle")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(.white, AppTheme.brand)
                                        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selectedPoint {
                    RecordingMapSelectionCard(point: selectedPoint) {
                        selectedRecording = selectedPoint.item
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("录音地图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $selectedRecording) { item in
                RecordingDetailView(item: item, store: store, transcriber: transcriber, player: player)
            }
        }
    }

    private var mapRegion: MKCoordinateRegion {
        guard let firstPoint = points.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }

        let latitudes = points.map(\.coordinate.latitude)
        let longitudes = points.map(\.coordinate.longitude)
        let minLatitude = latitudes.min() ?? firstPoint.coordinate.latitude
        let maxLatitude = latitudes.max() ?? firstPoint.coordinate.latitude
        let minLongitude = longitudes.min() ?? firstPoint.coordinate.longitude
        let maxLongitude = longitudes.max() ?? firstPoint.coordinate.longitude

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

private struct RecordingMapPoint: Identifiable {
    let id: RecordingItem.ID
    let item: RecordingItem
    let title: String
    let durationText: String
    let createdAt: Date
    let location: RecordingLocation
    let coordinate: CLLocationCoordinate2D

    init(item: RecordingItem, location: RecordingLocation) {
        id = item.id
        self.item = item
        title = (item.audioFileName as NSString).deletingPathExtension
        durationText = TranscriptionLine.formatTimestamp(Double(item.durationSeconds))
        createdAt = item.createdAt
        self.location = location
        coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }
}

private struct RecordingMapSelectionCard: View {
    let point: RecordingMapPoint
    let onOpen: () -> Void

    var body: some View {
        Button {
            HapticFeedback.play(.navigation)
            onOpen()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                        .fill(AppTheme.brand.opacity(0.14))
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.brand)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(point.title)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Label {
                            RecordingLocationNameText(location: point.location)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        Label(point.durationText, systemImage: "clock")
                    }
                    .font(.redditSans(.caption).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private extension RecordingLocation {
    var locationName: String? {
        placeName
    }

    var coordinateText: String {
        "\(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"
    }

    var cacheKey: String {
        "\(latitude.rounded(toPlaces: 4)),\(longitude.rounded(toPlaces: 4))"
    }
}

private struct RecordingLocationNameText: View {
    let location: RecordingLocation
    @State private var resolvedName: String?

    var body: some View {
        Text(resolvedName ?? location.locationName ?? location.coordinateText)
            .task(id: location.cacheKey) {
                guard location.locationName == nil else {
                    resolvedName = location.locationName
                    return
                }
                resolvedName = await RecordingLocationNameCache.shared.name(for: location)
            }
    }
}

@MainActor
private final class RecordingLocationNameCache {
    static let shared = RecordingLocationNameCache()

    private var namesByLocationKey: [String: String] = [:]

    func name(for location: RecordingLocation) async -> String {
        if let storedName = location.locationName {
            return storedName
        }

        let key = location.cacheKey
        if let cachedName = namesByLocationKey[key] {
            return cachedName
        }

        let fallback = location.coordinateText
        do {
            guard let request = MKReverseGeocodingRequest(location:
                CLLocation(latitude: location.latitude, longitude: location.longitude)
            ) else {
                namesByLocationKey[key] = fallback
                return fallback
            }
            let mapItems = try await request.mapItems
            let mapItem = mapItems.first
            let address = mapItem?.addressRepresentations
            let city = address?.cityName
                ?? address?.cityWithContext(.short)
                ?? mapItem?.name
            let country = address?.regionName
            let name = [city, country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let resolvedName = name.isEmpty ? fallback : name
            namesByLocationKey[key] = resolvedName
            return resolvedName
        } catch {
            namesByLocationKey[key] = fallback
            return fallback
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private struct RecordingRow: View {
    let item: RecordingItem
    let isAnalyzing: Bool
    let showsIntelligence: Bool
    let onOpen: () -> Void

    private var isTranscriptionRunning: Bool {
        item.importStatus?.isFailed == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                        .fill(AppTheme.brand.opacity(0.12))
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.brand)
                }
                .frame(width: 36, height: 36)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.audioFileName)
                        .font(.redditSans(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                trailingStatus
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticFeedback.play(.navigation)
                onOpen()
            }

            RecordingMetadataStrip(item: item)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticFeedback.play(.navigation)
                    onOpen()
                }

            if !item.combinedTags.isEmpty {
                FlowTags(tags: Array(item.combinedTags.prefix(4)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticFeedback.play(.navigation)
                        onOpen()
                    }
            }

            if let importStatus = item.importStatus {
                VStack(alignment: .leading, spacing: 6) {
                    if importStatus.isFailed {
                        Label(importStatus.message, systemImage: "exclamationmark.triangle")
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                            .lineLimit(2)
                    } else {
                        ProgressView(value: importStatus.progress)
                            .progressViewStyle(.linear)
                        Text(importStatus.message)
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(AppTheme.info)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticFeedback.play(.navigation)
                    onOpen()
                }
            } else if showsIntelligence && isAnalyzing {
                Label("正在分析", systemImage: "sparkles")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticFeedback.play(.navigation)
                        onOpen()
                    }
            } else if showsIntelligence, let intelligence = item.intelligence {
                RecordingIntelligencePreview(intelligence: intelligence)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticFeedback.play(.navigation)
                        onOpen()
                    }
            } else if !item.transcriptPreview.isEmpty {
                Text(item.transcriptPreview)
                    .font(.redditSans(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticFeedback.play(.navigation)
                        onOpen()
                    }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 7, y: 2)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if item.importStatus?.isFailed == true {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
                .frame(width: 26, height: 26)
        } else if isAnalyzing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
        } else if !isTranscriptionRunning {
            Text(TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }
}

private struct RecordingMetadataStrip: View {
    let item: RecordingItem

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                RecordingMetadataChip(systemImage: "globe", text: item.languageName)
                RecordingMetadataChip(systemImage: "text.alignleft", text: "\(item.lineCount)")
                if let location = item.location {
                    RecordingMetadataChip(systemImage: "mappin.and.ellipse") {
                        RecordingLocationNameText(location: location)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct RecordingMetadataChip<Content: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content

    init(systemImage: String, text: String) where Content == Text {
        self.systemImage = systemImage
        content = Text(text)
    }

    init(systemImage: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.secondary.opacity(0.09), in: Capsule())
    }
}

private struct RecordingIntelligencePreview: View {
    let intelligence: RecordingIntelligence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !intelligence.summary.isEmpty {
                Text(intelligence.summary)
                    .font(.redditSans(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.redditSans(.caption2, weight: .semibold))
                        .foregroundStyle(AppTheme.info)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(AppTheme.info.opacity(0.12), in: Capsule())
                }
            }
        }
        .scrollClipDisabled()
    }
}

struct RecordingDetailView: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var isAnalyzing = false
    @State private var analysisErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var audioFileInfo: RecordingAudioFileInfo?
    @State private var audioFileInfoError: String?
    @State private var isShowingAudioFileInfo = false
    @StateObject private var editLocationProvider = RecordingEditLocationProvider()
    @State private var isShowingRecordingEditSheet = false
    @State private var editRecordingName = ""
    @State private var editRecordingTags: [String] = []
    @State private var editRecordingIncludesLocation = false
    @State private var isSavingRecordingEdit = false
    @State private var renameErrorMessage: String?
    @State private var cachedTranscriptLines: [StoredTranscriptLine] = []
    @State private var scrubbedPlaybackTime: TimeInterval?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var selectedTranslationLanguage: TranscriptionLanguage?
    @State private var translatedTranscriptByLineID: [StoredTranscriptLine.ID: String] = [:]
    @State private var translatedTranscriptCache: [String: [StoredTranscriptLine.ID: String]] = [:]
    @State private var isTranslatingTranscript = false
    @State private var translationErrorMessage: String?

    private var currentItem: RecordingItem {
        store.recording(withID: item.id) ?? item
    }

    private var transcriptCacheIdentifier: String {
        [
            currentItem.id.uuidString,
            currentItem.transcriptFileName,
            "\(currentItem.lineCount)",
            "\(currentItem.transcriptPreview.hashValue)",
            "\(currentItem.importStatus == nil)"
        ].joined(separator: "-")
    }

    private var isTranscriptionRunning: Bool {
        currentItem.importStatus?.isFailed == false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.intelligenceAvailability.isAvailable {
                    intelligenceCard
                }
                transcript
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            playerCard
                .frame(maxWidth: 390)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 6)
        }
        .background(AppTheme.groupedBackground)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(currentItem.audioFileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("返回")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                detailActionsMenu
            }
        }
        .sheet(isPresented: $isShowingAudioFileInfo) {
            NavigationStack {
                ScrollView {
                    audioParametersCard
                        .padding()
                }
                .background(AppTheme.groupedBackground.ignoresSafeArea())
                .navigationTitle("音频参数")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            isShowingAudioFileInfo = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingRecordingEditSheet) {
            RecordingEditSheet(
                item: currentItem,
                recordingName: $editRecordingName,
                tags: $editRecordingTags,
                includesLocation: $editRecordingIncludesLocation,
                locationProvider: editLocationProvider,
                isSaving: isSavingRecordingEdit,
                onSave: saveRecordingEdit,
                onCancel: {
                    isShowingRecordingEditSheet = false
                }
            )
            .interactiveDismissDisabled(isSavingRecordingEdit)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onChange(of: editRecordingIncludesLocation) { _, includesLocation in
                if includesLocation, currentItem.location == nil {
                    editLocationProvider.requestLocation()
                } else if !includesLocation {
                    editLocationProvider.reset()
                }
            }
        }
        .onAppear {
            Task {
                store.refreshIntelligenceAvailability()
                await store.normalizeAudioIfNeeded(
                    for: currentItem,
                    loudnessProcessingEnabled: transcriber.isLoudnessProcessingEnabled
                )
                await refreshAudioFileInfo()
                player.load(item: currentItem, url: store.audioURL(for: currentItem))
            }
        }
        .task(id: transcriptCacheIdentifier) {
            await refreshTranscriptCache()
        }
        .translationTask(translationConfiguration) { session in
            await translateTranscript(using: session)
        }
        .onDisappear {
            player.unload()
        }
        .alert(
            "分析失败",
            isPresented: Binding(
                get: { analysisErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        analysisErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(analysisErrorMessage ?? "")
        }
        .alert(
            "删除录音",
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteRequest = nil
                    }
                }
            )
        ) {
            Button("删除", role: .destructive) {
                if let request = deleteRequest {
                    deleteCurrentItem(request.item)
                    deleteRequest = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "确定要删除 %@ 吗？"), deleteRequest?.item.audioFileName ?? ""))
        }
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(
            "重命名失败",
            isPresented: Binding(
                get: { renameErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        renameErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(renameErrorMessage ?? "")
        }
    }

    private var detailActionsMenu: some View {
        let transcriptText = store.transcriptText(for: currentItem)

        return Menu {
            Button {
                prepareRecordingEditSheet()
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            .disabled(isTranscriptionRunning)

            Button {
                isShowingAudioFileInfo = true
            } label: {
                Label("音频参数", systemImage: "info.circle")
            }

            Divider()

            Menu {
                ShareLink(item: store.audioURL(for: currentItem)) {
                    Label("分享音频", systemImage: "waveform")
                }

                ShareLink(item: transcriptText) {
                    Label("分享转录文字", systemImage: "text.alignleft")
                }
                .disabled(transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }

            Menu {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        retranscribeCurrentItem(language: language)
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language.id == currentItem.languageID ? "checkmark" : "globe"
                        )
                    }
                }
            } label: {
                Label("重新转录", systemImage: isTranscriptionRunning ? "hourglass" : "arrow.triangle.2.circlepath")
            }
            .disabled(isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)

            Button {
                HapticFeedback.play(.copy)
                UIPasteboard.general.string = transcriptText
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    copied = false
                }
            } label: {
                Label(copied ? "已复制" : "复制转录文本", systemImage: copied ? "checkmark" : "doc.on.doc")
            }

            if store.intelligenceAvailability.isAvailable {
                Button {
                    analyzeCurrentItem()
                } label: {
                    Label("智能分析", systemImage: isAnalyzing ? "hourglass" : "sparkles")
                }
                .disabled(isAnalyzing)
            }

            Divider()

            Button(role: .destructive) {
                HapticFeedback.play(.deleteRequested)
                deleteRequest = RecordingDeleteRequest(item: currentItem)
            } label: {
                Label("删除录音", systemImage: "trash")
            }
            .disabled(isTranscriptionRunning)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("更多")
    }

    private var header: some View {
        let item = currentItem

        return VStack(alignment: .leading, spacing: 10) {
            Label(item.audioFileName, systemImage: "waveform")
                .font(.redditSans(.headline, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: 10) {
                RecordingInfoPill(icon: "calendar", text: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                RecordingInfoPill(icon: "clock", text: TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                RecordingInfoPill(icon: "globe", text: item.languageName)
            }

            if !item.combinedTags.isEmpty {
                FlowTags(tags: item.combinedTags)
            }

            if let location = item.location {
                Label {
                    RecordingLocationNameText(location: location)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var intelligenceCard: some View {
        let item = currentItem

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("智能摘要", systemImage: "sparkles")
                    .font(.redditSans(.headline))

                Spacer(minLength: 8)

                Button {
                    analyzeCurrentItem()
                } label: {
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(item.intelligence == nil ? "分析" : "重新分析")
                            .font(.redditSans(.caption, weight: .semibold))
                    }
                }
                .disabled(isAnalyzing)
                .buttonStyle(.bordered)
            }

            if isAnalyzing {
                Label("正在分析", systemImage: "sparkles")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
            } else if let intelligence = item.intelligence {
                if !intelligence.summary.isEmpty {
                    Text(intelligence.summary)
                        .font(.redditSans(.body))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(intelligence.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.redditSans(.caption2))
                    .foregroundStyle(.secondary)
            } else {
                EmptyStateView(icon: "sparkles", title: "暂无摘要")
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var audioParametersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("音频参数", systemImage: "info.circle")
                .font(.redditSans(.headline))

            if let audioFileInfo {
                VStack(spacing: 0) {
                    RecordingAudioParameterRow(icon: "waveform", title: "采样率", value: audioFileInfo.fileSampleRateText)
                    RecordingAudioParameterRow(icon: "speaker.wave.2", title: "声道", value: audioFileInfo.channelLayoutText)
                    RecordingAudioParameterRow(icon: "cpu", title: "编码", value: audioFileInfo.fileFormatText)
                    RecordingAudioParameterRow(icon: "slider.horizontal.3", title: "处理格式", value: audioFileInfo.processingFormatText)
                    RecordingAudioParameterRow(icon: "number", title: "PCM 位深", value: audioFileInfo.bitDepthText)
                    RecordingAudioParameterRow(icon: "timer", title: "音频时长", value: audioFileInfo.durationText)
                    RecordingAudioParameterRow(icon: "square.stack.3d.up", title: "音频帧数", value: audioFileInfo.frameCountText)
                    RecordingAudioParameterRow(icon: "doc", title: "文件大小", value: audioFileInfo.fileSizeText)
                    RecordingAudioParameterRow(icon: "checkmark.seal", title: "音量处理", value: audioFileInfo.normalizationText, showsDivider: false)
                }
            } else if let audioFileInfoError {
                Label(audioFileInfoError, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("正在读取音频参数", systemImage: "waveform")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var playerCard: some View {
        let displayedTime = scrubbedPlaybackTime ?? player.currentTime
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(TranscriptionLine.formatTimestamp(displayedTime))
                    .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(minWidth: 50, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { scrubbedPlaybackTime ?? player.currentTime },
                        set: { scrubbedPlaybackTime = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { isEditing in
                        if !isEditing, let scrubbedPlaybackTime {
                            player.seek(to: scrubbedPlaybackTime)
                            self.scrubbedPlaybackTime = nil
                        }
                    }
                )
                .disabled(!player.isLoaded)
                .frame(maxWidth: .infinity)

                Text(TranscriptionLine.formatTimestamp(player.duration))
                    .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            ZStack {
                HStack(spacing: 8) {
                    PlaybackRoundButton(systemImage: "gobackward.5", title: "-5s") {
                        HapticFeedback.play(.timelineSeek)
                        scrubbedPlaybackTime = nil
                        player.skip(by: -5)
                    }
                    .disabled(!player.isLoaded)

                    PlaybackRoundButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill", title: player.isPlaying ? "暂停" : "播放", isPrimary: true) {
                        HapticFeedback.play(.playbackToggle)
                        player.togglePlayback()
                    }
                    .disabled(!player.isLoaded)

                    PlaybackRoundButton(systemImage: "goforward.5", title: "+5s") {
                        HapticFeedback.play(.timelineSeek)
                        scrubbedPlaybackTime = nil
                        player.skip(by: 5)
                    }
                    .disabled(!player.isLoaded)
                }
                .frame(width: 168)

                HStack {
                    Spacer(minLength: 0)
                    playbackSpeedMenu
                }
            }
            .frame(height: 58)

            if let errorText = player.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(AppTheme.brand.opacity(0.08)).interactive(), in: shape)
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
    }

    private var playbackSpeedMenu: some View {
        Menu {
            ForEach(RecordingPlaybackController.availablePlaybackRates, id: \.self) { rate in
                Button {
                    HapticFeedback.play(.menuSelection)
                    player.setPlaybackRate(rate)
                } label: {
                    Label(
                        RecordingPlaybackController.playbackRateLabel(rate),
                        systemImage: player.playbackRate == rate ? "checkmark" : "speedometer"
                    )
                }
            }
        } label: {
            Text(RecordingPlaybackController.playbackRateLabel(player.playbackRate))
                .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
                .lineLimit(1)
            .foregroundStyle(AppTheme.brand)
            .padding(.horizontal, 7)
            .frame(height: 24)
        }
        .buttonStyle(.glass)
        .disabled(!player.isLoaded)
    }

    private var transcript: some View {
        let item = currentItem
        let lines = cachedTranscriptLines
        let currentLineID = StoredTranscriptLine.currentLineID(in: lines, time: player.currentTime)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("转录文本", systemImage: "text.alignleft")
                    .font(.redditSans(.headline))

                Spacer(minLength: 8)

                transcriptTranslationMenu
                    .disabled(lines.isEmpty || isTranscriptionRunning)
            }

            transcriptTranslationStatus

            if let importStatus = item.importStatus {
                RecordingImportStatusDetail(status: importStatus)
            }

            if lines.isEmpty {
                if item.importStatus == nil {
                    EmptyStateView(icon: "text.badge.xmark", title: "暂无文本")
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        StoredTranscriptLineRow(
                            line: line,
                            translatedText: translatedTranscriptByLineID[line.id],
                            isShowingTranslation: isTranslatingTranscript && selectedTranslationLanguage != nil && translatedTranscriptByLineID[line.id] == nil,
                            isCurrent: line.id == currentLineID
                        ) {
                            HapticFeedback.play(.timelineSeek)
                            scrubbedPlaybackTime = nil
                            player.seek(to: line.startSeconds)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var transcriptTranslationMenu: some View {
        Menu {
            Button {
                clearTranscriptTranslation()
            } label: {
                Label("原文", systemImage: selectedTranslationLanguage == nil ? "checkmark" : "text.alignleft")
            }

            Divider()

            ForEach(transcriptTranslationLanguages) { language in
                Button {
                    requestTranscriptTranslation(to: language)
                } label: {
                    Label(
                        language.displayName,
                        systemImage: selectedTranslationLanguage?.id == language.id ? "checkmark" : "translate"
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .semibold))
                Text(selectedTranslationLanguage?.shortName ?? String(localized: "翻译"))
                    .font(.redditSans(.caption, weight: .bold))
            }
            .foregroundStyle(selectedTranslationLanguage == nil ? AppTheme.info : AppTheme.brand)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background((selectedTranslationLanguage == nil ? AppTheme.info : AppTheme.brand).opacity(0.11), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var transcriptTranslationStatus: some View {
        if let selectedTranslationLanguage {
            HStack(spacing: 8) {
                if isTranslatingTranscript {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: translationErrorMessage == nil ? "translate" : "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(translationErrorMessage ?? String(format: String(localized: "翻译成 %@"), selectedTranslationLanguage.displayName))
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(translationErrorMessage == nil ? .secondary : AppTheme.warning)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
        }
    }

    private var transcriptTranslationLanguages: [TranscriptionLanguage] {
        transcriber.supportedLanguages.filter { language in
            !Self.sameBaseLanguage(language.id, currentItem.languageID)
        }
    }

    private func analyzeCurrentItem() {
        guard store.intelligenceAvailability.isAvailable else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !isAnalyzing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        if selectedTranslationLanguage != nil, isTranslatingTranscript {
            analysisErrorMessage = String(localized: "请等待翻译完成后再生成智能摘要")
            HapticFeedback.play(.blocked)
            return
        }
        let translatedAnalysisInput = translatedTranscriptAnalysisInput()
        if selectedTranslationLanguage != nil, translatedAnalysisInput == nil {
            analysisErrorMessage = String(localized: "没有可用于智能摘要的翻译文本")
            HapticFeedback.play(.blocked)
            return
        }

        isAnalyzing = true
        HapticFeedback.play(.analysisStart)
        Task {
            do {
                _ = try await store.analyzeIntelligence(
                    for: item,
                    transcriptOverride: translatedAnalysisInput?.transcript,
                    languageNameOverride: translatedAnalysisInput?.languageName
                )
                HapticFeedback.play(.analysisComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isAnalyzing = false
        }
    }

    private func translatedTranscriptAnalysisInput() -> (transcript: String, languageName: String)? {
        guard let selectedTranslationLanguage else {
            return nil
        }

        let translatedLineCount = cachedTranscriptLines.reduce(0) { count, line in
            let translatedText = translatedTranscriptByLineID[line.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return translatedText?.isEmpty == false ? count + 1 : count
        }
        guard translatedLineCount > 0 else {
            return nil
        }

        let transcript = cachedTranscriptLines
            .map { line in
                translatedTranscriptByLineID[line.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !transcript.isEmpty else {
            return nil
        }

        return (transcript, selectedTranslationLanguage.displayName)
    }

    private func retranscribeCurrentItem(language: TranscriptionLanguage) {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        Task {
            HapticFeedback.play(.retranscribeStart)
            do {
                try await store.retranscribe(item, language: language)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func refreshAudioFileInfo() async {
        let item = currentItem
        let url = store.audioURL(for: item)
        let audioNormalizedAt = item.audioNormalizedAt
        let audioNormalizationVersion = item.audioNormalizationVersion
        do {
            let info = try await Task.detached(priority: .utility) {
                try RecordingAudioFileInfo(
                    url: url,
                    audioNormalizedAt: audioNormalizedAt,
                    audioNormalizationVersion: audioNormalizationVersion
                )
            }.value
            audioFileInfo = info
            audioFileInfoError = nil
        } catch {
            audioFileInfo = nil
            audioFileInfoError = String(format: String(localized: "无法读取音频参数: %@"), error.localizedDescription)
        }
    }

    private func refreshTranscriptCache() async {
        let item = currentItem
        let transcriptURL = store.transcriptURL(for: item)
        let lines = await Task.detached(priority: .utility) {
            let text = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
            return StoredTranscriptLine.parse(text)
        }.value

        guard currentItem.id == item.id,
              currentItem.transcriptFileName == item.transcriptFileName else {
            return
        }

        cachedTranscriptLines = lines
        translatedTranscriptByLineID = [:]
        translatedTranscriptCache = translatedTranscriptCache.filter { key, _ in
            key.hasPrefix(transcriptTranslationCachePrefix)
        }

        if let selectedTranslationLanguage {
            requestTranscriptTranslation(to: selectedTranslationLanguage)
        }
    }

    private func requestTranscriptTranslation(to language: TranscriptionLanguage) {
        guard !cachedTranscriptLines.isEmpty else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !Self.sameBaseLanguage(language.id, currentItem.languageID) else {
            clearTranscriptTranslation()
            return
        }

        HapticFeedback.play(.menuSelection)
        selectedTranslationLanguage = language
        translationErrorMessage = nil

        let cacheKey = transcriptTranslationCacheKey(for: language)
        if let cachedTranslation = translatedTranscriptCache[cacheKey] {
            translatedTranscriptByLineID = cachedTranslation
            isTranslatingTranscript = false
            return
        }

        translatedTranscriptByLineID = [:]
        isTranslatingTranscript = true

        let sourceLanguage = Self.localeLanguage(for: currentItem.languageID)
        let targetLanguage = Self.localeLanguage(for: language.id)
        let nextConfiguration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )

        if var existingConfiguration = translationConfiguration,
           existingConfiguration == nextConfiguration {
            existingConfiguration.invalidate()
            translationConfiguration = existingConfiguration
        } else {
            translationConfiguration = nextConfiguration
        }
    }

    private func clearTranscriptTranslation() {
        HapticFeedback.play(.menuSelection)
        selectedTranslationLanguage = nil
        translatedTranscriptByLineID = [:]
        translationErrorMessage = nil
        isTranslatingTranscript = false
        translationConfiguration = nil
    }

    private func translateTranscript(using session: TranslationSession) async {
        guard let targetTranslationLanguage = selectedTranslationLanguage,
              !cachedTranscriptLines.isEmpty else {
            isTranslatingTranscript = false
            return
        }

        let cacheKey = transcriptTranslationCacheKey(for: targetTranslationLanguage)
        if let cachedTranslation = translatedTranscriptCache[cacheKey] {
            translatedTranscriptByLineID = cachedTranslation
            isTranslatingTranscript = false
            return
        }

        let lines = cachedTranscriptLines
        let targetLanguageID = targetTranslationLanguage.id
        let requests = lines.map { line in
            TranslationSession.Request(sourceText: line.text, clientIdentifier: line.id)
        }

        do {
            try await session.prepareTranslation()
            var translatedByLineID: [StoredTranscriptLine.ID: String] = [:]
            for try await response in session.translate(batch: requests) {
                guard let currentTargetLanguage = selectedTranslationLanguage,
                      currentTargetLanguage.id == targetLanguageID,
                      transcriptTranslationCacheKey(for: currentTargetLanguage) == cacheKey,
                      let lineID = response.clientIdentifier else {
                    continue
                }

                let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translatedText.isEmpty else {
                    continue
                }

                translatedByLineID[lineID] = translatedText
                translatedTranscriptByLineID = translatedByLineID
            }

            guard selectedTranslationLanguage?.id == targetLanguageID else {
                return
            }

            translatedTranscriptCache[cacheKey] = translatedByLineID
            translatedTranscriptByLineID = translatedByLineID
            isTranslatingTranscript = false
            translationErrorMessage = nil
        } catch {
            guard selectedTranslationLanguage?.id == targetLanguageID else {
                return
            }

            translatedTranscriptByLineID = [:]
            isTranslatingTranscript = false
            translationErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private var transcriptTranslationCachePrefix: String {
        [
            currentItem.id.uuidString,
            currentItem.transcriptFileName,
            "\(currentItem.lineCount)",
            "\(currentItem.transcriptPreview.hashValue)"
        ].joined(separator: "|")
    }

    private func transcriptTranslationCacheKey(for language: TranscriptionLanguage) -> String {
        "\(transcriptTranslationCachePrefix)|\(language.id)"
    }

    private static func localeLanguage(for identifier: String) -> Locale.Language? {
        let language = Locale(identifier: identifier).language
        guard language.languageCode != nil else {
            return nil
        }
        return language
    }

    private static func sameBaseLanguage(_ firstIdentifier: String, _ secondIdentifier: String) -> Bool {
        let firstLanguage = Locale(identifier: firstIdentifier).language
        let secondLanguage = Locale(identifier: secondIdentifier).language
        let firstCode = firstLanguage.languageCode?.identifier
        let secondCode = secondLanguage.languageCode?.identifier
        guard let firstCode, let secondCode else {
            return firstIdentifier == secondIdentifier
        }
        guard firstCode == secondCode else {
            return false
        }

        let firstScript = firstLanguage.script?.identifier
        let secondScript = secondLanguage.script?.identifier
        if firstScript != nil || secondScript != nil {
            return firstScript == secondScript
        }

        return true
    }

    private func prepareRecordingEditSheet() {
        let item = currentItem
        editRecordingName = (item.audioFileName as NSString).deletingPathExtension
        editRecordingTags = item.combinedTags
        editRecordingIncludesLocation = item.location != nil
        editLocationProvider.reset()
        isShowingRecordingEditSheet = true
        HapticFeedback.play(.menuSelection)
    }

    private func saveRecordingEdit() {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !isSavingRecordingEdit else {
            return
        }

        isSavingRecordingEdit = true
        do {
            let location = editRecordingIncludesLocation
                ? (editLocationProvider.recordingLocation ?? currentItem.location)
                : nil
            let updatedItem = try store.updateDetails(
                for: currentItem,
                proposedName: editRecordingName,
                manualTags: editRecordingTags,
                location: location
            )
            HapticFeedback.play(.primaryAction)
            isShowingRecordingEditSheet = false
            player.load(item: updatedItem, url: store.audioURL(for: updatedItem))
            Task {
                await refreshAudioFileInfo()
                await refreshTranscriptCache()
            }
        } catch {
            renameErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
        isSavingRecordingEdit = false
    }

    private func deleteCurrentItem(_ item: RecordingItem) {
        do {
            player.unload()
            try store.delete(item)
            HapticFeedback.play(.deleteConfirmed)
            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        } catch {
            deleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }
}

private struct RecordingEditSheet: View {
    let item: RecordingItem
    @Binding var recordingName: String
    @Binding var tags: [String]
    @Binding var includesLocation: Bool
    @ObservedObject var locationProvider: RecordingEditLocationProvider
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameSection
                    tagsEntry
                    durationRow
                    locationSection
                }
                .padding(16)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle("编辑录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        onCancel()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("保存")
                                .font(.redditSans(.subheadline, weight: .semibold))
                        }
                    }
                    .disabled(isSaving || recordingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("录音名称", systemImage: "pencil")
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("录音名称", text: $recordingName)
                .font(.redditSans(.headline, weight: .semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        }
        .recordingEditSectionSurface()
    }

    private var tagsEntry: some View {
        NavigationLink {
            RecordingMetadataTagsEditor(tags: $tags)
        } label: {
            HStack(spacing: 12) {
                Label("标签", systemImage: "tag")
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(tags.isEmpty ? String(localized: "未添加") : "\(tags.count)")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .recordingEditSectionSurface()
    }

    private var durationRow: some View {
        HStack(spacing: 12) {
            Label("音频时长", systemImage: "clock")
                .font(.redditSans(.subheadline, weight: .semibold))
            Spacer()
            Text(TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                .font(.redditSans(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .recordingEditSectionSurface()
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $includesLocation) {
                Label("添加地理位置", systemImage: "location")
                    .font(.redditSans(.subheadline, weight: .semibold))
            }
            .tint(AppTheme.brand)

            if includesLocation {
                RecordingEditLocationPreview(
                    existingLocation: item.location,
                    locationProvider: locationProvider
                )
            }
        }
        .recordingEditSectionSurface()
    }
}

private struct RecordingMetadataTagsEditor: View {
    @Binding var tags: [String]
    @State private var newTag = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("添加标签", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        addTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(normalizedTag.isEmpty)
                }
            }

            Section {
                if tags.isEmpty {
                    Text("暂无标签")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                    }
                    .onDelete { offsets in
                        tags.remove(atOffsets: offsets)
                    }
                }
            }
        }
        .navigationTitle("标签")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var normalizedTag: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTag() {
        let tag = normalizedTag
        guard !tag.isEmpty else {
            return
        }

        if !tags.contains(where: { $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            tags.append(tag)
        }
        newTag = ""
        HapticFeedback.play(.primaryAction)
    }
}

private struct RecordingEditLocationPreview: View {
    let existingLocation: RecordingLocation?
    @ObservedObject var locationProvider: RecordingEditLocationProvider

    private var displayedLocation: RecordingLocation? {
        locationProvider.recordingLocation ?? existingLocation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let displayedLocation {
                let coordinate = CLLocationCoordinate2D(
                    latitude: displayedLocation.latitude,
                    longitude: displayedLocation.longitude
                )

                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                ) {
                    Marker(displayedLocation.placeName ?? String(localized: "当前位置"), coordinate: coordinate)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))

                Label {
                    RecordingLocationNameText(location: displayedLocation)
                } icon: {
                    Image(systemName: "building.2")
                }
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(displayedLocation.coordinateText)
                        .monospacedDigit()
                    Spacer()
                    Button("更新当前位置") {
                        locationProvider.requestLocation()
                    }
                    .font(.redditSans(.caption, weight: .semibold))
                }
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
            } else if locationProvider.isDenied {
                Label("位置权限被拒绝", systemImage: "location.slash")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
            } else if let errorText = locationProvider.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在获取位置")
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .task {
                    locationProvider.requestLocation()
                }
            }
        }
    }
}

@MainActor
private final class RecordingEditLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var placeName: String?
    @Published private(set) var errorText: String?

    private let manager = CLLocationManager()
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?
    private var city: String?
    private var country: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var recordingLocation: RecordingLocation? {
        guard let latestLocation else {
            return nil
        }

        return RecordingLocation(
            latitude: latestLocation.coordinate.latitude,
            longitude: latestLocation.coordinate.longitude,
            horizontalAccuracy: latestLocation.horizontalAccuracy >= 0 ? latestLocation.horizontalAccuracy : nil,
            capturedAt: Date(),
            city: city,
            country: country
        )
    }

    func reset() {
        latestLocation = nil
        placeName = nil
        city = nil
        country = nil
        errorText = nil
        reverseGeocodingRequest?.cancel()
        reverseGeocodingRequest = nil
    }

    func requestLocation() {
        errorText = nil
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            errorText = String(localized: "位置权限被拒绝")
        @unknown default:
            errorText = String(localized: "无法获取位置")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                return
            }
            latestLocation = location
            errorText = nil
            await resolvePlaceName(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorText = error.localizedDescription
        }
    }

    private func resolvePlaceName(for location: CLLocation) async {
        placeName = nil
        city = nil
        country = nil
        reverseGeocodingRequest?.cancel()

        do {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                return
            }
            reverseGeocodingRequest = request
            let mapItems = try await request.mapItems
            let mapItem = mapItems.first
            guard reverseGeocodingRequest === request else {
                return
            }

            let address = mapItem?.addressRepresentations
            let resolvedCity = address?.cityName
                ?? address?.cityWithContext(.short)
                ?? mapItem?.name
            let resolvedCountry = address?.regionName
            city = resolvedCity
            country = resolvedCountry
            placeName = [resolvedCity, resolvedCountry]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        } catch {
            if reverseGeocodingRequest?.isCancelled != true {
                placeName = nil
            }
        }
    }
}

private extension View {
    func recordingEditSectionSurface() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
    }
}

private struct RecordingImportStatusDetail: View {
    let status: RecordingImportStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.isFailed {
                Label(status.message, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView(value: status.progress)
                    .progressViewStyle(.linear)
                Label(status.message, systemImage: "waveform")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((status.isFailed ? AppTheme.warning : AppTheme.info).opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
    }
}

private struct RecordingAudioFileInfo: Equatable, Sendable {
    var fileSampleRate: Double
    var processingSampleRate: Double
    var channelCount: UInt32
    var processingChannelCount: UInt32
    var fileFormatName: String
    var fileCommonFormatName: String
    var processingCommonFormatName: String
    var bitDepth: Int?
    var isInterleaved: Bool
    var frameCount: AVAudioFramePosition
    var durationSeconds: TimeInterval
    var fileSize: Int64?
    var audioNormalizedAt: Date?
    var audioNormalizationVersion: Int?

    init(url: URL, audioNormalizedAt: Date?, audioNormalizationVersion: Int?) throws {
        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.fileFormat
        let processingFormat = file.processingFormat
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])

        self.fileSampleRate = fileFormat.sampleRate
        self.processingSampleRate = processingFormat.sampleRate
        self.channelCount = fileFormat.channelCount
        self.processingChannelCount = processingFormat.channelCount
        self.fileFormatName = Self.formatName(from: fileFormat.settings[AVFormatIDKey])
        self.fileCommonFormatName = Self.commonFormatName(fileFormat.commonFormat)
        self.processingCommonFormatName = Self.commonFormatName(processingFormat.commonFormat)
        self.bitDepth = Self.bitDepth(settings: fileFormat.settings, format: fileFormat)
        self.isInterleaved = fileFormat.isInterleaved
        self.frameCount = file.length
        self.durationSeconds = processingFormat.sampleRate > 0 ? Double(file.length) / processingFormat.sampleRate : 0
        self.fileSize = resourceValues?.fileSize.map { Int64($0) }
        self.audioNormalizedAt = audioNormalizedAt
        self.audioNormalizationVersion = audioNormalizationVersion
    }

    var fileSampleRateText: String {
        Self.sampleRateText(fileSampleRate)
    }

    var channelLayoutText: String {
        switch channelCount {
        case 1:
            return String(localized: "单声道")
        case 2:
            return String(localized: "立体声")
        default:
            return String(format: String(localized: "%d 声道"), Int(channelCount))
        }
    }

    var fileFormatText: String {
        if bitDepth == nil {
            return fileFormatName
        }
        return "\(fileFormatName) / \(fileCommonFormatName)"
    }

    var processingFormatText: String {
        let channelText: String
        switch processingChannelCount {
        case 1:
            channelText = String(localized: "单声道")
        case 2:
            channelText = String(localized: "立体声")
        default:
            channelText = String(format: String(localized: "%d 声道"), Int(processingChannelCount))
        }

        return "\(Self.sampleRateText(processingSampleRate)) / \(channelText) / \(processingCommonFormatName)"
    }

    var bitDepthText: String {
        guard let bitDepth else {
            return String(localized: "不适用")
        }
        return String(format: String(localized: "%d-bit"), bitDepth)
    }

    var durationText: String {
        TranscriptionLine.formatTimestamp(durationSeconds)
    }

    var frameCountText: String {
        Self.integerFormatter.string(from: NSNumber(value: frameCount)) ?? "\(frameCount)"
    }

    var fileSizeText: String {
        guard let fileSize else {
            return String(localized: "未知")
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var normalizationText: String {
        guard let audioNormalizationVersion else {
            return String(localized: "未归一化")
        }

        if let audioNormalizedAt {
            return String(
                format: String(localized: "已归一化 v%d · %@"),
                audioNormalizationVersion,
                audioNormalizedAt.formatted(date: .abbreviated, time: .shortened)
            )
        }

        return String(format: String(localized: "已归一化 v%d"), audioNormalizationVersion)
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func sampleRateText(_ sampleRate: Double) -> String {
        guard sampleRate.isFinite, sampleRate > 0 else {
            return String(localized: "未知")
        }

        let kilohertz = sampleRate / 1_000
        if kilohertz.rounded() == kilohertz {
            return "\(Int(kilohertz)) kHz"
        }
        return String(format: "%.1f kHz", kilohertz)
    }

    private static func commonFormatName(_ commonFormat: AVAudioCommonFormat) -> String {
        switch commonFormat {
        case .pcmFormatFloat32:
            return "Float32 PCM"
        case .pcmFormatFloat64:
            return "Float64 PCM"
        case .pcmFormatInt16:
            return "Int16 PCM"
        case .pcmFormatInt32:
            return "Int32 PCM"
        case .otherFormat:
            return String(localized: "压缩或其他格式")
        @unknown default:
            return String(localized: "未知")
        }
    }

    private static func formatName(from value: Any?) -> String {
        guard let formatID = audioFormatID(from: value) else {
            return String(localized: "未知")
        }

        switch fourCharacterCode(formatID) {
        case "lpcm":
            return "Linear PCM"
        case "aac ":
            return "AAC"
        case "alac":
            return "Apple Lossless"
        case "mp4a":
            return "MPEG-4 Audio"
        case "caff":
            return "CAF"
        default:
            return fourCharacterCode(formatID)
        }
    }

    private static func audioFormatID(from value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int {
            return UInt32(value)
        }
        if let value = value as? NSNumber {
            return value.uint32Value
        }
        return nil
    }

    private static func intValue(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func bitDepth(settings: [String: Any], format: AVAudioFormat) -> Int? {
        if let explicitBitDepth = intValue(from: settings[AVLinearPCMBitDepthKey]) {
            return explicitBitDepth
        }

        guard audioFormatID(from: settings[AVFormatIDKey]) == kAudioFormatLinearPCM else {
            return nil
        }

        switch format.commonFormat {
        case .pcmFormatFloat32, .pcmFormatInt32:
            return 32
        case .pcmFormatFloat64:
            return 64
        case .pcmFormatInt16:
            return 16
        default:
            return nil
        }
    }

    private static func fourCharacterCode(_ rawValue: UInt32) -> String {
        let bytes = [
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        ]

        guard bytes.allSatisfy({ (32...126).contains($0) }) else {
            return "0x\(String(rawValue, radix: 16, uppercase: true))"
        }
        return String(bytes: bytes, encoding: .ascii) ?? "0x\(String(rawValue, radix: 16, uppercase: true))"
    }
}

private struct PlaybackRoundButton: View {
    let systemImage: String
    let title: LocalizedStringKey
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isPrimary ? 22 : 18, weight: .semibold))
                .frame(width: isPrimary ? 58 : 46, height: isPrimary ? 58 : 46)
                .foregroundStyle(isPrimary ? .white : AppTheme.brand)
                .background(
                    isPrimary ? AppTheme.brand : AppTheme.brand.opacity(0.11),
                    in: Circle()
                )
        }
        .buttonStyle(PlaybackRoundButtonStyle())
        .accessibilityLabel(title)
    }
}

private struct PlaybackRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.snappy(duration: 0.12, extraBounce: 0), value: configuration.isPressed)
    }
}

private struct RecordingAudioParameterRow: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
                    .frame(width: 18)

                Text(title)
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(value)
                    .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 8)

            if showsDivider {
                Divider()
                    .padding(.leading, 28)
            }
        }
    }
}

private struct StoredTranscriptLine: Identifiable, Hashable {
    let id: String
    let startSeconds: TimeInterval
    let timeText: String
    let text: String

    static func parse(_ transcript: String) -> [StoredTranscriptLine] {
        let lines = transcript
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { offset, rawLine -> StoredTranscriptLine? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("["),
                      let closingBracket = line.firstIndex(of: "]") else {
                    return nil
                }

                let timeText = String(line[line.index(after: line.startIndex)..<closingBracket])
                let textStart = line.index(after: closingBracket)
                let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                guard let seconds = parseSeconds(timeText), !text.isEmpty else {
                    return nil
                }

                return StoredTranscriptLine(
                    id: "\(offset)-\(timeText)",
                    startSeconds: seconds,
                    timeText: timeText,
                    text: text
                )
            }

        return lines.sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.id < $1.id
            }
            return $0.startSeconds < $1.startSeconds
        }
    }

    static func currentLineID(in lines: [StoredTranscriptLine], time: TimeInterval) -> StoredTranscriptLine.ID? {
        guard !lines.isEmpty else {
            return nil
        }

        var lowerBound = 0
        var upperBound = lines.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if lines[midIndex].startSeconds <= time {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }

        let index = lowerBound - 1
        guard lines.indices.contains(index) else {
            return nil
        }
        return lines[index].id
    }

    private static func parseSeconds(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              let centiseconds = Int(parts[2]),
              minutes >= 0,
              (0..<60).contains(seconds),
              (0..<100).contains(centiseconds) else {
            return nil
        }

        return TimeInterval(minutes * 60 + seconds) + TimeInterval(centiseconds) / 100
    }
}

private struct StoredTranscriptLineRow: View {
    let line: StoredTranscriptLine
    let translatedText: String?
    let isShowingTranslation: Bool
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Text(line.timeText)
                    .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? .white : AppTheme.brand)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(isCurrent ? AppTheme.brand : AppTheme.brand.opacity(0.12), in: Capsule())

                VStack(alignment: .leading, spacing: 4) {
                    Text(translatedText ?? line.text)
                        .font(.redditSans(.body))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if translatedText != nil {
                        Text(line.text)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(true)
                    } else if isShowingTranslation {
                        Text("正在翻译")
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isCurrent ? AppTheme.brand.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let translatedText {
            return "\(line.timeText) \(translatedText) \(line.text)"
        }
        return "\(line.timeText) \(line.text)"
    }
}

@MainActor
final class RecordingPlaybackController: ObservableObject {
    @Published private(set) var currentItem: RecordingItem?
    @Published private(set) var isLoaded = false
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorText: String?
    @Published private(set) var playbackRate: Float = 1

    private static let playbackGainDecibels: Float = 3
    private static let playbackUITickMilliseconds = 250
    static let availablePlaybackRates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    private let audioSessionQueue = DispatchQueue(label: "com.reddownloader.live-transcriber.playback-session", qos: .userInitiated)
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchUnit: AVAudioUnitTimePitch?
    private var gainUnit: AVAudioUnitEQ?
    private var audioFile: AVAudioFile?
    private var playbackTimerTask: Task<Void, Never>?
    private var sampleRate: Double = 44_100
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var playbackScheduleID = 0

    func load(item: RecordingItem, url: URL) {
        guard currentItem?.id != item.id || currentItem?.audioFileName != item.audioFileName || !isLoaded else {
            return
        }

        load(url: url)
        currentItem = item
    }

    func load(url: URL) {
        unload()
        errorText = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorText = String(localized: "录音文件不存在")
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            try configurePlaybackEngine(format: file.processingFormat)
            currentTime = 0
            isLoaded = true
        } catch {
            errorText = String(format: String(localized: "无法播放录音: %@"), error.localizedDescription)
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    static func playbackRateLabel(_ rate: Float) -> String {
        if rate == floor(rate) {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }

    func play() {
        guard isLoaded, let playerNode else {
            return
        }

        Task {
            do {
                try await configurePlaybackSession()
                try startPlaybackEngineIfNeeded()
                if currentTime >= duration {
                    currentTime = 0
                }
                schedulePlayback(from: currentTime)
                playerNode.play()
                isPlaying = true
                startTimer()
            } catch {
                errorText = String(format: String(localized: "播放启动失败: %@"), error.localizedDescription)
            }
        }
    }

    func pause() {
        currentTime = currentPlaybackTime()
        playbackScheduleID += 1
        playerNode?.stop()
        isPlaying = false
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        guard isLoaded else {
            return
        }

        let clampedTime = min(max(time, 0), duration)
        currentTime = clampedTime
        if isPlaying {
            schedulePlayback(from: clampedTime)
            playerNode?.play()
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentPlaybackTime() + seconds)
    }

    func setPlaybackRate(_ rate: Float) {
        let clampedRate = min(max(rate, 0.5), 3)
        guard playbackRate != clampedRate else {
            return
        }

        currentTime = currentPlaybackTime()
        playbackRate = clampedRate
        timePitchUnit?.rate = clampedRate

        if isPlaying {
            schedulePlayback(from: currentTime)
            playerNode?.play()
        }
    }

    func unload() {
        playbackScheduleID += 1
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        timePitchUnit = nil
        gainUnit = nil
        audioEngine = nil
        audioFile = nil
        currentItem = nil
        isLoaded = false
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimer()
        Task {
            await deactivatePlaybackSession()
        }
    }

    private func startTimer() {
        stopTimer()
        playbackTimerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                guard self.isPlaying else {
                    do {
                        try await Task.sleep(for: .milliseconds(Self.playbackUITickMilliseconds))
                    } catch {
                        break
                    }
                    continue
                }

                self.currentTime = self.currentPlaybackTime()
                if self.currentTime >= self.duration {
                    self.finishPlayback()
                }

                do {
                    try await Task.sleep(for: .milliseconds(Self.playbackUITickMilliseconds))
                } catch {
                    break
                }
            }
        }
    }

    private func stopTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    private func configurePlaybackEngine(format: AVAudioFormat) throws {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = playbackRate
        let equalizer = AVAudioUnitEQ(numberOfBands: 1)
        if let band = equalizer.bands.first {
            band.filterType = .parametric
            band.frequency = 1_000
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
        equalizer.globalGain = Self.playbackGainDecibels

        engine.attach(node)
        engine.attach(timePitch)
        engine.attach(equalizer)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        engine.prepare()

        audioEngine = engine
        playerNode = node
        timePitchUnit = timePitch
        gainUnit = equalizer
    }

    private func startPlaybackEngineIfNeeded() throws {
        guard let audioEngine, !audioEngine.isRunning else {
            return
        }
        try audioEngine.start()
    }

    private func schedulePlayback(from time: TimeInterval) {
        guard let audioFile, let playerNode else {
            return
        }

        playbackScheduleID += 1
        let completionID = playbackScheduleID
        playerNode.stop()

        let startFrame = framePosition(for: time)
        let remainingFrames = max(audioFile.length - startFrame, 0)
        guard remainingFrames > 0 else {
            finishPlayback()
            return
        }

        scheduledStartFrame = startFrame
        currentTime = Double(startFrame) / sampleRate
        let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(AVAudioFrameCount.max)))
        playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, self.playbackScheduleID == completionID, self.isPlaying else {
                    return
                }
                self.finishPlayback()
            }
        }
    }

    private func framePosition(for time: TimeInterval) -> AVAudioFramePosition {
        guard sampleRate > 0 else {
            return 0
        }
        let clampedTime = min(max(time, 0), duration)
        let frame = AVAudioFramePosition((clampedTime * sampleRate).rounded(.down))
        return min(max(frame, 0), audioFile?.length ?? frame)
    }

    private func currentPlaybackTime() -> TimeInterval {
        guard isPlaying,
              sampleRate > 0,
              let playerNode,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return currentTime
        }

        let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
        let frame = min(max(scheduledStartFrame + playedFrames, 0), audioFile?.length ?? scheduledStartFrame)
        return min(Double(frame) / sampleRate, duration)
    }

    private func finishPlayback() {
        playbackScheduleID += 1
        playerNode?.stop()
        currentTime = duration
        isPlaying = false
        stopTimer()
        Task {
            await deactivatePlaybackSession()
        }
    }

    private func configurePlaybackSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [.duckOthers])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deactivatePlaybackSession() async {
        await withCheckedContinuation { continuation in
            audioSessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                continuation.resume(returning: ())
            }
        }
    }
}

private struct RecordingInfoPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.redditSans(.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

#if DEBUG
#Preview("Recordings") {
    RecordingsView(
        store: RecordingStore(),
        transcriber: LiveTranscriptionManager(),
        searchText: .constant(""),
        selectedRecording: .constant(nil),
        player: RecordingPlaybackController()
    )
        .font(.redditSans(.body))
        .tint(AppTheme.brand)
}
#endif
