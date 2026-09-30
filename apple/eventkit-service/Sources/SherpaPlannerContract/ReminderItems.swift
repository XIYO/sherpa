public struct ReminderCollectionCreateRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let title: String
    public let sourceNativeLocator: String?
    enum CodingKeys: String, CodingKey { case schema, title; case sourceNativeLocator = "source_native_locator" }
    public init(schema: String, title: String, sourceNativeLocator: String? = nil) {
        self.schema = schema; self.title = title; self.sourceNativeLocator = sourceNativeLocator
    }
}

public struct ReminderCollectionDeleteRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let collectionNativeLocator: String
    enum CodingKeys: String, CodingKey { case schema; case collectionNativeLocator = "collection_native_locator" }
    public init(schema: String, collectionNativeLocator: String) {
        self.schema = schema; self.collectionNativeLocator = collectionNativeLocator
    }
}

public struct ReminderListRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let collectionNativeLocator: String?
    public let limit: Int?
    public let completed: Bool?
    enum CodingKeys: String, CodingKey { case schema, limit, completed; case collectionNativeLocator = "collection_native_locator" }
    public init(schema: String, collectionNativeLocator: String? = nil, limit: Int? = nil, completed: Bool? = nil) {
        self.schema = schema; self.collectionNativeLocator = collectionNativeLocator
        self.limit = limit; self.completed = completed
    }
}

public struct ReminderGetRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let nativeLocator: String
    enum CodingKeys: String, CodingKey { case schema; case nativeLocator = "native_locator" }
    public init(schema: String, nativeLocator: String) { self.schema = schema; self.nativeLocator = nativeLocator }
}

public struct ReminderDate: Codable, Sendable, Equatable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?
    public let second: Int?
    public let timeZone: String?
    enum CodingKeys: String, CodingKey { case year, month, day, hour, minute, second; case timeZone = "time_zone" }
    public init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil,
                second: Int? = nil, timeZone: String? = nil) {
        self.year = year; self.month = month; self.day = day; self.hour = hour
        self.minute = minute; self.second = second; self.timeZone = timeZone
    }
}

public struct ReminderCreateRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let title: String
    public let collectionNativeLocator: String?
    public let notes: String?
    public let url: String?
    public let priority: Int?
    public let due: ReminderDate?
    public let start: ReminderDate?
    public let alarms: [EventAlarm]?
    public let recurrenceRules: [EventRecurrenceRule]?
    enum CodingKeys: String, CodingKey {
        case schema, title, notes, url, priority, due, start, alarms
        case collectionNativeLocator = "collection_native_locator"
        case recurrenceRules = "recurrence_rules"
    }
    public init(schema: String, title: String, collectionNativeLocator: String? = nil,
                notes: String? = nil, url: String? = nil, priority: Int? = nil,
                due: ReminderDate? = nil, start: ReminderDate? = nil,
                alarms: [EventAlarm]? = nil, recurrenceRules: [EventRecurrenceRule]? = nil) {
        self.schema = schema; self.title = title; self.collectionNativeLocator = collectionNativeLocator
        self.notes = notes; self.url = url; self.priority = priority; self.due = due; self.start = start
        self.alarms = alarms; self.recurrenceRules = recurrenceRules
    }
}

public typealias ReminderChange<Value: Codable & Sendable & Equatable> = EventChange<Value>

public struct ReminderPatch: Codable, Sendable, Equatable {
    public let title: ReminderChange<String>?
    public let collectionNativeLocator: ReminderChange<String>?
    public let notes: ReminderChange<String>?
    public let url: ReminderChange<String>?
    public let priority: ReminderChange<Int>?
    public let due: ReminderChange<ReminderDate>?
    public let start: ReminderChange<ReminderDate>?
    public let alarms: ReminderChange<[EventAlarm]>?
    public let recurrenceRules: ReminderChange<[EventRecurrenceRule]>?
    enum CodingKeys: String, CodingKey {
        case title, notes, url, priority, due, start, alarms
        case collectionNativeLocator = "collection_native_locator"
        case recurrenceRules = "recurrence_rules"
    }
    public init(title: ReminderChange<String>? = nil,
                collectionNativeLocator: ReminderChange<String>? = nil,
                notes: ReminderChange<String>? = nil, url: ReminderChange<String>? = nil,
                priority: ReminderChange<Int>? = nil, due: ReminderChange<ReminderDate>? = nil,
                start: ReminderChange<ReminderDate>? = nil,
                alarms: ReminderChange<[EventAlarm]>? = nil,
                recurrenceRules: ReminderChange<[EventRecurrenceRule]>? = nil) {
        self.title = title; self.collectionNativeLocator = collectionNativeLocator; self.notes = notes
        self.url = url; self.priority = priority; self.due = due; self.start = start
        self.alarms = alarms; self.recurrenceRules = recurrenceRules
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func change<T: Codable & Sendable & Equatable>(_ key: CodingKeys, _: T.Type) throws -> ReminderChange<T>? {
            guard values.contains(key) else { return nil }
            if try values.decodeNil(forKey: key) { return .clear }
            return .set(try values.decode(T.self, forKey: key))
        }
        title = try change(.title, String.self)
        collectionNativeLocator = try change(.collectionNativeLocator, String.self)
        notes = try change(.notes, String.self); url = try change(.url, String.self)
        priority = try change(.priority, Int.self); due = try change(.due, ReminderDate.self)
        start = try change(.start, ReminderDate.self); alarms = try change(.alarms, [EventAlarm].self)
        recurrenceRules = try change(.recurrenceRules, [EventRecurrenceRule].self)
    }

    public var isEmpty: Bool {
        title == nil && collectionNativeLocator == nil && notes == nil && url == nil && priority == nil
            && due == nil && start == nil && alarms == nil && recurrenceRules == nil
    }
}

public struct ReminderUpdateRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let nativeLocator: String
    public let changes: ReminderPatch
    enum CodingKeys: String, CodingKey { case schema, changes; case nativeLocator = "native_locator" }
    public init(schema: String, nativeLocator: String, changes: ReminderPatch) {
        self.schema = schema; self.nativeLocator = nativeLocator; self.changes = changes
    }
}

public typealias ReminderDeleteRequest = ReminderGetRequest
public typealias ReminderCompleteRequest = ReminderGetRequest
public typealias ReminderReopenRequest = ReminderGetRequest

public struct ReminderCommandValidateRequest: Codable, Sendable, Equatable {
    public let schema: String
    public let commands: [ReminderValidationCommand]
}

public enum ReminderValidationCommand: Codable, Sendable, Equatable {
    case create(ReminderCreateRequest)
    case update(ReminderUpdateRequest)
    case delete(ReminderDeleteRequest)
    case complete(ReminderCompleteRequest)
    case reopen(ReminderReopenRequest)
    enum CodingKeys: String, CodingKey { case capability, payload }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .capability) {
        case "reminder.create": self = .create(try values.decode(ReminderCreateRequest.self, forKey: .payload))
        case "reminder.update": self = .update(try values.decode(ReminderUpdateRequest.self, forKey: .payload))
        case "reminder.delete": self = .delete(try values.decode(ReminderDeleteRequest.self, forKey: .payload))
        case "reminder.complete": self = .complete(try values.decode(ReminderCompleteRequest.self, forKey: .payload))
        case "reminder.reopen": self = .reopen(try values.decode(ReminderReopenRequest.self, forKey: .payload))
        default: throw DecodingError.dataCorruptedError(forKey: .capability, in: values, debugDescription: "unsupported reminder validation command")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .create(command): try values.encode("reminder.create", forKey: .capability); try values.encode(command, forKey: .payload)
        case let .update(command): try values.encode("reminder.update", forKey: .capability); try values.encode(command, forKey: .payload)
        case let .delete(command): try values.encode("reminder.delete", forKey: .capability); try values.encode(command, forKey: .payload)
        case let .complete(command): try values.encode("reminder.complete", forKey: .capability); try values.encode(command, forKey: .payload)
        case let .reopen(command): try values.encode("reminder.reopen", forKey: .capability); try values.encode(command, forKey: .payload)
        }
    }
}

public struct ReminderCommandValidateResult: Codable, Sendable, Equatable {
    public let schema: String
    public let valid: Bool
    public let commandCount: Int
    enum CodingKeys: String, CodingKey { case schema, valid; case commandCount = "command_count" }
    public init(commandCount: Int) { schema = "sherpa.planner.reminder-command-validate.success.v2"; valid = true; self.commandCount = commandCount }
}

public struct ReminderCollectionResult: Codable, Sendable, Equatable {
    public let schema: String
    public let reminderCollection: ReminderCollectionDescriptor
    enum CodingKeys: String, CodingKey { case schema; case reminderCollection = "reminder_collection" }
    public init(_ value: ReminderCollectionDescriptor) { schema = "sherpa.planner.reminder-collection-create.success.v2"; reminderCollection = value }
}

public struct ReminderCollectionDeleteResult: Codable, Sendable, Equatable {
    public let schema: String
    public let deleted: Bool
    public init() { schema = "sherpa.planner.reminder-collection-delete.success.v2"; deleted = true }
}

public struct ReminderCollectionSnapshot: Codable, Sendable, Equatable {
    public let nativeLocator, title, type: String
    public let allowsContentModifications: Bool
    enum CodingKeys: String, CodingKey { case nativeLocator = "native_locator", title, type; case allowsContentModifications = "allows_content_modifications" }
    public init(nativeLocator: String, title: String, type: String, allowsContentModifications: Bool) { self.nativeLocator = nativeLocator; self.title = title; self.type = type; self.allowsContentModifications = allowsContentModifications }
}

public struct ReminderSnapshot: Codable, Sendable, Equatable {
    public let nativeLocator: String
    public let collection: ReminderCollectionSnapshot
    public let title: String
    public let notes: String?
    public let url: String?
    public let completed: Bool
    public let completionDate: String?
    public let priority: Int
    public let due: ReminderDate?
    public let start: ReminderDate?
    public let alarms: SnapshotField<[AlarmSnapshot]>
    public let recurrenceRules: SnapshotField<[RecurrenceSnapshot]>
    enum CodingKeys: String, CodingKey {
        case nativeLocator = "native_locator", title, notes, url, completed, priority, due, start
        case collection = "reminder_collection", completionDate = "completion_date"
        case alarms; case recurrenceRules = "recurrence_rules"
    }
    public init(nativeLocator: String, collection: ReminderCollectionSnapshot, title: String, notes: String?, url: String?, completed: Bool, completionDate: String?, priority: Int, due: ReminderDate?, start: ReminderDate?, alarms: SnapshotField<[AlarmSnapshot]>, recurrenceRules: SnapshotField<[RecurrenceSnapshot]>) {
        self.nativeLocator = nativeLocator; self.collection = collection; self.title = title; self.notes = notes; self.url = url
        self.completed = completed; self.completionDate = completionDate; self.priority = priority; self.due = due; self.start = start
        self.alarms = alarms; self.recurrenceRules = recurrenceRules
    }
}

public struct ReminderItemResult: Codable, Sendable, Equatable {
    public let schema: String
    public let reminder: ReminderSnapshot
    public init(operation: String, reminder: ReminderSnapshot) { schema = "sherpa.planner.reminder-\(operation).success.v2"; self.reminder = reminder }
}
public struct ReminderListResult: Codable, Sendable, Equatable {
    public let schema: String
    public let reminders: [ReminderSnapshot]
    public init(reminders: [ReminderSnapshot]) { schema = "sherpa.planner.reminder-list.success.v2"; self.reminders = reminders }
}
public struct ReminderDeleteResult: Codable, Sendable, Equatable {
    public let schema: String
    public let deleted: Bool
    public init() { schema = "sherpa.planner.reminder-delete.success.v2"; deleted = true }
}
