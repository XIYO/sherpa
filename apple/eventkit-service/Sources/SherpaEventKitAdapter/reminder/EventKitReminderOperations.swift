import SherpaWorkerProtocol
import SherpaPlannerContract
@preconcurrency import EventKit
import Foundation

final class EventKitReminderOperations {
  private let store: EKEventStore

  init(store: EKEventStore) {
    self.store = store
  }

  func list(_ command: ReminderListRequest) async throws -> ReminderListResult {
    // Decode the complete untrusted payload before resolving a native list.
    // In particular, a malformed limit or completion filter must not turn
    // into a not-found result merely because its accompanying list was
    // deleted between the caller's read and this request.
    let listReference = command.collectionNativeLocator
    let completed = command.completed
    let limit = command.limit ?? 100
    let calendars = try selectedLists(reference: listReference)
    let predicate =
      switch completed {
      case true:
        store.predicateForCompletedReminders(
          withCompletionDateStarting: nil,
          ending: nil,
          calendars: calendars
        )
      case false:
        store.predicateForIncompleteReminders(
          withDueDateStarting: nil,
          ending: nil,
          calendars: calendars
        )
      case nil:
        store.predicateForReminders(in: calendars)
      }
    let reminders = await fetchReminders(matching: predicate).values
      .filter { reminder in
        completed.map { reminder.isCompleted == $0 } ?? true
      }
      .sorted { reminderSortKey($0) < reminderSortKey($1) }
    return ReminderListResult(reminders: reminders.prefix(limit).map(reminderSnapshot))
  }

  func get(_ command: ReminderGetRequest) throws -> ReminderItemResult {
    ReminderItemResult(operation: "get", reminder: reminderSnapshot(try existingReminder(command.nativeLocator)))
  }

  func create(_ command: ReminderCreateRequest) throws -> ReminderItemResult {
    // Validate every field first.  The subsequent list lookup is an
    // EventKit boundary, so it must not mask malformed protocol input.
    let reminder = EKReminder(eventStore: store)
    reminder.title = command.title
    reminder.calendar = try writableCalendar(
      store: store,
      reference: command.collectionNativeLocator,
      entity: .reminder
    )
    reminder.notes = command.notes
    reminder.url = try command.url.map(reminderURL)
    reminder.priority = command.priority ?? 0
    reminder.dueDateComponents = command.due.map(reminderDateComponents)
    reminder.startDateComponents = command.start.map(reminderDateComponents)
    reminder.alarms = try eventKitAlarms(command.alarms)
    reminder.recurrenceRules = try eventKitRecurrenceRules(command.recurrenceRules)
    try store.save(reminder, commit: true)
    return ReminderItemResult(operation: "create", reminder: reminderSnapshot(try readBack(reminder)))
  }

  func update(_ command: ReminderUpdateRequest) throws -> ReminderItemResult {
    let changes = command.changes
    // Reject malformed cross-process input before resolving a native item.
    // This keeps invalid schedule payloads away from EventKit and makes the
    // protocol error deterministic even when the supplied reference is gone.
    let reminder = try existingReminder(command.nativeLocator)
    if let change = changes.title { reminder.title = try reminderRequiredSet(change) }
    if let change = changes.collectionNativeLocator {
      reminder.calendar = try writableCalendar(
        store: store,
        reference: try reminderRequiredSet(change),
        entity: .reminder
      )
    }
    if let change = changes.notes { reminder.notes = reminderOptionalSet(change) }
    if let change = changes.url { reminder.url = try reminderChangedOptional(change, transform: reminderURL) }
    if let change = changes.priority { reminder.priority = try reminderRequiredSet(change) }
    if let change = changes.due { reminder.dueDateComponents = reminderOptionalSet(change).map(reminderDateComponents) }
    if let change = changes.start { reminder.startDateComponents = reminderOptionalSet(change).map(reminderDateComponents) }
    if let change = changes.alarms { reminder.alarms = try reminderChangedCollection(change, eventKitAlarms) }
    if let change = changes.recurrenceRules { reminder.recurrenceRules = try reminderChangedCollection(change, eventKitRecurrenceRules) }
    try store.save(reminder, commit: true)
    return ReminderItemResult(operation: "update", reminder: reminderSnapshot(try readBack(reminder)))
  }

  func setCompleted(_ command: ReminderGetRequest, completed: Bool) async throws -> ReminderItemResult {
    let reminder = try existingReminder(command.nativeLocator)
    let calendarIdentifier = reminder.calendar.calendarIdentifier
    let completionStartedAt = Date()
    reminder.isCompleted = completed
    try store.save(reminder, commit: true)
    let verified: EKReminder
    if completed {
      let completionReadAt = Date()
      let predicate = store.predicateForCompletedReminders(
        withCompletionDateStarting: completionStartedAt.addingTimeInterval(-1),
        ending: completionReadAt.addingTimeInterval(1),
        calendars: [reminder.calendar]
      )
      let matches = await fetchReminders(matching: predicate).values.filter {
        $0.calendar.calendarIdentifier == calendarIdentifier
          && $0.isCompleted
          && $0.completionDate.map {
            completionStartedAt.addingTimeInterval(-1) <= $0
              && $0 <= completionReadAt.addingTimeInterval(1)
          } == true
      }
      guard matches.count == 1, let completedOccurrence = matches.first else {
        throw EventKitWorkerError.verificationFailed
      }
      verified = completedOccurrence
    } else {
      verified = try readBack(reminder)
    }
    // EventKit owns the completion timestamp.  A state-only check would allow
    // a stale native completion marker to pass a reopen verification.
    guard verified.isCompleted == completed,
          completed ? verified.completionDate != nil : verified.completionDate == nil
    else { throw EventKitWorkerError.verificationFailed }
    return ReminderItemResult(operation: completed ? "complete" : "reopen", reminder: reminderSnapshot(verified))
  }

  func delete(_ command: ReminderDeleteRequest) throws -> ReminderDeleteResult {
    let reminder = try existingReminder(command.nativeLocator)
    let reference = reminder.calendarItemIdentifier
    try store.remove(reminder, commit: true)
    guard store.calendarItem(withIdentifier: reference) == nil else {
      throw EventKitWorkerError.verificationFailed
    }
    return ReminderDeleteResult()
  }

  func existingReminder(_ reference: String) throws -> EKReminder {
    guard let reminder = store.calendarItem(withIdentifier: reference) as? EKReminder else {
      throw EventKitWorkerError.notFound
    }
    return reminder
  }

  func readBack(_ reminder: EKReminder) throws -> EKReminder {
    guard
      let verified = store.calendarItem(withIdentifier: reminder.calendarItemIdentifier)
        as? EKReminder
    else {
      throw EventKitWorkerError.verificationFailed
    }
    return verified
  }

  private func selectedLists(reference: String?) throws -> [EKCalendar]? {
    guard let reference else {
      return nil
    }
    guard
      let list = store.calendars(for: .reminder).first(where: {
        $0.calendarIdentifier == reference
      })
    else {
      throw EventKitWorkerError.notFound
    }
    return [list]
  }

  private func fetchReminders(matching predicate: NSPredicate) async -> FetchedReminders {
    await withCheckedContinuation { continuation in
      store.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: FetchedReminders(values: reminders ?? []))
      }
    }
  }
}

/// EventKit predates Swift concurrency. The callback hands ownership of this
/// immutable result batch to the awaiting task, where it is consumed once.
private struct FetchedReminders: @unchecked Sendable {
  let values: [EKReminder]
}

private func reminderURL(_ value: String) throws -> URL {
  guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { throw WorkerProtocolError.invalidPayload }
  return url
}

private func reminderDateComponents(_ value: ReminderDate) -> DateComponents {
  var result = DateComponents(); result.calendar = Calendar(identifier: .gregorian)
  result.year = value.year; result.month = value.month; result.day = value.day
  result.hour = value.hour; result.minute = value.minute; result.second = value.second
  result.timeZone = value.timeZone.flatMap(TimeZone.init(identifier:))
  return result
}

private func reminderRequiredSet<T>(_ change: ReminderChange<T>) throws -> T {
  guard case let .set(value) = change else { throw WorkerProtocolError.invalidPayload }; return value
}
private func reminderOptionalSet<T>(_ change: ReminderChange<T>) -> T? {
  if case let .set(value) = change { return value }; return nil
}
private func reminderChangedOptional<T, U>(_ change: ReminderChange<T>, transform: (T) throws -> U) throws -> U? {
  switch change { case .clear: nil; case let .set(value): try transform(value) }
}
private func reminderChangedCollection<T, U>(_ change: ReminderChange<[T]>, _ transform: ([T]?) throws -> [U]?) throws -> [U]? {
  switch change { case .clear: nil; case let .set(values): try transform(values) }
}
