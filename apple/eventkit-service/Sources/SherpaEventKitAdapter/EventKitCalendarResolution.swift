import SherpaWorkerProtocol
@preconcurrency import EventKit

func writableCalendar(
    store: EKEventStore,
    reference: String?,
    entity: EKEntityType
) throws -> EKCalendar {
    let calendar: EKCalendar?
    if let reference {
        calendar = store.calendars(for: entity).first { $0.calendarIdentifier == reference }
    } else if entity == .event {
        calendar = store.defaultCalendarForNewEvents
    } else {
        calendar = store.defaultCalendarForNewReminders()
    }
    guard let calendar else { throw EventKitWorkerError.notFound }
    try requireWritableDestination(allowsContentModifications: calendar.allowsContentModifications)
    return calendar
}

func requireWritableDestination(allowsContentModifications: Bool) throws {
    guard allowsContentModifications else {
        throw EventKitWorkerError.readOnlyDestination
    }
}
