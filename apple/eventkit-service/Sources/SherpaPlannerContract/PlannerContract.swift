import SherpaWorkerProtocol

/// Provider-neutral identity shared by Planner application commands.
public struct NativeLocator: Codable, Sendable, Equatable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// Canonical Planner capability names. Public presentation may project Apple
/// terms such as Calendar and Reminder List, but worker dispatch uses these.
public enum PlannerCapability: String, Codable, Sendable, CaseIterable {
    case eventAuthorizationStatus = "event.authorization.status"
    case eventAuthorizationRequest = "event.authorization.request"
    case eventSourceList = "event.source.list"
    case eventCollectionCreate = "event.collection.create"
    case eventCollectionDelete = "event.collection.delete"
    case eventCommandValidate = "event.command.validate"
    case eventList = "event.list"
    case eventGet = "event.get"
    case eventCreate = "event.create"
    case eventUpdate = "event.update"
    case eventDelete = "event.delete"
    case reminderAuthorizationStatus = "reminder.authorization.status"
    case reminderAuthorizationRequest = "reminder.authorization.request"
    case reminderSourceList = "reminder.source.list"
    case reminderCollectionCreate = "reminder.collection.create"
    case reminderCollectionDelete = "reminder.collection.delete"
    case reminderCommandValidate = "reminder.command.validate"
    case reminderList = "reminder.list"
    case reminderGet = "reminder.get"
    case reminderCreate = "reminder.create"
    case reminderUpdate = "reminder.update"
    case reminderDelete = "reminder.delete"
    case reminderComplete = "reminder.complete"
    case reminderReopen = "reminder.reopen"
}

public struct EventSourceListRequest: Codable, Sendable, Equatable {
    public let schema: String
    public init(schema: String) { self.schema = schema }
}

public struct EventCollectionDescriptor: Codable, Sendable, Equatable {
    public let nativeLocator: String
    public let title: String
    public let type: String
    public let allowsContentModifications: Bool
    enum CodingKeys: String, CodingKey {
        case nativeLocator = "native_locator", title, type
        case allowsContentModifications = "allows_content_modifications"
    }
    public init(nativeLocator: String, title: String, type: String, allowsContentModifications: Bool) {
        self.nativeLocator = nativeLocator; self.title = title; self.type = type
        self.allowsContentModifications = allowsContentModifications
    }
}

public struct EventSourceDescriptor: Codable, Sendable, Equatable {
    public let nativeLocator: String
    public let title: String
    public let type: String
    public let eventCollections: [EventCollectionDescriptor]
    enum CodingKeys: String, CodingKey {
        case nativeLocator = "native_locator", title, type
        case eventCollections = "event_collections"
    }
    public init(nativeLocator: String, title: String, type: String, eventCollections: [EventCollectionDescriptor]) {
        self.nativeLocator = nativeLocator; self.title = title; self.type = type
        self.eventCollections = eventCollections
    }
}

public struct EventSourceListResult: Codable, Sendable, Equatable {
    public let schema: String
    public let sources: [EventSourceDescriptor]
    public init(sources: [EventSourceDescriptor]) {
        schema = "sherpa.planner.event-source-list.success.v2"
        self.sources = sources
    }
}

public struct EventCollectionCreateRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let title: String
    public let sourceNativeLocator: String?
    enum CodingKeys: String, CodingKey { case schema, title; case sourceNativeLocator = "source_native_locator" }
    public init(schema: String, title: String, sourceNativeLocator: String? = nil) {
        self.schema = schema; self.title = title; self.sourceNativeLocator = sourceNativeLocator
    }
}

public struct EventCollectionDeleteRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let collectionNativeLocator: String
    enum CodingKeys: String, CodingKey { case schema; case collectionNativeLocator = "collection_native_locator" }
    public init(schema: String, collectionNativeLocator: String) {
        self.schema = schema; self.collectionNativeLocator = collectionNativeLocator
    }
}

public struct EventCollectionCreateResult: Codable, Sendable, Equatable {
    public let schema: String
    public let eventCollection: EventCollectionDescriptor
    enum CodingKeys: String, CodingKey { case schema; case eventCollection = "event_collection" }
    public init(eventCollection: EventCollectionDescriptor) {
        schema = "sherpa.planner.event-collection-create.success.v2"
        self.eventCollection = eventCollection
    }
}

public struct EventCollectionDeleteResult: Codable, Sendable, Equatable {
    public let schema: String
    public let deleted: Bool
    public init() { schema = "sherpa.planner.event-collection-delete.success.v2"; deleted = true }
}

public struct EmptyPlannerRequest: Codable, Sendable, Equatable {
    public let schema: String
    public init(schema: String) { self.schema = schema }
}

public struct AuthorizationResult: Codable, Sendable, Equatable {
    public let schema: String
    public let authorization: String
    public init(domain: String, authorization: String) {
        schema = "sherpa.planner.\(domain)-authorization.success.v2"
        self.authorization = authorization
    }
}

public struct ReminderCollectionDescriptor: Codable, Sendable, Equatable {
    public let nativeLocator, title, type: String
    public let allowsContentModifications: Bool
    enum CodingKeys: String, CodingKey { case nativeLocator = "native_locator", title, type; case allowsContentModifications = "allows_content_modifications" }
    public init(nativeLocator: String, title: String, type: String, allowsContentModifications: Bool) { self.nativeLocator = nativeLocator; self.title = title; self.type = type; self.allowsContentModifications = allowsContentModifications }
}
public struct ReminderSourceDescriptor: Codable, Sendable, Equatable {
    public let nativeLocator, title, type: String
    public let reminderCollections: [ReminderCollectionDescriptor]
    enum CodingKeys: String, CodingKey { case nativeLocator = "native_locator", title, type; case reminderCollections = "reminder_collections" }
    public init(nativeLocator: String, title: String, type: String, reminderCollections: [ReminderCollectionDescriptor]) { self.nativeLocator = nativeLocator; self.title = title; self.type = type; self.reminderCollections = reminderCollections }
}
public struct ReminderSourceListResult: Codable, Sendable, Equatable {
    public let schema: String
    public let sources: [ReminderSourceDescriptor]
    public init(sources: [ReminderSourceDescriptor]) { schema = "sherpa.planner.reminder-source-list.success.v2"; self.sources = sources }
}

// MARK: - Event item commands

public struct EventListRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let from: String
    public let to: String
    public let limit: Int?
    public let collectionNativeLocator: String?
    enum CodingKeys: String, CodingKey {
        case schema, from, to, limit
        case collectionNativeLocator = "collection_native_locator"
    }
    public init(schema: String, from: String, to: String, limit: Int? = nil, collectionNativeLocator: String? = nil) {
        self.schema = schema; self.from = from; self.to = to; self.limit = limit
        self.collectionNativeLocator = collectionNativeLocator
    }
}

public struct EventGetRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let nativeLocator: String
    enum CodingKeys: String, CodingKey { case schema; case nativeLocator = "native_locator" }
    public init(schema: String, nativeLocator: String) { self.schema = schema; self.nativeLocator = nativeLocator }
}

public enum EventAlarm: Codable, Sendable, Equatable {
    case absolute(date: String)
    case relative(offsetSeconds: Int64)

    enum CodingKeys: String, CodingKey { case kind, date; case offsetSeconds = "offset_seconds" }
    enum Kind: String, Codable { case absolute, relative }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .absolute:
            guard !values.contains(.offsetSeconds) else { throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "unexpected alarm field") }
            self = .absolute(date: try values.decode(String.self, forKey: .date))
        case .relative:
            guard !values.contains(.date) else { throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "unexpected alarm field") }
            self = .relative(offsetSeconds: try values.decode(Int64.self, forKey: .offsetSeconds))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .absolute(date): try values.encode(Kind.absolute, forKey: .kind); try values.encode(date, forKey: .date)
        case let .relative(offset): try values.encode(Kind.relative, forKey: .kind); try values.encode(offset, forKey: .offsetSeconds)
        }
    }
}

public struct EventRecurrenceDay: Codable, Sendable, Equatable {
    public let dayOfWeek: Int
    public let weekNumber: Int
    enum CodingKeys: String, CodingKey { case dayOfWeek = "day_of_week"; case weekNumber = "week_number" }
    public init(dayOfWeek: Int, weekNumber: Int) { self.dayOfWeek = dayOfWeek; self.weekNumber = weekNumber }
}

public struct EventRecurrenceEnd: Codable, Sendable, Equatable {
    public let kind: String
    public let date: String?
    public let count: Int?
    public init(kind: String, date: String? = nil, count: Int? = nil) {
        self.kind = kind; self.date = date; self.count = count
    }
}

public struct EventRecurrenceRule: Codable, Sendable, Equatable {
    public let frequency: String
    public let interval: Int
    public let daysOfWeek: [EventRecurrenceDay]?
    public let daysOfMonth: [Int]?
    public let monthsOfYear: [Int]?
    public let weeksOfYear: [Int]?
    public let daysOfYear: [Int]?
    public let setPositions: [Int]?
    public let end: EventRecurrenceEnd?
    enum CodingKeys: String, CodingKey {
        case frequency, interval, end
        case daysOfWeek = "days_of_week", daysOfMonth = "days_of_month"
        case monthsOfYear = "months_of_year", weeksOfYear = "weeks_of_year"
        case daysOfYear = "days_of_year", setPositions = "set_positions"
    }
    public init(frequency: String, interval: Int, daysOfWeek: [EventRecurrenceDay]? = nil,
                daysOfMonth: [Int]? = nil, monthsOfYear: [Int]? = nil,
                weeksOfYear: [Int]? = nil, daysOfYear: [Int]? = nil,
                setPositions: [Int]? = nil, end: EventRecurrenceEnd? = nil) {
        self.frequency = frequency; self.interval = interval; self.daysOfWeek = daysOfWeek
        self.daysOfMonth = daysOfMonth; self.monthsOfYear = monthsOfYear
        self.weeksOfYear = weeksOfYear; self.daysOfYear = daysOfYear
        self.setPositions = setPositions; self.end = end
    }
}

public struct EventCreateRequest: Codable, Sendable, Equatable {
    public let schema, title, start, end: String
    public let allDay: Bool?
    public let collectionNativeLocator, notes, location, url, timeZone: String?
    public let alarms: [EventAlarm]?
    public let recurrenceRules: [EventRecurrenceRule]?
    enum CodingKeys: String, CodingKey {
        case schema, title, start, end, notes, location, url, alarms
        case allDay = "all_day", collectionNativeLocator = "collection_native_locator"
        case timeZone = "time_zone", recurrenceRules = "recurrence_rules"
    }
    public init(schema: String, title: String, start: String, end: String, allDay: Bool? = nil,
                collectionNativeLocator: String? = nil, notes: String? = nil,
                location: String? = nil, url: String? = nil, timeZone: String? = nil,
                alarms: [EventAlarm]? = nil, recurrenceRules: [EventRecurrenceRule]? = nil) {
        self.schema = schema; self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.collectionNativeLocator = collectionNativeLocator; self.notes = notes; self.location = location
        self.url = url; self.timeZone = timeZone; self.alarms = alarms; self.recurrenceRules = recurrenceRules
    }
}

/// An update patch retains presence separately from a nullable value, so an
/// omitted property and an explicit JSON null can never be confused.
public enum EventChange<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    case set(Value)
    case clear
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        self = value.decodeNil() ? .clear : .set(try value.decode(Value.self))
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self { case let .set(item): try value.encode(item); case .clear: try value.encodeNil() }
    }
}

public struct EventPatch: Codable, Sendable, Equatable {
    public let title, start, end: EventChange<String>?
    public let allDay: EventChange<Bool>?
    public let collectionNativeLocator, notes, location, url, timeZone: EventChange<String>?
    public let alarms: EventChange<[EventAlarm]>?
    public let recurrenceRules: EventChange<[EventRecurrenceRule]>?
    enum CodingKeys: String, CodingKey {
        case title, start, end, notes, location, url, alarms
        case allDay = "all_day", collectionNativeLocator = "collection_native_locator"
        case timeZone = "time_zone", recurrenceRules = "recurrence_rules"
    }
    public init(title: EventChange<String>? = nil, start: EventChange<String>? = nil,
                end: EventChange<String>? = nil, allDay: EventChange<Bool>? = nil,
                collectionNativeLocator: EventChange<String>? = nil,
                notes: EventChange<String>? = nil, location: EventChange<String>? = nil,
                url: EventChange<String>? = nil, timeZone: EventChange<String>? = nil,
                alarms: EventChange<[EventAlarm]>? = nil,
                recurrenceRules: EventChange<[EventRecurrenceRule]>? = nil) {
        self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.collectionNativeLocator = collectionNativeLocator; self.notes = notes; self.location = location
        self.url = url; self.timeZone = timeZone; self.alarms = alarms; self.recurrenceRules = recurrenceRules
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func change<T: Codable & Sendable & Equatable>(_ key: CodingKeys, _: T.Type) throws -> EventChange<T>? {
            guard values.contains(key) else { return nil }
            if try values.decodeNil(forKey: key) { return .clear }
            return .set(try values.decode(T.self, forKey: key))
        }
        title = try change(.title, String.self); start = try change(.start, String.self)
        end = try change(.end, String.self); allDay = try change(.allDay, Bool.self)
        collectionNativeLocator = try change(.collectionNativeLocator, String.self)
        notes = try change(.notes, String.self); location = try change(.location, String.self)
        url = try change(.url, String.self); timeZone = try change(.timeZone, String.self)
        alarms = try change(.alarms, [EventAlarm].self)
        recurrenceRules = try change(.recurrenceRules, [EventRecurrenceRule].self)
    }
    public var isEmpty: Bool {
        title == nil && start == nil && end == nil && allDay == nil && collectionNativeLocator == nil
            && notes == nil && location == nil && url == nil && timeZone == nil
            && alarms == nil && recurrenceRules == nil
    }
}

public struct EventUpdateRequest: Codable, Sendable, Equatable {
    public let schema, nativeLocator, span: String
    public let changes: EventPatch
    enum CodingKeys: String, CodingKey { case schema, span, changes; case nativeLocator = "native_locator" }
    public init(schema: String, nativeLocator: String, span: String, changes: EventPatch) {
        self.schema = schema; self.nativeLocator = nativeLocator; self.span = span; self.changes = changes
    }
}

public struct EventDeleteRequest: Codable, Sendable, Equatable {
    public let schema, nativeLocator, span: String
    enum CodingKeys: String, CodingKey { case schema, span; case nativeLocator = "native_locator" }
    public init(schema: String, nativeLocator: String, span: String) {
        self.schema = schema; self.nativeLocator = nativeLocator; self.span = span
    }
}

public enum EventValidatedCommand: Codable, Sendable, Equatable {
    case create(EventCreateRequest)
    case update(EventUpdateRequest)
    case delete(EventDeleteRequest)
    enum CodingKeys: String, CodingKey { case capability, payload }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .capability) {
        case PlannerCapability.eventCreate.rawValue: self = .create(try values.decode(EventCreateRequest.self, forKey: .payload))
        case PlannerCapability.eventUpdate.rawValue: self = .update(try values.decode(EventUpdateRequest.self, forKey: .payload))
        case PlannerCapability.eventDelete.rawValue: self = .delete(try values.decode(EventDeleteRequest.self, forKey: .payload))
        default: throw DecodingError.dataCorruptedError(forKey: .capability, in: values, debugDescription: "unsupported event command")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .create(command): try values.encode(PlannerCapability.eventCreate.rawValue, forKey: .capability); try values.encode(command, forKey: .payload)
        case let .update(command): try values.encode(PlannerCapability.eventUpdate.rawValue, forKey: .capability); try values.encode(command, forKey: .payload)
        case let .delete(command): try values.encode(PlannerCapability.eventDelete.rawValue, forKey: .capability); try values.encode(command, forKey: .payload)
        }
    }
}

public struct EventCommandValidateRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let commands: [EventValidatedCommand]
}

public struct EventCommandValidateResult: Codable, Sendable, Equatable {
    public let schema: String
    public let valid: Bool
    public let commandCount: Int
    enum CodingKeys: String, CodingKey { case schema, valid; case commandCount = "command_count" }
    public init(commandCount: Int) {
        schema = "sherpa.planner.event-command-validate.success.v2"
        valid = true
        self.commandCount = commandCount
    }
}

public struct SnapshotField<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let state: String
    public let value: Value?
    public init(_ value: Value?) { state = value == nil ? "absent" : "value"; self.value = value }
    public static var unsupported: Self { .init(state: "unsupported", value: nil) }
    public init(state: String, value: Value?) { self.state = state; self.value = value }
}

public struct EventCollectionSnapshot: Codable, Sendable, Equatable {
    public let nativeLocator, title, type: String
    public let allowsContentModifications: Bool
    public init(nativeLocator: String, title: String, type: String, allowsContentModifications: Bool) {
        self.nativeLocator = nativeLocator; self.title = title; self.type = type
        self.allowsContentModifications = allowsContentModifications
    }
    enum CodingKeys: String, CodingKey { case nativeLocator = "native_locator", title, type; case allowsContentModifications = "allows_content_modifications" }
}

public struct AlarmSnapshot: Codable, Sendable, Equatable {
    public let absoluteDate: String?
    public let relativeOffsetSeconds: Double
    public let proximity: String
    public let structuredLocation: String?
    public init(absoluteDate: String?, relativeOffsetSeconds: Double, proximity: String, structuredLocation: String?) {
        self.absoluteDate = absoluteDate; self.relativeOffsetSeconds = relativeOffsetSeconds
        self.proximity = proximity; self.structuredLocation = structuredLocation
    }
    enum CodingKeys: String, CodingKey { case absoluteDate = "absolute_date", relativeOffsetSeconds = "relative_offset_seconds", proximity; case structuredLocation = "structured_location" }
}

public struct RecurrenceSnapshot: Codable, Sendable, Equatable {
    public let frequency: String
    public let interval, firstDayOfWeek, occurrenceCount: Int
    public let endDate: String?
    public let daysOfWeek: [EventRecurrenceDay]
    public let daysOfMonth, monthsOfYear, weeksOfYear, daysOfYear, setPositions: [Int]
    public init(frequency: String, interval: Int, firstDayOfWeek: Int, occurrenceCount: Int, endDate: String?, daysOfWeek: [EventRecurrenceDay], daysOfMonth: [Int], monthsOfYear: [Int], weeksOfYear: [Int], daysOfYear: [Int], setPositions: [Int]) {
        self.frequency = frequency; self.interval = interval; self.firstDayOfWeek = firstDayOfWeek
        self.occurrenceCount = occurrenceCount; self.endDate = endDate; self.daysOfWeek = daysOfWeek
        self.daysOfMonth = daysOfMonth; self.monthsOfYear = monthsOfYear; self.weeksOfYear = weeksOfYear
        self.daysOfYear = daysOfYear; self.setPositions = setPositions
    }
    enum CodingKeys: String, CodingKey { case frequency, interval; case firstDayOfWeek = "first_day_of_week"; case occurrenceCount = "occurrence_count"; case endDate = "end_date"; case daysOfWeek = "days_of_week"; case daysOfMonth = "days_of_month"; case monthsOfYear = "months_of_year"; case weeksOfYear = "weeks_of_year"; case daysOfYear = "days_of_year"; case setPositions = "set_positions" }
}

public struct EventSnapshot: Codable, Sendable, Equatable {
    public let nativeLocator: String
    public let eventCollection: EventCollectionSnapshot
    public let title, start, end: String
    public let allDay: Bool
    public let timeZone: String?
    public let notes, location, url: SnapshotField<String>
    public let occurrenceDate: String?
    public let detached: Bool
    public let status, availability: String
    public let alarms: SnapshotField<[AlarmSnapshot]>
    public let recurrenceRules: SnapshotField<[RecurrenceSnapshot]>
    public init(nativeLocator: String, eventCollection: EventCollectionSnapshot, title: String, start: String, end: String, allDay: Bool, timeZone: String?, notes: SnapshotField<String>, location: SnapshotField<String>, url: SnapshotField<String>, occurrenceDate: String?, detached: Bool, status: String, availability: String, alarms: SnapshotField<[AlarmSnapshot]>, recurrenceRules: SnapshotField<[RecurrenceSnapshot]>) {
        self.nativeLocator = nativeLocator; self.eventCollection = eventCollection; self.title = title
        self.start = start; self.end = end; self.allDay = allDay; self.timeZone = timeZone
        self.notes = notes; self.location = location; self.url = url; self.occurrenceDate = occurrenceDate
        self.detached = detached; self.status = status; self.availability = availability
        self.alarms = alarms; self.recurrenceRules = recurrenceRules
    }
    enum CodingKeys: String, CodingKey { case nativeLocator = "native_locator"; case eventCollection = "event_collection"; case title, start, end; case allDay = "all_day"; case timeZone = "time_zone"; case notes, location, url; case occurrenceDate = "occurrence_date"; case detached, status, availability, alarms; case recurrenceRules = "recurrence_rules" }
}

public struct EventItemResult: Codable, Sendable, Equatable {
    public let schema: String; public let event: EventSnapshot
    public init(operation: String, event: EventSnapshot) { schema = "sherpa.planner.event-\(operation).success.v2"; self.event = event }
}
public struct EventListResult: Codable, Sendable, Equatable {
    public let schema: String; public let events: [EventSnapshot]; public let from, to: String; public let toExclusive: Bool
    public init(events: [EventSnapshot], from: String, to: String) { schema = "sherpa.planner.event-list.success.v2"; self.events = events; self.from = from; self.to = to; toExclusive = true }
    enum CodingKeys: String, CodingKey { case schema, events, from, to; case toExclusive = "to_exclusive" }
}
public struct EventDeleteResult: Codable, Sendable, Equatable { public let schema: String; public let deleted: Bool; public init() { schema = "sherpa.planner.event-delete.success.v2"; deleted = true } }
