import SherpaWorkerProtocol
import SherpaPlannerContract
@preconcurrency import EventKit
import Foundation

func parseDate(_ value: String) -> Date? {
    makeWireDateFormatter().date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

func eventSnapshot(_ event: EKEvent) throws -> EventSnapshot {
    guard let start = wireDate(event.startDate), let end = wireDate(canonicalAllDayEnd(event.endDate, isAllDay: event.isAllDay, timeZone: event.timeZone ?? .current)) else { throw EventKitWorkerError.verificationFailed }
    return EventSnapshot(
        nativeLocator: try EventLocator(event: event).wireValue,
        eventCollection: eventCollectionSnapshot(event.calendar), title: event.title ?? "",
        start: start, end: end, allDay: event.isAllDay, timeZone: event.timeZone?.identifier,
        notes: stringField(event.notes), location: stringField(event.location), url: stringField(event.url?.absoluteString),
        occurrenceDate: wireDate(event.occurrenceDate), detached: event.isDetached,
        status: eventStatus(event.status), availability: eventAvailability(event.availability),
        alarms: collectionField(event.alarms?.map(alarmSnapshot)),
        recurrenceRules: collectionField(event.recurrenceRules?.map(recurrenceSnapshot))
    )
}

func reminderSnapshot(_ reminder: EKReminder) -> ReminderSnapshot {
    ReminderSnapshot(
        nativeLocator: reminder.calendarItemIdentifier,
        collection: reminderCollectionSnapshot(reminder.calendar), title: reminder.title ?? "",
        notes: reminder.notes, url: reminder.url?.absoluteString, completed: reminder.isCompleted,
        completionDate: wireDate(reminder.completionDate), priority: reminder.priority,
        due: reminderDate(reminder.dueDateComponents), start: reminderDate(reminder.startDateComponents),
        alarms: collectionField(reminder.alarms?.map(alarmSnapshot)),
        recurrenceRules: collectionField(reminder.recurrenceRules?.map(recurrenceSnapshot))
    )
}

func eventCollectionSnapshot(_ calendar: EKCalendar) -> EventCollectionSnapshot {
    .init(nativeLocator: calendar.calendarIdentifier, title: calendar.title, type: calendarType(calendar.type), allowsContentModifications: calendar.allowsContentModifications)
}

func reminderCollectionSnapshot(_ calendar: EKCalendar) -> ReminderCollectionSnapshot {
    .init(nativeLocator: calendar.calendarIdentifier, title: calendar.title, type: calendarType(calendar.type), allowsContentModifications: calendar.allowsContentModifications)
}

func calendarSnapshot(_ calendar: EKCalendar) -> ReminderCollectionSnapshot {
    reminderCollectionSnapshot(calendar)
}

func reminderSortKey(_ reminder: EKReminder) -> String {
    reminderSortKey(
        completed: reminder.isCompleted,
        due: reminder.dueDateComponents,
        title: reminder.title ?? "",
        reference: reminder.calendarItemIdentifier
    )
}

func reminderSortKey(
    completed: Bool, due: DateComponents?, title: String, reference: String
) -> String {
    let due = due.map { components in
        String(format: "%04d-%02d-%02dT%02d:%02d", components.year ?? 0,
               components.month ?? 0, components.day ?? 0, components.hour ?? 0,
               components.minute ?? 0)
    } ?? "9999-99-99T99:99"
    return "\(completed ? 1 : 0)|\(due)|\(title)|\(reference)"
}

private func makeWireDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}

private func wireDate(_ value: Date?) -> String? {
    value.map { makeWireDateFormatter().string(from: $0) }
}

/// EventKit calendars may expose an all-day event's final boundary as the
/// inclusive local 23:59:59. Sherpa's canonical event range is half-open, so
/// normalize only that exact provider representation to next-day midnight.
func canonicalAllDayEnd(
    _ value: Date?,
    isAllDay: Bool,
    timeZone: TimeZone
) -> Date? {
    guard let value, isAllDay else { return value }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: value)
    guard components.hour == 23,
          components.minute == 59,
          components.second == 59,
          components.nanosecond == 0
    else { return value }
    return calendar.date(byAdding: .second, value: 1, to: value)
}

/// Convert Sherpa's half-open all-day end boundary to EventKit's inclusive
/// final second. Without this inverse conversion, EventKit interprets an
/// exclusive midnight as another included calendar day.
func eventKitAllDayEnd(
    _ value: Date,
    isAllDay: Bool,
    timeZone: TimeZone
) -> Date {
    guard isAllDay else { return value }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: value)
    guard components.hour == 0,
          components.minute == 0,
          components.second == 0,
          components.nanosecond == 0,
          let inclusive = calendar.date(byAdding: .second, value: -1, to: value)
    else { return value }
    return inclusive
}

private func stringField(_ value: String?) -> SnapshotField<String> {
    .init(value.flatMap { $0.isEmpty ? nil : $0 })
}

func collectionField<T>(_ value: [T]?) -> SnapshotField<[T]> where T: Codable & Sendable & Equatable {
    .init(value.flatMap { $0.isEmpty ? nil : $0 })
}

private func alarmSnapshot(_ alarm: EKAlarm) -> AlarmSnapshot {
    .init(absoluteDate: wireDate(alarm.absoluteDate), relativeOffsetSeconds: alarm.relativeOffset, proximity: alarmProximity(alarm.proximity), structuredLocation: alarm.structuredLocation?.title)
}

private func recurrenceSnapshot(_ rule: EKRecurrenceRule) -> RecurrenceSnapshot {
    .init(frequency: recurrenceFrequency(rule.frequency), interval: rule.interval,
          firstDayOfWeek: rule.firstDayOfTheWeek, occurrenceCount: rule.recurrenceEnd?.occurrenceCount ?? 0,
          endDate: wireDate(rule.recurrenceEnd?.endDate),
          daysOfWeek: rule.daysOfTheWeek?.map { .init(dayOfWeek: $0.dayOfTheWeek.rawValue, weekNumber: $0.weekNumber) } ?? [],
          daysOfMonth: rule.daysOfTheMonth?.map(\.intValue) ?? [], monthsOfYear: rule.monthsOfTheYear?.map(\.intValue) ?? [],
          weeksOfYear: rule.weeksOfTheYear?.map(\.intValue) ?? [], daysOfYear: rule.daysOfTheYear?.map(\.intValue) ?? [],
          setPositions: rule.setPositions?.map(\.intValue) ?? [])
}

private func reminderDate(_ value: DateComponents?) -> ReminderDate? {
    guard let value, let year = value.year, let month = value.month, let day = value.day else { return nil }
    return ReminderDate(year: year, month: month, day: day, hour: value.hour, minute: value.minute, second: value.second, timeZone: value.timeZone?.identifier)
}

private func eventStatus(_ value: EKEventStatus) -> String {
    switch value {
    case .none: "none"
    case .confirmed: "confirmed"
    case .tentative: "tentative"
    case .canceled: "cancelled"
    @unknown default: "unknown"
    }
}

private func eventAvailability(_ value: EKEventAvailability) -> String {
    switch value {
    case .notSupported: "not_supported"
    case .busy: "busy"
    case .free: "free"
    case .tentative: "tentative"
    case .unavailable: "unavailable"
    @unknown default: "unknown"
    }
}

private func participantRole(_ value: EKParticipantRole) -> String {
    switch value {
    case .unknown: "unknown"
    case .required: "required"
    case .optional: "optional"
    case .chair: "chair"
    case .nonParticipant: "non_participant"
    @unknown default: "unknown"
    }
}

private func participantStatus(_ value: EKParticipantStatus) -> String {
    switch value {
    case .unknown: "unknown"
    case .pending: "pending"
    case .accepted: "accepted"
    case .declined: "declined"
    case .tentative: "tentative"
    case .delegated: "delegated"
    case .completed: "completed"
    case .inProcess: "in_process"
    @unknown default: "unknown"
    }
}

private func participantType(_ value: EKParticipantType) -> String {
    switch value {
    case .unknown: "unknown"
    case .person: "person"
    case .room: "room"
    case .resource: "resource"
    case .group: "group"
    @unknown default: "unknown"
    }
}

private func alarmProximity(_ value: EKAlarmProximity) -> String {
    switch value {
    case .none: "none"
    case .enter: "enter"
    case .leave: "leave"
    @unknown default: "unknown"
    }
}

private func recurrenceFrequency(_ value: EKRecurrenceFrequency) -> String {
    switch value {
    case .daily: "daily"
    case .weekly: "weekly"
    case .monthly: "monthly"
    case .yearly: "yearly"
    @unknown default: "unknown"
    }
}

func calendarType(_ value: EKCalendarType) -> String {
    switch value {
    case .local: "local"
    case .calDAV: "caldav"
    case .exchange: "exchange"
    case .subscription: "subscription"
    case .birthday: "birthday"
    @unknown default: "unknown"
    }
}

func sourceType(_ value: EKSourceType) -> String {
    switch value {
    case .local: "local"
    case .exchange: "exchange"
    case .calDAV: "caldav"
    case .mobileMe: "mobile_me"
    case .subscribed: "subscribed"
    case .birthdays: "birthdays"
    @unknown default: "unknown"
    }
}
