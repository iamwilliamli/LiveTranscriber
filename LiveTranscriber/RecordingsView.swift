import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordingsView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @StateObject private var player = RecordingPlaybackController()
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var selectedRecording: RecordingItem?
    @State private var analyzingRecordingID: RecordingItem.ID?
    @State private var analysisErrorMessage: String?
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var pendingImport: PendingImport?
    @State private var searchText = ""

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
        NavigationStack {
            Group {
                if store.recordings.isEmpty {
                    EmptyStateView(icon: "waveform.path.badge.plus", title: "暂无录音文件")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.groupedBackground)
                } else if filteredRecordings.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "没有找到录音")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.groupedBackground)
                } else {
                    List {
                        ForEach(filteredRecordings) { item in
                            RecordingRow(
                                item: item,
                                isAnalyzing: analyzingRecordingID == item.id,
                                showsIntelligence: store.intelligenceAvailability.isAvailable,
                                languages: transcriber.supportedLanguages
                            ) {
                                selectedRecording = item
                            } onRetranscribe: { language in
                                retranscribe(item, language: language)
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
                                .disabled(item.importStatus?.isFailed == false)

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
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.groupedBackground.ignoresSafeArea())
                    .safeAreaInset(edge: .top) {
                        Color.clear.frame(height: 4)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 8)
                    }
                }
            }
            .navigationTitle("录音文件")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        HapticFeedback.play(.primaryAction)
                        showsImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(isImporting || pendingImport != nil)
                    .accessibilityLabel("导入录音")
                }
            }
            .navigationDestination(item: $selectedRecording) { item in
                RecordingDetailView(item: item, store: store, transcriber: transcriber, player: player)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("搜索录音或转录")
        )
        .task {
            await transcriber.refreshSupportedLanguages()
            await store.reload()
            store.refreshIntelligenceAvailability()
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .confirmationDialog(
            "选择转录语言",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingImport = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingImport {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        importRecording(from: pendingImport.url, language: language)
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language.id == transcriber.selectedLanguageID ? "checkmark" : "globe"
                        )
                    }
                }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("导入录音")
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
            "导入失败",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        importErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
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

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                HapticFeedback.play(.warning)
                return
            }
            pendingImport = PendingImport(url: url)
            HapticFeedback.play(.importQueued)
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func importRecording(from url: URL, language: TranscriptionLanguage) {
        guard !isImporting else {
            HapticFeedback.play(.blocked)
            return
        }

        pendingImport = nil
        isImporting = true
        HapticFeedback.play(.importStart)
        Task {
            do {
                _ = try await store.importRecording(from: url, language: language)
                HapticFeedback.play(.importComplete)
            } catch {
                importErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isImporting = false
        }
    }

    private func retranscribe(_ item: RecordingItem, language: TranscriptionLanguage) {
        Task {
            HapticFeedback.play(.retranscribeStart)
            do {
                try await store.retranscribe(item, language: language)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                importErrorMessage = error.localizedDescription
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
        let searchableFields = [
            item.audioFileName,
            item.languageName,
            item.transcriptPreview,
            item.intelligence?.summary ?? "",
            item.intelligence?.tags.joined(separator: " ") ?? "",
            store.transcriptText(for: item)
        ]

        return searchableFields.contains { field in
            normalizedSearchText(field).contains(query)
        }
    }

    private func normalizedSearchText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

private struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RecordingDeleteRequest: Identifiable {
    let item: RecordingItem

    var id: RecordingItem.ID {
        item.id
    }
}

private struct RecordingRow: View {
    let item: RecordingItem
    let isAnalyzing: Bool
    let showsIntelligence: Bool
    let languages: [TranscriptionLanguage]
    let onOpen: () -> Void
    let onRetranscribe: (TranscriptionLanguage) -> Void

    private var isTranscriptionRunning: Bool {
        item.importStatus?.isFailed == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                            .fill(AppTheme.brand.opacity(0.12))
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppTheme.brand)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.redditSans(.headline, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(item.audioFileName)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticFeedback.play(.navigation)
                    onOpen()
                }

                Spacer(minLength: 8)

                Menu {
                    ForEach(languages) { language in
                        Button {
                            onRetranscribe(language)
                        } label: {
                            Label(
                                language.displayName,
                                systemImage: language.id == item.languageID ? "checkmark" : "globe"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .foregroundStyle(isTranscriptionRunning ? .secondary : AppTheme.brand)
                .disabled(isTranscriptionRunning)
                .accessibilityLabel("重新转录")

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
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                Label(item.languageName, systemImage: "globe")
                Label("\(item.lineCount)", systemImage: "text.alignleft")
            }
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticFeedback.play(.navigation)
                    onOpen()
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

            if !intelligence.tags.isEmpty {
                FlowTags(tags: Array(intelligence.tags.prefix(4)))
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

private struct RecordingDetailView: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var isAnalyzing = false
    @State private var analysisErrorMessage: String?
    @State private var deleteErrorMessage: String?

    private var currentItem: RecordingItem {
        store.recording(withID: item.id) ?? item
    }

    private var isTranscriptionRunning: Bool {
        currentItem.importStatus?.isFailed == false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                playerCard
                if store.intelligenceAvailability.isAvailable {
                    intelligenceCard
                }
                transcript
            }
            .padding()
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle("录音详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: store.audioURL(for: currentItem)) {
                        Label("分享音频", systemImage: "waveform")
                    }

                    ShareLink(item: store.transcriptText(for: currentItem)) {
                        Label("分享转录文字", systemImage: "text.alignleft")
                    }
                    .disabled(store.transcriptText(for: currentItem).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享")

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
                    Image(systemName: isTranscriptionRunning ? "hourglass" : "arrow.triangle.2.circlepath")
                }
                .disabled(isTranscriptionRunning)
                .accessibilityLabel("重新转录")

                Button {
                    HapticFeedback.play(.copy)
                    UIPasteboard.general.string = store.transcriptText(for: currentItem)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }

                if store.intelligenceAvailability.isAvailable {
                    Button {
                        analyzeCurrentItem()
                    } label: {
                        Image(systemName: isAnalyzing ? "hourglass" : "sparkles")
                    }
                    .disabled(isAnalyzing)
                }

                Button(role: .destructive) {
                    HapticFeedback.play(.deleteRequested)
                    deleteRequest = RecordingDeleteRequest(item: currentItem)
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isTranscriptionRunning)
            }
        }
        .onAppear {
            Task {
                store.refreshIntelligenceAvailability()
                await store.normalizeAudioIfNeeded(for: currentItem)
                player.load(item: currentItem, url: store.audioURL(for: currentItem))
            }
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

                if !intelligence.tags.isEmpty {
                    FlowTags(tags: intelligence.tags)
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

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("播放录音", systemImage: "play.circle")
                .font(.redditSans(.headline))

            HStack(spacing: 12) {
                Button {
                    HapticFeedback.play(.playbackToggle)
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                        .background(player.isLoaded ? AppTheme.brand : Color.secondary, in: Circle())
                }
                .disabled(!player.isLoaded)

                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 1)
                    )
                    .disabled(!player.isLoaded)

                    HStack {
                        Text(TranscriptionLine.formatTimestamp(player.currentTime))
                        Spacer()
                        Text(TranscriptionLine.formatTimestamp(player.duration))
                    }
                    .font(.redditSans(.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            if let errorText = player.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var transcript: some View {
        let item = currentItem
        let text = store.transcriptText(for: item)
        let lines = StoredTranscriptLine.parse(text)

        return VStack(alignment: .leading, spacing: 12) {
            Label("转录文本", systemImage: "text.alignleft")
                .font(.redditSans(.headline))

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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        StoredTranscriptLineRow(
                            line: line,
                            isCurrent: line.contains(time: player.currentTime, in: lines)
                        ) {
                            HapticFeedback.play(.timelineSeek)
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
        isAnalyzing = true
        HapticFeedback.play(.analysisStart)
        Task {
            do {
                _ = try await store.analyzeIntelligence(for: item)
                HapticFeedback.play(.analysisComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isAnalyzing = false
        }
    }

    private func retranscribeCurrentItem(language: TranscriptionLanguage) {
        guard !isTranscriptionRunning else {
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

    private func deleteCurrentItem(_ item: RecordingItem) {
        do {
            player.unload()
            try store.delete(item)
            HapticFeedback.play(.deleteConfirmed)
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
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

private struct StoredTranscriptLine: Identifiable, Hashable {
    let id = UUID()
    let startSeconds: TimeInterval
    let timeText: String
    let text: String

    static func parse(_ transcript: String) -> [StoredTranscriptLine] {
        transcript
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
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

                return StoredTranscriptLine(startSeconds: seconds, timeText: timeText, text: text)
            }
    }

    func contains(time: TimeInterval, in lines: [StoredTranscriptLine]) -> Bool {
        guard time >= startSeconds else {
            return false
        }

        let sorted = lines.sorted { $0.startSeconds < $1.startSeconds }
        guard let index = sorted.firstIndex(where: { $0.id == id }) else {
            return false
        }

        if sorted.indices.contains(index + 1) {
            return time < sorted[index + 1].startSeconds
        }
        return true
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

                Text(line.text)
                    .font(.redditSans(.body))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isCurrent ? AppTheme.brand.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(line.timeText) \(line.text)")
    }
}

@MainActor
private final class RecordingPlaybackController: ObservableObject {
    @Published private(set) var currentItem: RecordingItem?
    @Published private(set) var isLoaded = false
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorText: String?

    private static let playbackGainDecibels: Float = 3

    private let audioSessionQueue = DispatchQueue(label: "com.reddownloader.live-transcriber.playback-session", qos: .userInitiated)
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var gainUnit: AVAudioUnitEQ?
    private var audioFile: AVAudioFile?
    private var playbackTimerTask: Task<Void, Never>?
    private var sampleRate: Double = 44_100
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var playbackScheduleID = 0

    func load(item: RecordingItem, url: URL) {
        guard currentItem?.id != item.id || !isLoaded else {
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

    func unload() {
        playbackScheduleID += 1
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
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
                        try await Task.sleep(for: .milliseconds(120))
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
                    try await Task.sleep(for: .milliseconds(120))
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
        engine.attach(equalizer)
        engine.connect(node, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        engine.prepare()

        audioEngine = engine
        playerNode = node
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
        transcriber: LiveTranscriptionManager()
    )
        .font(.redditSans(.body))
        .tint(AppTheme.brand)
}
#endif
