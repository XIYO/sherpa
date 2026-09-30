import Foundation
import SherpaPlannerContract

public struct ReminderCommandValidator: Sendable {
    public init() {}

    public func validate(_ command: ReminderListRequest) throws {
        guard command.collectionNativeLocator.map(validLocator) ?? true,
              command.limit.map { (1 ... 10_000).contains($0) } ?? true
        else { throw PlannerValidationError.invalidCommand }
    }

    public func validate(_ command: ReminderGetRequest) throws {
        guard validLocator(command.nativeLocator) else { throw PlannerValidationError.invalidCommand }
    }

    public func validate(_ command: ReminderCreateRequest) throws {
        guard validTitle(command.title), command.collectionNativeLocator.map(validLocator) ?? true,
              command.notes.map { $0.utf8.count <= 1_000_000 && !$0.contains("\0") } ?? true,
              command.url.map(validURL) ?? true, command.priority.map { (0 ... 9).contains($0) } ?? true
        else { throw PlannerValidationError.invalidCommand }
        try command.due.map(validateDate)
        try command.start.map(validateDate)
        try validateSchedule(command.alarms, command.recurrenceRules)
    }

    public func validate(_ command: ReminderUpdateRequest) throws {
        guard validLocator(command.nativeLocator), !command.changes.isEmpty else {
            throw PlannerValidationError.invalidCommand
        }
        if case let .set(value)? = command.changes.title { guard validTitle(value) else { throw PlannerValidationError.invalidCommand } }
        if case .clear? = command.changes.title { throw PlannerValidationError.invalidCommand }
        if case let .set(value)? = command.changes.collectionNativeLocator { guard validLocator(value) else { throw PlannerValidationError.invalidCommand } }
        if case .clear? = command.changes.collectionNativeLocator { throw PlannerValidationError.invalidCommand }
        if case let .set(value)? = command.changes.notes { guard value.utf8.count <= 1_000_000 && !value.contains("\0") else { throw PlannerValidationError.invalidCommand } }
        if case let .set(value)? = command.changes.url { guard validURL(value) else { throw PlannerValidationError.invalidCommand } }
        if case let .set(value)? = command.changes.priority { guard (0 ... 9).contains(value) else { throw PlannerValidationError.invalidCommand } }
        if case let .set(value)? = command.changes.due { try validateDate(value) }
        if case let .set(value)? = command.changes.start { try validateDate(value) }
        if case let .set(value)? = command.changes.alarms { try validateSchedule(value, nil) }
        if case let .set(value)? = command.changes.recurrenceRules { try validateSchedule(nil, value) }
    }

    public func validate(_ batch: ReminderCommandValidateRequest) throws {
        guard !batch.commands.isEmpty, batch.commands.count <= 1_000 else { throw PlannerValidationError.invalidCommand }
        for command in batch.commands {
            switch command {
            case let .create(value): try validate(value)
            case let .update(value): try validate(value)
            case let .delete(value), let .complete(value), let .reopen(value): try validate(value)
            }
        }
    }

    private func validateDate(_ value: ReminderDate) throws {
        guard (1 ... 9_999).contains(value.year), (1 ... 12).contains(value.month), (1 ... 31).contains(value.day),
              value.hour.map { (0 ... 23).contains($0) } ?? true,
              value.minute.map { (0 ... 59).contains($0) } ?? true,
              value.second.map { (0 ... 59).contains($0) } ?? true,
              (value.hour == nil && value.minute == nil && value.second == nil) || (value.hour != nil && value.minute != nil),
              value.timeZone.map { TimeZone(identifier: $0) != nil } ?? true
        else { throw PlannerValidationError.invalidCommand }
        var components = DateComponents(); components.calendar = Calendar(identifier: .gregorian)
        components.year = value.year; components.month = value.month; components.day = value.day
        components.hour = value.hour; components.minute = value.minute; components.second = value.hour == nil ? nil : (value.second ?? 0)
        components.timeZone = value.timeZone.flatMap(TimeZone.init(identifier:))
        guard components.isValidDate else { throw PlannerValidationError.invalidCommand }
    }

    private func validateSchedule(_ alarms: [EventAlarm]?, _ recurrence: [EventRecurrenceRule]?) throws {
        guard alarms.map({ !$0.isEmpty && $0.count <= 64 }) ?? true,
              recurrence.map({ !$0.isEmpty && $0.count == 1 }) ?? true
        else { throw PlannerValidationError.invalidCommand }
    }
    private func validTitle(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 1_024 && !value.contains("\0") }
    private func validLocator(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 4_096 && !value.contains("\0") }
    private func validURL(_ value: String) -> Bool { value.utf8.count <= 16_384 && !value.contains("\0") && URL(string: value)?.scheme != nil }
}
