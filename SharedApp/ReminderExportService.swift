import EventKit
import Foundation

@MainActor
enum ReminderExportService {
    private static let eventStore = EKEventStore()

    static func addActionItems(
        _ actionItems: [RecordingActionItem],
        recordingTitle: String
    ) async throws -> Int {
        let validItems = actionItems.filter { !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validItems.isEmpty else {
            throw ReminderExportError.noActionItems
        }

        return try await addDrafts(
            validItems.map { ReminderDraft(actionItem: $0, recordingTitle: recordingTitle) }
        )
    }

    static func addDrafts(_ drafts: [ReminderDraft]) async throws -> Int {
        let validDrafts = drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validDrafts.isEmpty else {
            throw ReminderExportError.noActionItems
        }

        try await requestAccessIfNeeded()
        let calendar = try writableReminderCalendar()
        var createdCount = 0

        for draft in validDrafts {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.priority = draft.priority
            let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                reminder.notes = notes
            }
            if draft.hasDueDate, let dueDate = draft.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }
            try eventStore.save(reminder, commit: true)
            createdCount += 1
        }

        return createdCount
    }

    private static func requestAccessIfNeeded() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted = try await requestReminderAccess()
            guard granted else {
                throw ReminderExportError.accessDenied
            }
        case .denied, .restricted, .writeOnly:
            throw ReminderExportError.accessDenied
        @unknown default:
            throw ReminderExportError.accessDenied
        }
    }

    private static func requestReminderAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            if #available(iOS 17.0, *) {
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            } else {
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    private static func writableReminderCalendar() throws -> EKCalendar {
        if let calendar = eventStore.defaultCalendarForNewReminders(),
           calendar.allowsContentModifications {
            return calendar
        }

        if let calendar = eventStore.calendars(for: .reminder).first(where: \.allowsContentModifications) {
            return calendar
        }

        throw ReminderExportError.noWritableList
    }

    private static func reminderNotes(
        for actionItem: RecordingActionItem,
        recordingTitle: String
    ) -> String {
        var lines = [localizedFormat(L10n.Recordings.reminderNoteSourceFormat, recordingTitle)]

        if let owner = actionItem.owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
            lines.append(localizedFormat(L10n.Recordings.reminderNoteOwnerFormat, owner))
        }

        if let dueDate = actionItem.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines), !dueDate.isEmpty {
            lines.append(localizedFormat(L10n.Recordings.reminderNoteDueDateFormat, dueDate))
        }

        return lines.joined(separator: "\n")
    }

    private static func localizedFormat(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
        String(format: String(localized: resource), arguments: arguments)
    }

    private static func dueDateComponents(from text: String?) -> DateComponents? {
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let date = detector.firstMatch(in: text, options: [], range: range)?.date else {
            return nil
        }

        return Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: date
        )
    }
}

struct ReminderDraft: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var notes: String
    var dueDate: Date?
    var hasDueDate: Bool
    var priority: Int

    init(
        title: String,
        notes: String,
        dueDate: Date?,
        hasDueDate: Bool,
        priority: Int = 5
    ) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasDueDate = hasDueDate
        self.priority = priority
    }

    init(actionItem: RecordingActionItem, recordingTitle: String) {
        let parsedDueDate = Self.dueDate(from: actionItem.dueDate)
        self.init(
            title: actionItem.task,
            notes: Self.notes(for: actionItem, recordingTitle: recordingTitle),
            dueDate: parsedDueDate,
            hasDueDate: parsedDueDate != nil
        )
    }

    private static func notes(
        for actionItem: RecordingActionItem,
        recordingTitle: String
    ) -> String {
        var lines = [String(format: String(localized: L10n.Recordings.reminderNoteSourceFormat), recordingTitle)]

        if let owner = actionItem.owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
            lines.append(String(format: String(localized: L10n.Recordings.reminderNoteOwnerFormat), owner))
        }

        if let dueDate = actionItem.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines), !dueDate.isEmpty {
            lines.append(String(format: String(localized: L10n.Recordings.reminderNoteDueDateFormat), dueDate))
        }

        return lines.joined(separator: "\n")
    }

    private static func dueDate(from text: String?) -> Date? {
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.date
    }
}

enum ReminderExportError: LocalizedError {
    case accessDenied
    case noWritableList
    case noActionItems

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return String(localized: L10n.Recordings.reminderAccessDenied)
        case .noWritableList:
            return String(localized: L10n.Recordings.reminderNoWritableList)
        case .noActionItems:
            return String(localized: L10n.Recordings.reminderNoActionItems)
        }
    }
}
