import SherpaPlannerContract
import Foundation

/// Marker for the semantic-authority layer. Concrete use cases migrate here
/// without allowing EventKit types to enter the provider-neutral contract.
public enum SherpaPlannerApplicationBoundary: Sendable {}

public enum PlannerValidationError: Error, Sendable { case invalidCommand }

public struct EventCommandValidator: Sendable {
    public init() {}

    public func validate(_ batch: EventCommandValidateRequest) throws -> EventCommandValidateResult {
        guard batch.schema == "sherpa.planner.event-command-validate.request.v2",
              (1 ... 64).contains(batch.commands.count)
        else { throw PlannerValidationError.invalidCommand }
        // Complete the entire provider-neutral preflight before a caller may
        // invoke an Event port. This is deliberately all-or-nothing.
        for command in batch.commands {
            switch command {
            case let .create(value): try validate(value)
            case let .update(value): try validate(value)
            case let .delete(value): try validate(value)
            }
        }
        return EventCommandValidateResult(commandCount: batch.commands.count)
    }

    public func validate(_ command: EventCreateRequest) throws {
        guard !command.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command.title.utf8.count <= 1_024,
              let start = Self.date(command.start), let end = Self.date(command.end), start < end,
              command.collectionNativeLocator.map(Self.validLocator) ?? true,
              command.timeZone.map({ TimeZone(identifier: $0) != nil }) ?? true,
              command.url.map(Self.validURL) ?? true
        else { throw PlannerValidationError.invalidCommand }
        try validateSchedule(alarms: command.alarms, recurrence: command.recurrenceRules)
    }

    public func validate(_ command: EventListRequest) throws {
        guard let start = Self.date(command.from), let end = Self.date(command.to), start < end,
              (command.limit.map { (1 ... 10_000).contains($0) } ?? true),
              command.collectionNativeLocator.map(Self.validLocator) ?? true
        else { throw PlannerValidationError.invalidCommand }
    }

    public func validate(_ command: EventGetRequest) throws {
        guard Self.validLocator(command.nativeLocator) else { throw PlannerValidationError.invalidCommand }
    }

    public func validate(_ command: EventDeleteRequest) throws {
        guard Self.validLocator(command.nativeLocator), ["this", "future"].contains(command.span)
        else { throw PlannerValidationError.invalidCommand }
    }

    public func validate(_ command: EventUpdateRequest) throws {
        guard Self.validLocator(command.nativeLocator), ["this", "future"].contains(command.span),
              !command.changes.isEmpty
        else { throw PlannerValidationError.invalidCommand }
        // The adapter validates the resulting range against the freshly read
        // native item; paired patch endpoints can be rejected before I/O.
        if case let .set(start)? = command.changes.start,
           case let .set(end)? = command.changes.end,
           let startDate = Self.date(start), let endDate = Self.date(end), startDate >= endDate {
            throw PlannerValidationError.invalidCommand
        }
        if case let .set(title)? = command.changes.title,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PlannerValidationError.invalidCommand
        }
        if case .clear? = command.changes.title { throw PlannerValidationError.invalidCommand }
        if case let .set(zone)? = command.changes.timeZone, TimeZone(identifier: zone) == nil {
            throw PlannerValidationError.invalidCommand
        }
        if case let .set(url)? = command.changes.url, !Self.validURL(url) {
            throw PlannerValidationError.invalidCommand
        }
        if case let .set(alarms)? = command.changes.alarms { try validateSchedule(alarms: alarms, recurrence: nil) }
        if case let .set(rules)? = command.changes.recurrenceRules { try validateSchedule(alarms: nil, recurrence: rules) }
    }

    private func validateSchedule(alarms: [EventAlarm]?, recurrence: [EventRecurrenceRule]?) throws {
        guard alarms.map({ !$0.isEmpty && $0.count <= 64 }) ?? true,
              recurrence.map({ !$0.isEmpty && $0.count == 1 }) ?? true
        else { throw PlannerValidationError.invalidCommand }
    }
    private static func validLocator(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 4_096 && !value.contains("\0") }
    private static func validURL(_ value: String) -> Bool { value.utf8.count <= 16_384 && URL(string: value)?.scheme != nil }
    private static func date(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }
}
