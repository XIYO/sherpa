import SherpaWorkerProtocol
import SherpaPlannerContract
@preconcurrency import EventKit
import Foundation

final class EventKitEventOperations {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func list(_ command: EventListRequest) throws -> EventListResult {
        guard let start = parseDate(command.from), let end = parseDate(command.to), start < end else {
            throw WorkerProtocolError.invalidPayload
        }
        let limit = command.limit ?? 100
        let calendarReference = command.collectionNativeLocator
        let calendars = try selectedCalendars(reference: calendarReference)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let entries = try validatedListEntries(
            store.events(matching: predicate),
            from: start,
            to: end,
            selectedCalendarReference: calendarReference
        )
        return EventListResult(events: try Array(entries.prefix(limit).map { try eventSnapshot($0.event) }), from: command.from, to: command.to)
    }

    func get(_ command: EventGetRequest) throws -> EventItemResult {
        EventItemResult(operation: "get", event: try eventSnapshot(try existingEvent(command.nativeLocator)))
    }

    func create(_ command: EventCreateRequest) throws -> EventItemResult {
        let event = EKEvent(eventStore: store)
        event.title = command.title
        guard let requestedStart = parseDate(command.start), let requestedEnd = parseDate(command.end) else { throw WorkerProtocolError.invalidPayload }
        guard requestedStart < requestedEnd else { throw WorkerProtocolError.invalidPayload }
        let isAllDay = command.allDay ?? false
        event.timeZone = try command.timeZone.map(validTimeZone)
        event.startDate = requestedStart
        event.endDate = eventKitAllDayEnd(
            requestedEnd,
            isAllDay: isAllDay,
            timeZone: event.timeZone ?? .current
        )
        event.isAllDay = isAllDay
        guard event.startDate < event.endDate else { throw WorkerProtocolError.invalidPayload }
        event.calendar = try writableCalendar(
            store: store,
            reference: command.collectionNativeLocator,
            entity: .event
        )
        event.notes = command.notes; event.location = command.location
        event.url = try command.url.map(validURL)
        event.alarms = try eventKitAlarms(command.alarms)
        event.recurrenceRules = try eventKitRecurrenceRules(command.recurrenceRules)
        try store.save(event, span: .thisEvent, commit: true)
        return EventItemResult(operation: "create", event: try eventSnapshot(try readBack(event)))
    }

    func update(_ command: EventUpdateRequest) throws -> EventItemResult {
        let changes = command.changes
        let span = try eventSpan(command.span)
        // Reject malformed cross-process input before resolving a native item.
        // That makes rejected payloads deterministic even if the supplied
        // reference no longer exists, and keeps invalid schedule values away
        // from EventKit's Objective-C boundary.
        let event = try existingEvent(command.nativeLocator)
        guard let originalStart = event.startDate,
              let originalCalendar = event.calendar,
              let originalEventIdentifier = event.eventIdentifier,
              !originalEventIdentifier.isEmpty
        else { throw EventKitWorkerError.verificationFailed }
        let requestedStart = try changedDate(changes.start)
        let wasAllDay = event.isAllDay
        let targetAllDay = try changedValue(changes.allDay, current: event.isAllDay)
        if wasAllDay && !targetAllDay {
            event.isAllDay = false
        }
        if let change = changes.timeZone { event.timeZone = try changedOptional(change, transform: validTimeZone) }
        if let change = changes.title { event.title = try requiredSet(change) }
        if let requestedStart { event.startDate = requestedStart }
        if let change = changes.end {
            guard case let .set(encoded) = change, let requestedEnd = parseDate(encoded) else { throw WorkerProtocolError.invalidPayload }
            event.endDate = eventKitAllDayEnd(
                requestedEnd,
                isAllDay: targetAllDay,
                timeZone: event.timeZone ?? .current
            )
        }
        guard event.startDate < event.endDate else { throw WorkerProtocolError.invalidPayload }
        if !wasAllDay && targetAllDay {
            event.isAllDay = true
        }
        if let change = changes.collectionNativeLocator {
            event.calendar = try writableCalendar(
                store: store,
                reference: try requiredSet(change),
                entity: .event
            )
        }
        if let change = changes.notes { event.notes = optionalSet(change) }
        if let change = changes.location { event.location = optionalSet(change) }
        if let change = changes.url { event.url = try changedOptional(change, transform: validURL) }
        if let change = changes.alarms { event.alarms = try changedCollection(change, eventKitAlarms) }
        if let change = changes.recurrenceRules { event.recurrenceRules = try changedCollection(change, eventKitRecurrenceRules) }
        try store.save(event, span: span, commit: true)
        try removeStaleFutureSeriesOccurrence(
            span: span,
            originalStart: originalStart,
            originalEventIdentifier: originalEventIdentifier,
            calendar: originalCalendar,
            requestedStart: requestedStart,
            updatedEvent: event
        )
        return EventItemResult(operation: "update", event: try eventSnapshot(try readBack(event)))
    }

    func delete(_ command: EventDeleteRequest) throws -> EventDeleteResult {
        let locator = try eventLocator(command.nativeLocator)
        guard let event = findEvent(locator) else { throw EventKitWorkerError.notFound }
        try store.remove(event, span: try eventSpan(command.span), commit: true)
        guard findEvent(locator) == nil else { throw EventKitWorkerError.verificationFailed }
        return EventDeleteResult()
    }

    func existingEvent(_ nativeLocator: String) throws -> EKEvent {
        let locator = try eventLocator(nativeLocator)
        guard let event = findEvent(locator) else {
            throw EventKitWorkerError.notFound
        }
        return event
    }

    func eventLocator(_ nativeLocator: String) throws -> EventLocator {
        try EventLocator(wireValue: nativeLocator)
    }

    func findEvent(_ locator: EventLocator) -> EKEvent? {
        if locator.occurrenceDate == nil {
            return store.event(withIdentifier: locator.eventIdentifier)
        }
        if let direct = store.event(withIdentifier: locator.eventIdentifier), locator.matches(direct) {
            return direct
        }
        return findEventInCalendar(locator, calendar: nil)
    }

    private func findEventInCalendar(
        _ locator: EventLocator, calendar: EKCalendar?
    ) -> EKEvent? {
        var centers = [locator.occurrenceDate, locator.observedStartDate].compactMap { $0 }
        var visited = Set<Date>()
        centers.removeAll { !visited.insert($0).inserted }
        for center in centers {
            let predicate = store.predicateForEvents(
                withStart: center.addingTimeInterval(-1),
                end: center.addingTimeInterval(1),
                calendars: calendar.map { [$0] }
            )
            if let event = store.events(matching: predicate).first(where: locator.matches) {
                return event
            }
        }
        return nil
    }

    func readBack(_ event: EKEvent) throws -> EKEvent {
        let locator = try EventLocator(event: event)
        if let verified = findEvent(locator) {
            return verified
        }
        // EventKit can rewrite the occurrence metadata of an explicitly zoned
        // all-day item while keeping its exact item identity and local day.
        // Accept that provider normalization only when the direct identifier,
        // destination Calendar, all-day state, and local start day all agree.
        if event.isAllDay,
           let identifier = event.eventIdentifier,
           let expectedCalendar = event.calendar,
           let expectedStart = event.startDate,
           let direct = store.event(withIdentifier: identifier),
           direct.isAllDay,
           direct.eventIdentifier == identifier,
           direct.calendar.calendarIdentifier == expectedCalendar.calendarIdentifier,
           let actualStart = direct.startDate
        {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = event.timeZone ?? direct.timeZone ?? .current
            if calendar.isDate(actualStart, inSameDayAs: expectedStart) {
                return direct
            }
        }
        throw EventKitWorkerError.verificationFailed
    }

    /// On macOS EventKit can retain the pre-split occurrence after a future
    /// mutation. The save creates the replacement branch but can leave the
    /// original branch active on the split date, even when the start time did
    /// not change. Trim only when both sides are proven: the original event
    /// identifier still resolves at the original start and a distinct updated
    /// identifier resolves at the replacement start.
    private func removeStaleFutureSeriesOccurrence(
        span: EKSpan,
        originalStart: Date,
        originalEventIdentifier: String,
        calendar: EKCalendar,
        requestedStart: Date?,
        updatedEvent: EKEvent
    ) throws {
        guard let replacementStart = requestedStart ?? updatedEvent.startDate,
              let stale = event(
                  calendar: calendar,
                  eventIdentifier: originalEventIdentifier,
                  startingAt: originalStart
              ),
              let replacementIdentifier = updatedEvent.eventIdentifier,
              let replacement = event(
                  calendar: calendar,
                  eventIdentifier: replacementIdentifier,
                  startingAt: replacementStart
              )
        else { return }
        guard shouldTrimStaleFutureSeries(
            span: span,
            originalStart: originalStart,
            requestedStart: replacementStart,
            staleStart: stale.startDate,
            replacementStart: replacement.startDate,
            distinctEvents: stale.eventIdentifier != replacement.eventIdentifier
        ) else { return }
        // EventKit has already split the recurrence before exposing this stale
        // generated occurrence.  Removing it with `.futureEvents` addresses
        // the original (now-ended) branch and leaves the generated instance in
        // place.  Remove exactly this proven duplicate instead; the new branch
        // remains responsible for all later occurrences.
        try store.remove(stale, span: .thisEvent, commit: true)
        // A successful EventKit call is not verification. Re-resolve the exact
        // pre-split occurrence: if it survives, returning a successful update
        // would expose two appointments for one user command.
        guard event(
            calendar: calendar,
            eventIdentifier: originalEventIdentifier,
            startingAt: originalStart
        ) == nil else {
            throw EventKitWorkerError.verificationFailed
        }
    }

    private func event(
        calendar: EKCalendar, eventIdentifier: String, startingAt start: Date
    ) -> EKEvent? {
        let predicate = store.predicateForEvents(
            withStart: start.addingTimeInterval(-1),
            end: start.addingTimeInterval(1),
            calendars: [calendar]
        )
        return store.events(matching: predicate).first(where: {
            $0.eventIdentifier == eventIdentifier && sameInstant($0.startDate, start)
        })
    }

    private func selectedCalendars(reference: String?) throws -> [EKCalendar]? {
        guard let reference else {
            return nil
        }
        guard let calendar = store.calendars(for: .event).first(where: {
            $0.calendarIdentifier == reference
        }) else {
            throw EventKitWorkerError.notFound
        }
        return [calendar]
    }

    private func validatedListEntries(
        _ nativeEvents: [EKEvent],
        from: Date,
        to: Date,
        selectedCalendarReference: String?
    ) throws -> [EventListEntry] {
        var references = Set<String>()
        var entries = [EventListEntry]()
        for event in deduplicatedEventOccurrences(nativeEvents) {
            guard let calendar = event.calendar,
                  let eventStart = event.startDate,
                  let eventEnd = event.endDate,
                  eventListRowIsWithinRange(start: eventStart, end: eventEnd, from: from, to: to),
                  eventListCalendarMatches(
                      returnedReference: calendar.calendarIdentifier,
                      selectedReference: selectedCalendarReference
                  )
            else { throw EventKitWorkerError.verificationFailed }
            let reference: String
            do {
                reference = try EventLocator(event: event).wireValue
            } catch {
                // A malformed native result is not malformed caller input.
                throw EventKitWorkerError.verificationFailed
            }
            guard eventListReferenceWasNotSeen(reference, seen: &references) else {
                throw EventKitWorkerError.verificationFailed
            }
            entries.append(EventListEntry(
                event: event,
                sortKey: eventListSortKey(
                    start: eventStart,
                    title: event.title ?? "",
                    reference: reference
                )
            ))
        }
        return entries.sorted { $0.sortKey < $1.sortKey }
    }
}

private struct EventListEntry {
    let event: EKEvent
    let sortKey: EventListSortKey
}

struct EventListSortKey: Comparable, Equatable {
    let start: Date
    let title: String
    let reference: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.reference < rhs.reference
    }
}

func eventListSortKey(start: Date, title: String, reference: String) -> EventListSortKey {
    EventListSortKey(start: start, title: title, reference: reference)
}

/// EventKit predicates are an optimization, not a trust boundary. Every native
/// event must independently overlap Sherpa's half-open query range.
func eventListRowIsWithinRange(start: Date, end: Date, from: Date, to: Date) -> Bool {
    start < end && start < to && end > from
}

func eventListCalendarMatches(returnedReference: String, selectedReference: String?) -> Bool {
    selectedReference.map { $0 == returnedReference } ?? true
}

func eventListReferenceWasNotSeen(_ reference: String, seen: inout Set<String>) -> Bool {
    seen.insert(reference).inserted
}

private func eventSpan(_ value: String) throws -> EKSpan {
    switch value { case "this": .thisEvent; case "future": .futureEvents; default: throw WorkerProtocolError.invalidPayload }
}

private func validURL(_ value: String) throws -> URL {
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { throw WorkerProtocolError.invalidPayload }
    return url
}

private func validTimeZone(_ value: String) throws -> TimeZone {
    guard let zone = TimeZone(identifier: value) else { throw WorkerProtocolError.invalidPayload }
    return zone
}

private func requiredSet<T>(_ change: EventChange<T>) throws -> T {
    guard case let .set(value) = change else { throw WorkerProtocolError.invalidPayload }
    return value
}

private func optionalSet<T>(_ change: EventChange<T>) -> T? {
    if case let .set(value) = change { return value }
    return nil
}

private func changedValue<T>(_ change: EventChange<T>?, current: T) throws -> T {
    guard let change else { return current }
    return try requiredSet(change)
}

private func changedOptional<T, U>(_ change: EventChange<T>, transform: (T) throws -> U) throws -> U? {
    switch change { case .clear: nil; case let .set(value): try transform(value) }
}

private func changedCollection<T, U>(_ change: EventChange<[T]>, _ transform: ([T]?) throws -> [U]?) throws -> [U]? {
    switch change { case .clear: nil; case let .set(values): try transform(values) }
}

private func changedDate(_ change: EventChange<String>?) throws -> Date? {
    guard let change else { return nil }
    guard case let .set(value) = change, let date = parseDate(value) else { throw WorkerProtocolError.invalidPayload }
    return date
}
