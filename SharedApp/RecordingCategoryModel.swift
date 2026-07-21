import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum RecordingCategoryCatalog {
    static let customCategoriesDefaultsKey = "Recordings.customCategoriesJSON"
    static let definitionsDefaultsKey = "Recordings.categoryDefinitionsV2JSON"
    static let deletedCategoryTombstonesDefaultsKey = "Recordings.deletedCategoryTombstonesV2JSON"

    static func definitions() -> [RecordingCategoryDefinition] {
        guard let data = UserDefaults.standard.data(forKey: definitionsDefaultsKey),
              let decoded = try? JSONDecoder().decode([RecordingCategoryDefinition].self, from: data) else {
            return []
        }
        let tombstones = deletedCategoryTombstones()
        return decoded
            .filter { tombstones[$0.id] == nil }
            .map(\.normalized)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func customNames() -> [String] {
        definitions().map(\.name)
    }

    static func allNames(recordings: [RecordingItem]) -> [String] {
        normalized(recordings.compactMap(\.categoryName) + customNames())
    }

    static func definition(named name: String?) -> RecordingCategoryDefinition? {
        guard let cleaned = RecordingItem.normalizedCategoryName(name), !cleaned.isEmpty else {
            return nil
        }
        let key = cleaned.normalizedForRecordingSearch
        return definitions().first { $0.name.normalizedForRecordingSearch == key }
    }

    static func definition(id: UUID?) -> RecordingCategoryDefinition? {
        guard let id else {
            return nil
        }
        return definitions().first { $0.id == id }
    }

    @discardableResult
    static func register(_ name: String?) -> RecordingCategoryDefinition? {
        guard let cleaned = RecordingItem.normalizedCategoryName(name ?? "") else {
            return nil
        }
        if let existing = definition(named: cleaned) {
            return existing
        }

        let definition = RecordingCategoryDefinition(
            id: UUID(),
            name: cleaned,
            appearance: .defaultValue,
            modifiedAt: Date()
        )
        writeDefinitions(definitions() + [definition])
        RecordingMetadataCloudSync.shared.scheduleCategorySave(id: definition.id)
        return definition
    }

    static func remove(_ name: String) {
        let key = name.normalizedForRecordingSearch
        let current = definitions()
        let removedIDs = current
            .filter { $0.name.normalizedForRecordingSearch == key }
            .map(\.id)
        guard !removedIDs.isEmpty else {
            return
        }
        addDeletedCategoryTombstones(removedIDs)
        writeDefinitions(current.filter { !removedIDs.contains($0.id) })
        for id in removedIDs {
            RecordingMetadataCloudSync.shared.scheduleCategoryDelete(id: id)
        }
    }

    static func rename(_ oldName: String, to newName: String) {
        let oldKey = oldName.normalizedForRecordingSearch
        guard let cleanedName = RecordingItem.normalizedCategoryName(newName) else {
            return
        }
        var current = definitions()
        let matchingIndices = current.indices.filter {
            current[$0].name.normalizedForRecordingSearch == oldKey
        }
        guard !matchingIndices.isEmpty else {
            _ = register(cleanedName)
            return
        }
        let now = Date()
        let ids = matchingIndices.map { index in
            current[index].name = cleanedName
            current[index].modifiedAt = now
            return current[index].id
        }
        writeDefinitions(current)
        for id in ids {
            RecordingMetadataCloudSync.shared.scheduleCategorySave(id: id)
        }
    }

    static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for name in names {
            guard let cleaned = RecordingItem.normalizedCategoryName(name) else {
                continue
            }
            let key = cleaned.normalizedForRecordingSearch
            guard seen.insert(key).inserted else {
                continue
            }
            normalized.append(cleaned)
        }

        return normalized.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    static func updateAppearance(
        _ appearance: RecordingCategoryAppearance,
        for name: String
    ) {
        guard let existing = definition(named: name) ?? register(name) else {
            return
        }
        var current = definitions()
        guard let index = current.firstIndex(where: { $0.id == existing.id }) else {
            return
        }
        current[index].appearance = appearance.normalized
        current[index].modifiedAt = Date()
        writeDefinitions(current)
        RecordingMetadataCloudSync.shared.scheduleCategorySave(id: existing.id)
    }

    @discardableResult
    static func applyRemote(_ remote: RecordingCategoryDefinition) -> Bool {
        let remote = remote.normalized
        guard !isTombstoned(remote.id) else {
            return false
        }
        var current = definitions()
        if let index = current.firstIndex(where: { $0.id == remote.id }) {
            guard current[index].modifiedAt <= remote.modifiedAt else {
                return false
            }
            current[index] = remote
        } else {
            current.append(remote)
        }
        writeDefinitions(current)
        return true
    }

    @discardableResult
    static func applyRemoteDeletion(id: UUID) -> Bool {
        let current = definitions()
        let existed = current.contains(where: { $0.id == id })
        addDeletedCategoryTombstones([id])
        writeDefinitions(current.filter { $0.id != id })
        return existed
    }

    static func cloudPayload(for id: UUID) -> (data: Data, modifiedAt: Date)? {
        guard !isTombstoned(id),
              let definition = definition(id: id),
              let data = try? JSONEncoder().encode(definition.cloudPayload) else {
            return nil
        }
        return (data, definition.modifiedAt)
    }

    static func tombstonedIDs() -> [UUID] {
        Array(deletedCategoryTombstones().keys)
    }

    static func isTombstoned(_ id: UUID) -> Bool {
        deletedCategoryTombstones()[id] != nil
    }

    private static func deletedCategoryTombstones() -> [UUID: Date] {
        guard let data = UserDefaults.standard.data(forKey: deletedCategoryTombstonesDefaultsKey),
              let stored = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, date in
            UUID(uuidString: key).map { ($0, date) }
        })
    }

    private static func addDeletedCategoryTombstones(_ ids: [UUID]) {
        var tombstones = deletedCategoryTombstones()
        let now = Date()
        for id in ids {
            tombstones[id] = now
        }
        let stored = Dictionary(uniqueKeysWithValues: tombstones.map {
            ($0.key.uuidString, $0.value)
        })
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: deletedCategoryTombstonesDefaultsKey)
        }
    }

    private static func writeDefinitions(_ definitions: [RecordingCategoryDefinition]) {
        let normalizedDefinitions = definitions.map(\.normalized)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var appearances: [String: RecordingCategoryAppearance] = [:]
        for definition in normalizedDefinitions.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            appearances[definition.name.normalizedForRecordingSearch] = definition.appearance
        }
        guard let definitionsData = try? encoder.encode(normalizedDefinitions),
              let namesData = try? encoder.encode(normalized(normalizedDefinitions.map(\.name))),
              let namesJSON = String(data: namesData, encoding: .utf8),
              let appearancesData = try? encoder.encode(appearances),
              let appearancesJSON = String(data: appearancesData, encoding: .utf8) else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(definitionsData, forKey: definitionsDefaultsKey)
        // These two keys remain local SwiftUI invalidation caches. They are no
        // longer synchronized through iCloud KVS.
        defaults.set(namesJSON, forKey: customCategoriesDefaultsKey)
        defaults.set(appearancesJSON, forKey: RecordingCategoryAppearanceCatalog.defaultsKey)
    }
}

struct RecordingCategoryDefinition: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var appearance: RecordingCategoryAppearance
    var modifiedAt: Date

    var normalized: RecordingCategoryDefinition {
        RecordingCategoryDefinition(
            id: id,
            name: RecordingItem.normalizedCategoryName(name) ?? name,
            appearance: appearance.normalized,
            modifiedAt: modifiedAt
        )
    }

    var cloudPayload: RecordingCategoryDefinition {
        normalized
    }
}

struct RecordingCategoryAppearance: Codable, Hashable, Sendable {
    static let defaultValue = RecordingCategoryAppearance(
        iconName: "folder.fill",
        red: 0.96,
        green: 0.22,
        blue: 0.10
    )

    static let availableIconNames = [
        "folder.fill",
        "briefcase.fill",
        "book.closed.fill",
        "graduationcap.fill",
        "person.2.fill",
        "bubble.left.and.bubble.right.fill",
        "mic.fill",
        "waveform",
        "lightbulb.fill",
        "star.fill",
        "heart.fill",
        "gamecontroller.fill",
        "music.note",
        "film.fill",
        "airplane",
        "house.fill",
        "building.2.fill",
        "calendar",
        "checklist",
        "tag.fill"
    ]

    let iconName: String
    let red: Double
    let green: Double
    let blue: Double

    init(iconName: String, red: Double, green: Double, blue: Double) {
        self.iconName = Self.availableIconNames.contains(iconName)
            ? iconName
            : "folder.fill"
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(iconName: String, color: Color) {
        var red: CGFloat = 0.96
        var green: CGFloat = 0.22
        var blue: CGFloat = 0.10
        var alpha: CGFloat = 1
        #if canImport(UIKit)
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        if let resolvedColor = NSColor(color).usingColorSpace(.sRGB) {
            resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        #endif
        self.init(
            iconName: iconName,
            red: Double(red),
            green: Double(green),
            blue: Double(blue)
        )
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var normalized: RecordingCategoryAppearance {
        RecordingCategoryAppearance(iconName: iconName, red: red, green: green, blue: blue)
    }
}

enum RecordingCategoryAppearanceCatalog {
    static let defaultsKey = "Recordings.categoryAppearancesJSON"

    static func decode(_ json: String) -> [String: RecordingCategoryAppearance] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: RecordingCategoryAppearance].self, from: data) else {
            return [:]
        }
        return decoded.mapValues(\.normalized)
    }

    static func all() -> [String: RecordingCategoryAppearance] {
        var appearances: [String: RecordingCategoryAppearance] = [:]
        for definition in RecordingCategoryCatalog.definitions().sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            appearances[definition.name.normalizedForRecordingSearch] = definition.appearance
        }
        return appearances
    }

    static func appearance(for categoryName: String) -> RecordingCategoryAppearance {
        all()[categoryName.normalizedForRecordingSearch] ?? .defaultValue
    }

    static func set(
        _ appearance: RecordingCategoryAppearance,
        for categoryName: String,
        removing oldCategoryName: String? = nil
    ) {
        RecordingCategoryCatalog.updateAppearance(appearance, for: categoryName)
    }

    static func remove(_ categoryName: String) {
        // The category record owns its appearance, so deleting the category
        // already removes the appearance atomically.
    }
}
