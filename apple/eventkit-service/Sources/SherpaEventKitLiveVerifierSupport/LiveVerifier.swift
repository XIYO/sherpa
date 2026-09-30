import Foundation
import SherpaWorkerProtocol
@_exported import SherpaPlannerContract

public enum LiveVerifierError: Error, Equatable, Sendable {
    case usage, liveGate, workerUnavailable, authorizationRequired
    case workerFailed, invalidResponse, verificationFailed, cleanupFailed

    public var stableCode: String {
        switch self {
        case .usage: "live_verifier.usage"
        case .liveGate: "live_verifier.write_disabled"
        case .workerUnavailable: "live_verifier.worker_unavailable"
        case .authorizationRequired: "live_verifier.authorization_required"
        case .workerFailed: "live_verifier.worker_failed"
        case .invalidResponse: "live_verifier.invalid_response"
        case .verificationFailed: "live_verifier.verification_failed"
        case .cleanupFailed: "live_verifier.cleanup_failed"
        }
    }
}

public enum LiveVerifierStage: String, Equatable, Sendable {
    case authorization
    case calendarSources = "calendar_sources"
    case calendarFailurePaths = "calendar_failure_paths"
    case calendarReads = "calendar_reads"
    case calendarCreate = "calendar_create"
    case secondCalendarCreate = "second_calendar_create"
    case recurringCreate = "recurring_create"
    case recurringReadback = "recurring_readback"
    case recurringVariants = "recurring_variants"
    case recurringRuleUpdate = "recurring_rule_update"
    case allDayLifecycle = "all_day_lifecycle"
    case timeZoneRoundTrip = "time_zone_round_trip"
    case dstAllDay = "dst_all_day"
    case dstRecurrence = "dst_recurrence"
    case recurringFutureCreate = "recurring_future_create"
    case recurringFutureReadback = "recurring_future_readback"
    case recurringFutureUpdate = "recurring_future_update"
    case recurringFutureBeforeReadback = "recurring_future_before_readback"
    case recurringFutureTargetReadback = "recurring_future_target_readback"
    case recurringFutureFollowingReadback = "recurring_future_following_readback"
    case recurringFutureDelete = "recurring_future_delete"
    case recurringFutureDeleteReadback = "recurring_future_delete_readback"
    case recurringFutureBeforeDeleteReadback = "recurring_future_before_delete_readback"
    case recurringFutureRuleUpdate = "recurring_future_rule_update"
    case recurringFutureRuleReadback = "recurring_future_rule_readback"
    case recurringFutureRuleDelete = "recurring_future_rule_delete"
    case futureOccurrence = "future_occurrence"
    case futureUpdate = "future_update"
    case futureReadback = "future_readback"
    case singleOccurrence = "single_occurrence"
    case singleUpdate = "single_update"
    case singleReadback = "single_readback"
    case singleDelete = "single_delete"
    case singleDeleteReadback = "single_delete_readback"
    case timedCreate = "timed_create"
    case timedReadback = "timed_readback"
    case timedUpdate = "timed_update"
    case timedUpdateReadback = "timed_update_readback"
    case timedClear = "timed_clear"
    case timedClearReadback = "timed_clear_readback"
    case timedMove = "timed_move"
    case timedMoveReadback = "timed_move_readback"
    case timedDelete = "timed_delete"
    case timedDeleteReadback = "timed_delete_readback"
    case reminderAuthorization = "reminder_authorization"
    case reminderFailurePaths = "reminder_failure_paths"
    case reminderSources = "reminder_sources"
    case reminderListCreate = "reminder_list_create"
    case reminderSecondListCreate = "reminder_second_list_create"
    case reminderCreate = "reminder_create"
    case reminderReadback = "reminder_readback"
    case reminderDates = "reminder_dates"
    case reminderDueDateOnly = "reminder_due_date_only"
    case reminderDueDateTime = "reminder_due_date_time"
    case reminderStartOnly = "reminder_start_only"
    case reminderStartAndDue = "reminder_start_and_due"
    case reminderDateUpdate = "reminder_date_update"
    case reminderUpdate = "reminder_update"
    case reminderClear = "reminder_clear"
    case reminderCompletion = "reminder_completion"
    case reminderReopen = "reminder_reopen"
    case reminderRecurrence = "reminder_recurrence"
    case reminderRecurrenceComplete = "reminder_recurrence_complete"
    case reminderMove = "reminder_move"
    case reminderDelete = "reminder_delete"
    case reminderDeleteReadback = "reminder_delete_readback"
    case reminderCleanup = "reminder_cleanup"
    case readOnlyCalendar = "read_only_calendar"
    case cleanup
}

public enum LiveVerifierMismatchField: String, Equatable, Sendable {
    case occurrenceCount = "occurrence_count"
    case allDay = "all_day"
    case start, end
    case recurrenceRuleCount = "recurrence_rule_count"
    case title, notes, location, url
    case alarmCount = "alarm_count"
    case collectionNativeLocator = "collection_native_locator"
    case completed, priority, due
    case workerCode = "worker_code"
    case timeZone = "time_zone"
}

public struct LiveVerifierMismatch: Equatable, Sendable {
    public let field: LiveVerifierMismatchField
    public let expected: String
    public let actual: String

    public init(field: LiveVerifierMismatchField, expected: String, actual: String) {
        self.field = field; self.expected = expected; self.actual = actual
    }
}

public struct LiveVerifierFailure: Error, Equatable, Sendable {
    public let stage: LiveVerifierStage
    public let error: LiveVerifierError
    public let mismatch: LiveVerifierMismatch?

    public init(stage: LiveVerifierStage, error: LiveVerifierError, mismatch: LiveVerifierMismatch? = nil) {
        self.stage = stage; self.error = error; self.mismatch = mismatch
    }

    public var stableCode: String { error.stableCode }
}

public struct LiveVerifierConfiguration: Equatable {
    public static let confirmation = "VERIFY_EVENTKIT_DISPOSABLE_CALENDAR_ON_THIS_MAC"
    public static let authorizationUnavailableConfirmation =
        "VERIFY_EVENTKIT_AUTHORIZATION_UNAVAILABLE_ON_THIS_MAC"
    public static let readOnlyConfirmation = "VERIFY_EVENTKIT_READ_ONLY_CALENDAR_ON_THIS_MAC"

    public let workerPath: String
    public let mode: LiveVerifierMode

    public var successSuite: String {
        switch mode {
        case .disposable: "eventkit-disposable-calendar-and-reminder"
        case let .authorizationUnavailable(entity): "eventkit-authorization-unavailable-\(entity.rawValue)"
        case .readOnlyCalendar: "eventkit-read-only-calendar"
        }
    }

    public static func parse(arguments: [String], environment: [String: String]) throws -> Self {
        guard environment["SHERPA_EVENTKIT_LIVE"] == "1" else { throw LiveVerifierError.liveGate }
        guard arguments.count >= 2, arguments[0] == "--worker", !arguments[1].isEmpty else {
            throw LiveVerifierError.usage
        }
        let mode: LiveVerifierMode
        let expectedConfirmation: String
        let trailing = Array(arguments.dropFirst(2))
        if trailing.isEmpty {
            mode = .disposable; expectedConfirmation = confirmation
        } else if trailing.count == 2, trailing[0] == "--expect-authorization-unavailable",
                  let entity = LiveVerifierEntity(rawValue: trailing[1]) {
            mode = .authorizationUnavailable(entity); expectedConfirmation = authorizationUnavailableConfirmation
        } else if trailing == ["--verify-read-only-calendar"],
                  let reference = boundedReference(environment["SHERPA_EVENTKIT_READ_ONLY_CALENDAR_REFERENCE"]) {
            mode = .readOnlyCalendar(calendarReference: reference); expectedConfirmation = readOnlyConfirmation
        } else {
            throw LiveVerifierError.usage
        }
        guard environment["SHERPA_EVENTKIT_LIVE_CONFIRM"] == expectedConfirmation else {
            throw LiveVerifierError.liveGate
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: arguments[1], isDirectory: &isDirectory),
              !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: arguments[1])
        else { throw LiveVerifierError.workerUnavailable }
        return Self(workerPath: arguments[1], mode: mode)
    }
}

public enum LiveVerifierEntity: String, Equatable, Sendable { case calendar, reminder }
public enum LiveVerifierMode: Equatable, Sendable {
    case disposable
    case authorizationUnavailable(LiveVerifierEntity)
    case readOnlyCalendar(calendarReference: String)
}

public struct EventKitLiveVerifier {
    private let client: WorkerClient
    private let mode: LiveVerifierMode

    public init(configuration: LiveVerifierConfiguration) {
        client = WorkerClient(workerPath: configuration.workerPath); mode = configuration.mode
    }

    public func run() throws {
        switch mode {
        case .disposable: try runDisposableSuite()
        case let .authorizationUnavailable(entity): try verifyAuthorizationUnavailable(entity)
        case let .readOnlyCalendar(reference): try verifyReadOnlyCalendar(reference)
        }
    }

    private func runDisposableSuite() throws {
        try at(.authorization) { try requireAuthorization(domain: "event") }
        try at(.calendarSources) {
            let result: EventSourceListResult = try client.call(
                capability: .eventSourceList,
                payload: EventSourceListRequest(schema: schema("event-source-list")),
                effect: .read
            )
            guard !result.schema.isEmpty else { throw LiveVerifierError.invalidResponse }
        }
        var eventCollections: [String] = []
        var primaryFailure: Error?
        do {
            let primary = try at(.calendarCreate) { try createEventCollection("primary") }
            eventCollections.append(primary)
            let destination = try at(.secondCalendarCreate) { try createEventCollection("destination") }
            eventCollections.append(destination)
            try verifyEventLifecycle(primary: primary, destination: destination)
        } catch { primaryFailure = error }
        let cleanupFailure = cleanupEventCollections(eventCollections)
        if cleanupFailure { throw LiveVerifierFailure(stage: .cleanup, error: .cleanupFailed) }
        if let primaryFailure { throw primaryFailure }
        try verifyReminderSuite()
    }

    private func verifyAuthorizationUnavailable(_ entity: LiveVerifierEntity) throws {
        let stage: LiveVerifierStage = entity == .calendar ? .authorization : .reminderAuthorization
        try at(stage) {
            let capability: PlannerCapability = entity == .calendar
                ? .eventAuthorizationStatus : .reminderAuthorizationStatus
            let domain = entity == .calendar ? "event" : "reminder"
            let result: AuthorizationResult = try client.call(
                capability: capability,
                payload: EmptyPlannerRequest(schema: schema("\(domain)-authorization-status")),
                effect: .read
            )
            guard ["denied", "restricted", "write_only"].contains(result.authorization) else {
                throw LiveVerifierError.authorizationRequired
            }
            if entity == .calendar {
                try expectFailure(
                    .eventSourceList,
                    EventSourceListRequest(schema: schema("event-source-list")),
                    effect: .read,
                    code: "eventkit.access_unavailable"
                )
            } else {
                try expectFailure(
                    .reminderSourceList,
                    EmptyPlannerRequest(schema: schema("reminder-source-list")),
                    effect: .read,
                    code: "eventkit.access_unavailable"
                )
            }
        }
    }

    private func verifyReadOnlyCalendar(_ reference: String) throws {
        try at(.authorization) { try requireAuthorization(domain: "event") }
        try at(.readOnlyCalendar) {
            let sources: EventSourceListResult = try client.call(
                capability: .eventSourceList,
                payload: EventSourceListRequest(schema: schema("event-source-list")),
                effect: .read
            )
            let matches = sources.sources.flatMap(\.eventCollections).filter { $0.nativeLocator == reference }
            guard matches.count == 1, matches[0].allowsContentModifications == false else {
                throw mismatch(.collectionNativeLocator, "one_read_only_destination", "mismatch")
            }
            try expectFailure(
                .eventCreate,
                EventCreateRequest(
                    schema: schema("event-create"), title: "Sherpa EventKit read-only rejection",
                    start: "2027-01-01T00:00:00Z", end: "2027-01-01T01:00:00Z",
                    collectionNativeLocator: reference
                ),
                effect: .mutation,
                code: "eventkit.destination_read_only"
            )
        }
    }

    private func createEventCollection(_ role: String) throws -> String {
        let result: EventCollectionCreateResult = try client.call(
            capability: .eventCollectionCreate,
            payload: EventCollectionCreateRequest(
                schema: schema("event-collection-create"),
                title: "Sherpa EventKit disposable \(role) \(UUID().uuidString)"
            ),
            effect: .mutation
        )
        return result.eventCollection.nativeLocator
    }

    private func verifyEventLifecycle(primary: String, destination: String) throws {
        let calendar = seoulCalendar()
        let start = try clockDate(hour: 10, on: date(Date(), adding: 14, calendar: calendar), calendar: calendar)
        let end = try require(calendar.date(byAdding: .hour, value: 1, to: start))
        let title = "Sherpa EventKit synthetic \(UUID().uuidString)"
        let rule = EventRecurrenceRule(
            frequency: "weekly", interval: 1,
            daysOfWeek: [EventRecurrenceDay(dayOfWeek: 2, weekNumber: 0)],
            end: EventRecurrenceEnd(kind: "count", count: 3)
        )
        let created: EventItemResult = try at(.recurringCreate) {
            try client.call(
                capability: .eventCreate,
                payload: EventCreateRequest(
                    schema: schema("event-create"), title: title,
                    start: wireDate(start), end: wireDate(end), allDay: false,
                    collectionNativeLocator: primary, notes: "synthetic", location: "Sherpa Lab",
                    url: "https://example.invalid/sherpa-live", timeZone: "Asia/Seoul",
                    alarms: [.relative(offsetSeconds: -900)], recurrenceRules: [rule]
                ),
                effect: .mutation
            )
        }
        let nativeLocator = created.event.nativeLocator
        try at(.recurringReadback) {
            let snapshot = try event(nativeLocator)
            try expect(snapshot.title == title, .title, title, snapshot.title)
            try expect(snapshot.eventCollection.nativeLocator == primary, .collectionNativeLocator,
                       primary, snapshot.eventCollection.nativeLocator)
            try expect(snapshot.alarms.value?.count == 1, .alarmCount, "1", String(snapshot.alarms.value?.count ?? -1))
            try expect(snapshot.recurrenceRules.value?.count == 1, .recurrenceRuleCount,
                       "1", String(snapshot.recurrenceRules.value?.count ?? -1))
        }
        let updated: EventItemResult = try at(.timedUpdate) {
            try client.call(
                capability: .eventUpdate,
                payload: EventUpdateRequest(
                    schema: schema("event-update"), nativeLocator: nativeLocator, span: "future",
                    changes: EventPatch(
                        title: .set("\(title) updated"), collectionNativeLocator: .set(destination),
                        notes: .clear, location: .clear, url: .clear,
                        alarms: .clear, recurrenceRules: .clear
                    )
                ),
                effect: .mutation
            )
        }
        try at(.timedUpdateReadback) {
            try expect(updated.event.eventCollection.nativeLocator == destination, .collectionNativeLocator,
                       destination, updated.event.eventCollection.nativeLocator)
            try expect(updated.event.alarms.value?.isEmpty == true, .alarmCount, "0",
                       String(updated.event.alarms.value?.count ?? -1))
            try expect(updated.event.recurrenceRules.value?.isEmpty == true, .recurrenceRuleCount,
                       "0", String(updated.event.recurrenceRules.value?.count ?? -1))
        }
        try at(.calendarReads) {
            let listed: EventListResult = try client.call(
                capability: .eventList,
                payload: EventListRequest(
                    schema: schema("event-list"), from: wireDate(date(start, adding: -1, calendar: calendar)),
                    to: wireDate(date(end, adding: 4, calendar: calendar)), limit: 100,
                    collectionNativeLocator: destination
                ),
                effect: .read
            )
            guard listed.events.contains(where: { $0.nativeLocator == nativeLocator }) else {
                throw mismatch(.occurrenceCount, "at_least_one", "0")
            }
        }
        try at(.timedDelete) {
            let result: EventDeleteResult = try client.call(
                capability: .eventDelete,
                payload: EventDeleteRequest(schema: schema("event-delete"), nativeLocator: nativeLocator, span: "future"),
                effect: .mutation
            )
            guard result.deleted else { throw LiveVerifierError.cleanupFailed }
        }
    }

    private func event(_ nativeLocator: String) throws -> EventSnapshot {
        let result: EventItemResult = try client.call(
            capability: .eventGet,
            payload: EventGetRequest(schema: schema("event-get"), nativeLocator: nativeLocator),
            effect: .read
        )
        return result.event
    }

    private func cleanupEventCollections(_ references: [String]) -> Bool {
        var failed = false
        for reference in references.reversed() {
            do {
                let result: EventCollectionDeleteResult = try client.call(
                    capability: .eventCollectionDelete,
                    payload: EventCollectionDeleteRequest(
                        schema: schema("event-collection-delete"), collectionNativeLocator: reference
                    ),
                    effect: .mutation
                )
                guard result.deleted else { throw LiveVerifierError.cleanupFailed }
                let sources: EventSourceListResult = try client.call(
                    capability: .eventSourceList,
                    payload: EventSourceListRequest(schema: schema("event-source-list")), effect: .read
                )
                guard !sources.sources.flatMap(\.eventCollections).contains(where: { $0.nativeLocator == reference })
                else { throw LiveVerifierError.cleanupFailed }
            } catch { failed = true }
        }
        return failed
    }

    private func verifyReminderSuite() throws {
        try at(.reminderAuthorization) { try requireAuthorization(domain: "reminder") }
        try at(.reminderSources) {
            let result: ReminderSourceListResult = try client.call(
                capability: .reminderSourceList,
                payload: EmptyPlannerRequest(schema: schema("reminder-source-list")), effect: .read
            )
            guard !result.schema.isEmpty else { throw LiveVerifierError.invalidResponse }
        }
        var collections: [String] = []
        var primaryFailure: Error?
        do {
            let primary = try at(.reminderListCreate) { try createReminderCollection("primary") }
            collections.append(primary)
            let destination = try at(.reminderSecondListCreate) { try createReminderCollection("destination") }
            collections.append(destination)
            try verifyReminderLifecycle(primary: primary, destination: destination)
        } catch { primaryFailure = error }
        let cleanupFailure = cleanupReminderCollections(collections)
        if cleanupFailure { throw LiveVerifierFailure(stage: .reminderCleanup, error: .cleanupFailed) }
        if let primaryFailure { throw primaryFailure }
    }

    private func createReminderCollection(_ role: String) throws -> String {
        let result: ReminderCollectionResult = try client.call(
            capability: .reminderCollectionCreate,
            payload: ReminderCollectionCreateRequest(
                schema: schema("reminder-collection-create"),
                title: "Sherpa EventKit disposable Reminder \(role) \(UUID().uuidString)"
            ),
            effect: .mutation
        )
        return result.reminderCollection.nativeLocator
    }

    private func verifyReminderLifecycle(primary: String, destination: String) throws {
        let calendar = seoulCalendar()
        let day = try date(Date(), adding: 7, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let due = ReminderDate(
            year: try require(components.year), month: try require(components.month),
            day: try require(components.day), hour: 15, minute: 30, timeZone: "Asia/Seoul"
        )
        let rule = EventRecurrenceRule(frequency: "daily", interval: 1,
                                       end: EventRecurrenceEnd(kind: "count", count: 2))
        let title = "Sherpa Reminder synthetic \(UUID().uuidString)"
        let created: ReminderItemResult = try at(.reminderCreate) {
            try client.call(
                capability: .reminderCreate,
                payload: ReminderCreateRequest(
                    schema: schema("reminder-create"), title: title,
                    collectionNativeLocator: primary, notes: "synthetic",
                    url: "https://example.invalid/sherpa-reminder", priority: 5,
                    due: due, alarms: [.relative(offsetSeconds: -600)], recurrenceRules: [rule]
                ),
                effect: .mutation
            )
        }
        let reference = created.reminder.nativeLocator
        try at(.reminderReadback) {
            let snapshot = try reminder(reference)
            try expect(snapshot.title == title, .title, title, snapshot.title)
            try expect(snapshot.collection.nativeLocator == primary, .collectionNativeLocator,
                       primary, snapshot.collection.nativeLocator)
            try expect(snapshot.alarms.value?.count == 1, .alarmCount, "1", String(snapshot.alarms.value?.count ?? -1))
            try expect(snapshot.recurrenceRules.value?.count == 1, .recurrenceRuleCount,
                       "1", String(snapshot.recurrenceRules.value?.count ?? -1))
        }
        let completed: ReminderItemResult = try at(.reminderCompletion) {
            try client.call(
                capability: .reminderComplete,
                payload: ReminderGetRequest(schema: schema("reminder-complete"), nativeLocator: reference),
                effect: .mutation
            )
        }
        try expect(completed.reminder.completed, .completed, "true", "false")
        let reopened: ReminderItemResult = try at(.reminderReopen) {
            try client.call(
                capability: .reminderReopen,
                payload: ReminderGetRequest(schema: schema("reminder-reopen"), nativeLocator: reference),
                effect: .mutation
            )
        }
        try expect(!reopened.reminder.completed, .completed, "false", "true")
        let updated: ReminderItemResult = try at(.reminderMove) {
            try client.call(
                capability: .reminderUpdate,
                payload: ReminderUpdateRequest(
                    schema: schema("reminder-update"), nativeLocator: reference,
                    changes: ReminderPatch(
                        title: .set("\(title) updated"), collectionNativeLocator: .set(destination),
                        notes: .clear, url: .clear, due: .clear, alarms: .clear, recurrenceRules: .clear
                    )
                ),
                effect: .mutation
            )
        }
        try expect(updated.reminder.collection.nativeLocator == destination, .collectionNativeLocator,
                   destination, updated.reminder.collection.nativeLocator)
        try at(.reminderReadback) {
            let result: ReminderListResult = try client.call(
                capability: .reminderList,
                payload: ReminderListRequest(
                    schema: schema("reminder-list"), collectionNativeLocator: destination,
                    limit: 100, completed: false
                ),
                effect: .read
            )
            guard result.reminders.contains(where: { $0.nativeLocator == reference }) else {
                throw mismatch(.occurrenceCount, "1", "0")
            }
        }
        try at(.reminderDelete) {
            let result: ReminderDeleteResult = try client.call(
                capability: .reminderDelete,
                payload: ReminderGetRequest(schema: schema("reminder-delete"), nativeLocator: reference),
                effect: .mutation
            )
            guard result.deleted else { throw LiveVerifierError.cleanupFailed }
        }
    }

    private func reminder(_ reference: String) throws -> ReminderSnapshot {
        let result: ReminderItemResult = try client.call(
            capability: .reminderGet,
            payload: ReminderGetRequest(schema: schema("reminder-get"), nativeLocator: reference),
            effect: .read
        )
        return result.reminder
    }

    private func cleanupReminderCollections(_ references: [String]) -> Bool {
        var failed = false
        for reference in references.reversed() {
            do {
                let result: ReminderCollectionDeleteResult = try client.call(
                    capability: .reminderCollectionDelete,
                    payload: ReminderCollectionDeleteRequest(
                        schema: schema("reminder-collection-delete"), collectionNativeLocator: reference
                    ),
                    effect: .mutation
                )
                guard result.deleted else { throw LiveVerifierError.cleanupFailed }
                let sources: ReminderSourceListResult = try client.call(
                    capability: .reminderSourceList,
                    payload: EmptyPlannerRequest(schema: schema("reminder-source-list")), effect: .read
                )
                guard !sources.sources.flatMap(\.reminderCollections).contains(where: { $0.nativeLocator == reference })
                else { throw LiveVerifierError.cleanupFailed }
            } catch { failed = true }
        }
        return failed
    }

    private func requireAuthorization(domain: String) throws {
        let capability: PlannerCapability = domain == "event"
            ? .eventAuthorizationStatus : .reminderAuthorizationStatus
        let result: AuthorizationResult = try client.call(
            capability: capability,
            payload: EmptyPlannerRequest(schema: schema("\(domain)-authorization-status")), effect: .read
        )
        guard result.authorization == "full_access" else { throw LiveVerifierError.authorizationRequired }
    }

    private func at<T>(_ stage: LiveVerifierStage, operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch let failure as LiveVerifierFailure { throw failure }
        catch let check as LiveVerifierCheckFailure {
            throw LiveVerifierFailure(stage: stage, error: .verificationFailed, mismatch: check.mismatch)
        }
        catch let error as LiveVerifierError { throw LiveVerifierFailure(stage: stage, error: error) }
        catch { throw LiveVerifierFailure(stage: stage, error: .workerFailed) }
    }
}

private struct LiveVerifierCheckFailure: Error {
    let mismatch: LiveVerifierMismatch
}

private struct WorkerCallFailure: Error { let code: String }
private struct FailureResult: Decodable {}

private struct LivePolicy: Encodable {
    let effect: WorkerEffect
    let requiredEvidence: RequiredEvidence
    enum CodingKeys: String, CodingKey { case effect; case requiredEvidence = "required_evidence"; case artifactDirectory = "artifact_directory" }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(effect, forKey: .effect)
        try container.encode(requiredEvidence, forKey: .requiredEvidence)
        try container.encodeNil(forKey: .artifactDirectory)
    }
}

private struct LiveRequest<Payload: Encodable>: Encodable {
    let kind = "request"
    let protocolVersion = sherpaProtocolVersion
    let applicationContract = "sherpa.planner.v2"
    let requestID, operationID, capability: String
    let payload: Payload
    let deadlineMilliseconds = 30_000
    let idempotencyKey: String
    let policy: LivePolicy
    enum CodingKeys: String, CodingKey {
        case kind; case protocolVersion = "protocol_version"; case applicationContract = "application_contract"
        case requestID = "request_id"; case operationID = "operation_id"; case capability, payload
        case deadlineMilliseconds = "deadline_ms"; case idempotencyKey = "idempotency_key"; case policy
    }
}

private struct LiveResponse<Result: Decodable>: Decodable {
    let kind, protocolVersion, applicationContract, requestID, operationID, capability: String
    let status: WorkerStatus
    let result: Result?
    let effect: WorkerEffectOutcome
    let evidence: WorkerEvidence?
    let error: WorkerError?
    let warnings: [JSONValue]
    enum CodingKeys: String, CodingKey {
        case kind; case protocolVersion = "protocol_version"; case applicationContract = "application_contract"
        case requestID = "request_id"; case operationID = "operation_id"; case capability, status, result
        case effect, evidence, error, warnings
    }
}

private struct WorkerClient {
    let workerPath: String
    let processTimeZone: String?

    init(workerPath: String, processTimeZone: String? = nil) {
        self.workerPath = workerPath; self.processTimeZone = processTimeZone
    }

    func call<Payload: Encodable, Result: Decodable>(
        capability: PlannerCapability, payload: Payload, effect: WorkerEffect
    ) throws -> Result {
        let identifier = "live-\(UUID().uuidString.lowercased())"
        let evidence: RequiredEvidence = if effect == .read { .none }
            else if capability.rawValue.hasSuffix(".delete") { .nativeAbsenceReadback }
            else if effect == .authorizationPrompt { .authorizationReadback }
            else { .nativeReadback }
        let request = LiveRequest(
            requestID: identifier, operationID: identifier, capability: capability.rawValue,
            payload: payload, idempotencyKey: identifier,
            policy: LivePolicy(effect: effect, requiredEvidence: evidence)
        )
        let encoded: Data
        do { encoded = try JSONEncoder().encode(request) }
        catch { throw LiveVerifierError.invalidResponse }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: workerPath)
        if let processTimeZone { process.environment = ["TZ": processTimeZone] }
        let input = Pipe(); let output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = Pipe()
        do {
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: encoded)
            try input.fileHandleForWriting.close()
        } catch { throw LiveVerifierError.workerFailed }
        let responseData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, responseData.count <= 8 * 1024 * 1024 else {
            throw LiveVerifierError.workerFailed
        }
        let response: LiveResponse<Result>
        do { response = try JSONDecoder().decode(LiveResponse<Result>.self, from: responseData) }
        catch { throw LiveVerifierError.invalidResponse }
        guard response.kind == "response", response.protocolVersion == sherpaProtocolVersion,
              response.applicationContract == "sherpa.planner.v2",
              response.requestID == identifier, response.operationID == identifier,
              response.capability == capability.rawValue
        else { throw LiveVerifierError.invalidResponse }
        switch response.status {
        case .succeeded:
            guard response.error == nil, let result = response.result else { throw LiveVerifierError.invalidResponse }
            return result
        case .failed, .partial, .uncertain:
            guard let code = response.error?.code, safeCode(code) else { throw LiveVerifierError.workerFailed }
            throw WorkerCallFailure(code: code)
        }
    }
}

private extension EventKitLiveVerifier {
    func expectFailure<Payload: Encodable>(
        _ capability: PlannerCapability, _ payload: Payload, effect: WorkerEffect, code: String
    ) throws {
        do {
            let _: FailureResult = try client.call(capability: capability, payload: payload, effect: effect)
            throw mismatch(.workerCode, code, "succeeded")
        } catch let failure as WorkerCallFailure {
            guard failure.code == code else { throw mismatch(.workerCode, code, failure.code) }
        }
    }
}

private func schema(_ operation: String) -> String { "sherpa.planner.\(operation).request.v2" }

private func mismatch(_ field: LiveVerifierMismatchField, _ expected: String, _ actual: String) -> LiveVerifierCheckFailure {
    LiveVerifierCheckFailure(mismatch: LiveVerifierMismatch(field: field, expected: expected, actual: actual))
}

private func expect(_ condition: Bool, _ field: LiveVerifierMismatchField, _ expected: String, _ actual: String) throws {
    guard condition else { throw mismatch(field, expected, actual) }
}

private func boundedReference(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= 4_096, !value.contains("\0") else { return nil }
    return value
}

private func safeCode(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 128 && value.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-"
    }
}

private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw LiveVerifierError.verificationFailed }
    return value
}

private func seoulCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}

private func date(_ value: Date, adding days: Int, calendar: Calendar) throws -> Date {
    try require(calendar.date(byAdding: .day, value: days, to: value))
}

private func clockDate(hour: Int, on day: Date, calendar: Calendar) throws -> Date {
    try require(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day))
}

private func wireDate(_ value: Date) -> String {
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: value)
}

private func parsedDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

public func exactOccurrences(_ events: [EventSnapshot], on day: Date, calendar: Calendar) -> [EventSnapshot] {
    let matching = events.filter { event in
        guard let occurrence = parsedDate(event.occurrenceDate) else { return false }
        return calendar.isDate(occurrence, inSameDayAs: day)
    }
    let detached = matching.filter(\.detached)
    return detached.isEmpty ? matching : detached
}
