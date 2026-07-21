import CloudKit
import CryptoKit
import Foundation
import TranscriberCore
import TranscriberDomain

actor MacRecordingLibrary: RecordingLibraryReading {
    enum LocationKind: Equatable, Sendable {
        case iCloud
        case selectedFolder
    }

    struct Location: Sendable {
        var kind: LocationKind
        var directoryURL: URL
    }

    private static let containerIdentifier = "iCloud.com.iamwilliamli.LiveTranscriber"
    private static let cloudZoneName = "LiveTranscriberMetadataV2"
    private static let cloudRecordType = "LTRecordingV2"
    private static let cloudRecordPrefix = "recording_"
    private static let cloudPayloadField = "payload"
    private static let selectedDirectoryBookmarkKey = "mac.library.selected-directory-bookmark.v1"
    private static let audioExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "mp3", "wav",
    ]
    private static let videoExtensions: Set<String> = ["m4v", "mov", "mp4"]
    private static let imageExtensions: Set<String> = ["heic", "jpeg", "jpg", "png"]

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private var selectedDirectoryURL: URL?
    private var securityScopedDirectoryURL: URL?
    private var currentLocation: Location?
    private var sessionsByID: [RecordingSession.ID: RecordingSession] = [:]

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        initialDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults

        if let initialDirectoryURL {
            selectedDirectoryURL = initialDirectoryURL
            return
        }

        guard let bookmarkData = defaults.data(forKey: Self.selectedDirectoryBookmarkKey) else {
            return
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() {
            selectedDirectoryURL = url
            securityScopedDirectoryURL = url
            if isStale,
               let refreshedBookmark = try? url.bookmarkData(
                   options: [.withSecurityScope],
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                defaults.set(refreshedBookmark, forKey: Self.selectedDirectoryBookmarkKey)
            }
        }
    }

    deinit {
        securityScopedDirectoryURL?.stopAccessingSecurityScopedResource()
    }

    func selectDirectory(_ url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        securityScopedDirectoryURL?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            throw MacRecordingLibraryError.folderAccessDenied
        }
        selectedDirectoryURL = url
        securityScopedDirectoryURL = url
        currentLocation = nil
        sessionsByID = [:]
        defaults.set(bookmarkData, forKey: Self.selectedDirectoryBookmarkKey)
    }

    func useICloudDirectory() {
        securityScopedDirectoryURL?.stopAccessingSecurityScopedResource()
        selectedDirectoryURL = nil
        securityScopedDirectoryURL = nil
        currentLocation = nil
        sessionsByID = [:]
        defaults.removeObject(forKey: Self.selectedDirectoryBookmarkKey)
    }

    func location() throws -> Location {
        if let selectedDirectoryURL {
            return Location(kind: .selectedFolder, directoryURL: selectedDirectoryURL)
        }
        guard let containerURL = fileManager.url(
            forUbiquityContainerIdentifier: Self.containerIdentifier
        ) else {
            throw MacRecordingLibraryError.iCloudContainerUnavailable
        }
        let recordingsURL = containerURL.appendingPathComponent(
            "Data/Recordings",
            isDirectory: true
        )
        let legacyCandidates = [
            containerURL.appendingPathComponent("Recordings", isDirectory: true),
            containerURL.appendingPathComponent("Documents/Recordings", isDirectory: true),
        ]
        if let legacyDirectory = legacyCandidates.first(where: directoryContainsMedia) {
            return Location(kind: .iCloud, directoryURL: legacyDirectory)
        }
        try fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        return Location(kind: .iCloud, directoryURL: recordingsURL)
    }

    func recordingSessions() async throws -> [RecordingSession] {
        let location = try location()
        let cloudSessions: [RecordingSession]
        if location.kind == .iCloud {
            cloudSessions = (try? await fetchCloudSessions()) ?? []
        } else {
            cloudSessions = []
        }

        let scannedFiles = try scanFiles(in: location.directoryURL)
        let mergedSessions = merge(cloudSessions: cloudSessions, scannedFiles: scannedFiles)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
        currentLocation = location
        sessionsByID = mergedSessions.reduce(into: [:]) { result, session in
            result[session.id] = session
        }
        return mergedSessions
    }

    func recordingSession(withID id: RecordingSession.ID) async throws -> RecordingSession? {
        if let session = sessionsByID[id] {
            return session
        }
        _ = try await recordingSessions()
        return sessionsByID[id]
    }

    func recordingAssetURL(
        sessionID: RecordingSession.ID,
        assetID: RecordingAsset.ID
    ) async throws -> URL {
        if sessionsByID[sessionID] == nil {
            _ = try await recordingSessions()
        }
        guard let session = sessionsByID[sessionID] else {
            throw RecordingLibraryError.recordingNotFound(sessionID)
        }
        guard let asset = session.assets.first(where: { $0.id == assetID }) else {
            throw RecordingLibraryError.assetNotFound(assetID)
        }
        guard asset.isSafeRelativePath else {
            throw RecordingLibraryError.unsafeAssetPath(asset.relativePath)
        }

        let location = try currentLocation ?? self.location()
        let rootURL = location.directoryURL.standardizedFileURL
        let assetURL = rootURL.appendingPathComponent(asset.relativePath).standardizedFileURL
        guard assetURL.path == rootURL.path
                || assetURL.path.hasPrefix(rootURL.path + "/") else {
            throw RecordingLibraryError.unsafeAssetPath(asset.relativePath)
        }

        try await prepareUbiquitousItem(at: assetURL)
        guard fileManager.fileExists(atPath: assetURL.path) else {
            throw MacRecordingLibraryError.assetFileMissing(asset.relativePath)
        }
        return assetURL
    }

    private func fetchCloudSessions() async throws -> [RecordingSession] {
        let database = CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: Self.cloudZoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let query = CKQuery(recordType: Self.cloudRecordType, predicate: NSPredicate(value: true))
        var page = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: [Self.cloudPayloadField]
        )
        var sessions = decodedSessions(from: page.matchResults)

        while let cursor = page.queryCursor {
            try Task.checkCancellation()
            page = try await database.records(
                continuingMatchFrom: cursor,
                desiredKeys: [Self.cloudPayloadField]
            )
            sessions.append(contentsOf: decodedSessions(from: page.matchResults))
        }
        return sessions
    }

    private func decodedSessions(
        from results: [(CKRecord.ID, Result<CKRecord, any Error>)]
    ) -> [RecordingSession] {
        results.compactMap { recordID, result in
            guard recordID.recordName.hasPrefix(Self.cloudRecordPrefix),
                  let record = try? result.get(),
                  let data = record[Self.cloudPayloadField] as? Data,
                  let session = try? RecordingSessionPayloadDecoder.decode(data) else {
                return nil
            }
            return session
        }
    }

    private func scanFiles(in directory: URL) throws -> [ScannedRecordingFile] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .creationDateKey,
            .isDirectoryKey,
            .isRegularFileKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [ScannedRecordingFile] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true,
                  let kind = Self.assetKind(for: fileURL) else {
                continue
            }
            let relativePath = Self.relativePath(for: fileURL, in: directory)
            guard !relativePath.isEmpty else {
                continue
            }
            files.append(
                ScannedRecordingFile(
                    sessionID: Self.sessionID(for: relativePath),
                    groupingKey: Self.groupingKey(for: relativePath),
                    asset: RecordingAsset(
                        id: "discovered.\(kind.rawValue).\(relativePath)",
                        kind: kind,
                        relativePath: relativePath
                    ),
                    createdAt: values?.creationDate
                        ?? values?.contentModificationDate
                        ?? Date.distantPast
                )
            )
        }
        return files
    }

    private func merge(
        cloudSessions: [RecordingSession],
        scannedFiles: [ScannedRecordingFile]
    ) -> [RecordingSession] {
        var sessions = cloudSessions.reduce(into: [RecordingSession.ID: RecordingSession]()) {
            result,
            session in
            if let existing = result[session.id], existing.createdAt > session.createdAt {
                return
            }
            result[session.id] = session
        }
        let groupedFiles = Dictionary(grouping: scannedFiles) { file in
            file.sessionID?.uuidString.lowercased() ?? file.groupingKey
        }

        for (groupingKey, files) in groupedFiles {
            let knownID = files.compactMap(\.sessionID).first
            let sessionID = knownID ?? Self.stableUUID(for: groupingKey)
            if var session = sessions[sessionID] {
                let knownPaths = Set(session.assets.map(\.relativePath))
                session.assets.append(contentsOf: files.compactMap { file in
                    knownPaths.contains(file.asset.relativePath) ? nil : file.asset
                })
                if session.primaryAssetID == nil {
                    session.primaryAssetID = session.assets.first(where: {
                        $0.kind.isAudio || $0.kind.isVideo
                    })?.id
                }
                sessions[sessionID] = session
                continue
            }

            let assets = files.map(\.asset).sorted { lhs, rhs in
                Self.assetSortRank(lhs.kind) < Self.assetSortRank(rhs.kind)
            }
            guard assets.contains(where: { $0.kind.isAudio || $0.kind.isVideo }) else {
                continue
            }
            let createdAt = files.map(\.createdAt).filter { $0 != .distantPast }.min() ?? Date()
            let rawTitle = files.first?.groupingKey ?? groupingKey
            let title = UUID(uuidString: rawTitle) == nil
                ? rawTitle
                : Self.defaultTitle(for: createdAt)
            sessions[sessionID] = RecordingSession(
                id: sessionID,
                createdAt: createdAt,
                title: title,
                durationSeconds: 0,
                assets: assets,
                primaryAssetID: assets.first(where: {
                    $0.kind.isAudio || $0.kind.isVideo
                })?.id
            )
        }
        return Array(sessions.values)
    }

    private func prepareUbiquitousItem(at url: URL) async throws {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        guard let initialValues = try? url.resourceValues(forKeys: keys),
              initialValues.isUbiquitousItem == true else {
            return
        }

        try fileManager.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<150 {
            try Task.checkCancellation()
            let status = try? url.resourceValues(forKeys: keys).ubiquitousItemDownloadingStatus
            if status == .current || status == .downloaded {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private static func assetKind(for url: URL) -> RecordingAssetKind? {
        let fileExtension = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        if audioExtensions.contains(fileExtension) {
            if name.contains("microphone") || name.contains(".mic.") {
                return .microphoneAudio
            }
            if name.contains("system") {
                return .systemAudio
            }
            if name.contains("mixed") {
                return .mixedAudio
            }
            return .primaryAudio
        }
        if videoExtensions.contains(fileExtension) {
            return name.contains("camera") ? .cameraVideo : .screenVideo
        }
        if fileExtension == "txt" || fileExtension == "md" {
            return .transcript
        }
        if imageExtensions.contains(fileExtension) {
            return .thumbnail
        }
        return nil
    }

    private func directoryContainsMedia(_ directory: URL) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }
        for case let fileURL as URL in enumerator where Self.assetKind(for: fileURL) != nil {
            return true
        }
        return false
    }

    private static func relativePath(for fileURL: URL, in directory: URL) -> String {
        let rootPath = directory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return ""
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func sessionID(for relativePath: String) -> UUID? {
        let fileName = (relativePath as NSString).lastPathComponent
        let stem = (fileName as NSString).deletingPathExtension
        if let id = UUID(uuidString: stem) {
            return id
        }
        if stem.count >= 36,
           let id = UUID(uuidString: String(stem.prefix(36))) {
            return id
        }
        let firstComponent = (relativePath as NSString).pathComponents.first
        return firstComponent.flatMap(UUID.init(uuidString:))
    }

    private static func groupingKey(for relativePath: String) -> String {
        let fileName = (relativePath as NSString).lastPathComponent
        let stem = (fileName as NSString).deletingPathExtension
        if stem.count >= 36, UUID(uuidString: String(stem.prefix(36))) != nil {
            return String(stem.prefix(36)).lowercased()
        }
        return stem
    }

    private static func stableUUID(for value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        var hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        hex.replaceSubrange(hex.index(hex.startIndex, offsetBy: 12)...hex.index(hex.startIndex, offsetBy: 12), with: "5")
        let variantIndex = hex.index(hex.startIndex, offsetBy: 16)
        let variant = Int(String(hex[variantIndex]), radix: 16) ?? 0
        hex.replaceSubrange(variantIndex...variantIndex, with: String(format: "%x", (variant & 0x3) | 0x8))
        let uuidString = [8, 4, 4, 4, 12].reduce(into: (parts: [String](), index: hex.startIndex)) { result, length in
            let end = hex.index(result.index, offsetBy: length)
            result.parts.append(String(hex[result.index..<end]))
            result.index = end
        }.parts.joined(separator: "-")
        return UUID(uuidString: uuidString)!
    }

    private static func assetSortRank(_ kind: RecordingAssetKind) -> Int {
        switch kind {
        case .primaryAudio: return 0
        case .mixedAudio: return 1
        case .systemAudio: return 2
        case .microphoneAudio: return 3
        case .screenVideo: return 4
        case .cameraVideo: return 5
        case .transcript: return 6
        case .thumbnail: return 7
        case .attachment: return 8
        }
    }

    private static func defaultTitle(for date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ScannedRecordingFile {
    var sessionID: UUID?
    var groupingKey: String
    var asset: RecordingAsset
    var createdAt: Date
}

private enum MacRecordingLibraryError: LocalizedError {
    case iCloudContainerUnavailable
    case folderAccessDenied
    case assetFileMissing(String)

    var errorDescription: String? {
        switch self {
        case .iCloudContainerUnavailable:
            return "The Live Transcriber iCloud container is unavailable. Sign in to iCloud Drive or choose a recording folder."
        case .folderAccessDenied:
            return "Live Transcriber could not retain access to the selected folder."
        case .assetFileMissing(let path):
            return "The recording asset is not available at \(path)."
        }
    }
}
