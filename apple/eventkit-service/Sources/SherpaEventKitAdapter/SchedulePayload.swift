import SherpaWorkerProtocol
import SherpaPlannerContract
@preconcurrency import EventKit
import Foundation

func eventKitAlarms(_ values: [EventAlarm]?) throws -> [EKAlarm]? {
    guard let values else { return nil }
    return try values.map { value in
        switch value {
        case let .absolute(date):
            guard let parsed = parseDate(date) else { throw WorkerProtocolError.invalidPayload }
            return EKAlarm(absoluteDate: parsed)
        case let .relative(offsetSeconds): return EKAlarm(relativeOffset: TimeInterval(offsetSeconds))
        }
    }
}

func eventKitRecurrenceRules(_ values: [EventRecurrenceRule]?) throws -> [EKRecurrenceRule]? {
    try values?.map(eventKitRecurrenceRule)
}

private func eventKitRecurrenceRule(_ value: EventRecurrenceRule) throws -> EKRecurrenceRule {
    let frequency: EKRecurrenceFrequency = switch value.frequency {
    case "daily": .daily; case "weekly": .weekly; case "monthly": .monthly; case "yearly": .yearly
    default: throw WorkerProtocolError.invalidPayload
    }
    let days = try value.daysOfWeek?.map { value in
        guard let weekday = EKWeekday(rawValue: value.dayOfWeek) else { throw WorkerProtocolError.invalidPayload }
        return EKRecurrenceDayOfWeek(weekday, weekNumber: value.weekNumber)
    }
    let end: EKRecurrenceEnd? = try value.end.map { value in
        switch value.kind {
        case "date":
            guard let encoded = value.date, value.count == nil, let date = parseDate(encoded) else { throw WorkerProtocolError.invalidPayload }
            return EKRecurrenceEnd(end: date)
        case "count":
            guard value.date == nil, let count = value.count else { throw WorkerProtocolError.invalidPayload }
            return EKRecurrenceEnd(occurrenceCount: count)
        default: throw WorkerProtocolError.invalidPayload
        }
    }
    return EKRecurrenceRule(
        recurrenceWith: frequency, interval: value.interval, daysOfTheWeek: days,
        daysOfTheMonth: value.daysOfMonth?.map(NSNumber.init(value:)),
        monthsOfTheYear: value.monthsOfYear?.map(NSNumber.init(value:)),
        weeksOfTheYear: value.weeksOfYear?.map(NSNumber.init(value:)),
        daysOfTheYear: value.daysOfYear?.map(NSNumber.init(value:)),
        setPositions: value.setPositions?.map(NSNumber.init(value:)), end: end
    )
}
