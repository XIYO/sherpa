import SherpaWorkerProtocol
import SherpaPlannerContract
import SherpaPlannerApplication
@preconcurrency import EventKit
import Foundation

public final class EventKitWorker {
    private let store: EKEventStore
    private let calendars: EventKitCalendarOperations
    private let events: EventKitEventOperations
    private let reminderLists: EventKitReminderListOperations
    private let reminders: EventKitReminderOperations

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
        calendars = EventKitCalendarOperations(store: store)
        events = EventKitEventOperations(store: store)
        reminderLists = EventKitReminderListOperations(store: store)
        reminders = EventKitReminderOperations(store: store)
    }

    public func handle(_ request: WorkerRequest) async -> WorkerResponse {
        do {
            guard request.applicationContract == "sherpa.planner.v2" else {
                throw WorkerProtocolError.invalidPayload
            }
            if request.capability == PlannerCapability.eventAuthorizationStatus.rawValue {
                _ = try request.payload.decode(as: EmptyPlannerRequest.self, allowedKeys: ["schema"])
                return .success(request: request, result: try encodeJSONObject(AuthorizationResult(
                    domain: "event", authorization: authorizationName(EKEventStore.authorizationStatus(for: .event))
                )))
            }
            if request.capability == PlannerCapability.eventAuthorizationRequest.rawValue {
                _ = try request.payload.decode(as: EmptyPlannerRequest.self, allowedKeys: ["schema"])
                _ = try await store.requestFullAccessToEvents()
                return .success(
                    request: request,
                    result: try encodeJSONObject(AuthorizationResult(
                        domain: "event", authorization: authorizationName(EKEventStore.authorizationStatus(for: .event))
                    )),
                    effect: .init(kind: .authorizationPrompt, state: .applied),
                    evidence: .init(kind: .authorizationReadback, state: .matched)
                )
            }
            if request.capability == PlannerCapability.eventSourceList.rawValue {
                _ = try request.payload.decode(
                    as: EventSourceListRequest.self,
                    allowedKeys: ["schema"]
                )
                if let entity = entityRequiringFullAccess(for: request.capability) {
                    try requireFullAccess(EKEventStore.authorizationStatus(for: entity))
                }
                return .success(
                    request: request,
                    result: try encodeJSONObject(typedEventSourceList(store: store))
                )
            }
            if request.capability == PlannerCapability.eventCollectionCreate.rawValue {
                let command = try request.payload.decode(
                    as: EventCollectionCreateRequest.self,
                    allowedKeys: ["schema", "title", "source_native_locator"],
                    requiredKeys: ["schema", "title"]
                )
                try requireFullAccess(EKEventStore.authorizationStatus(for: .event))
                return .success(
                    request: request,
                    result: try encodeJSONObject(calendars.create(command)),
                    effect: .init(kind: .nativeMutation, state: .applied),
                    evidence: .init(kind: .nativeReadback, state: .matched)
                )
            }
            if request.capability == PlannerCapability.eventCollectionDelete.rawValue {
                let command = try request.payload.decode(
                    as: EventCollectionDeleteRequest.self,
                    allowedKeys: ["schema", "collection_native_locator"]
                )
                try requireFullAccess(EKEventStore.authorizationStatus(for: .event))
                return .success(
                    request: request,
                    result: try encodeJSONObject(calendars.delete(command)),
                    effect: .init(kind: .nativeMutation, state: .applied),
                    evidence: .init(kind: .nativeAbsenceReadback, state: .matched)
                )
            }
            if request.capability == PlannerCapability.eventCommandValidate.rawValue {
                let batch = try request.payload.decodeExact(as: EventCommandValidateRequest.self,
                    allowedKeys: ["schema", "commands"])
                let result = try EventCommandValidator().validate(batch)
                return .success(request: request, result: try encodeJSONObject(result))
            }
            if request.capability == PlannerCapability.eventList.rawValue {
                let command = try request.payload.decode(as: EventListRequest.self,
                    allowedKeys: ["schema", "from", "to", "limit", "collection_native_locator"],
                    requiredKeys: ["schema", "from", "to"])
                try EventCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .event))
                return try typedResponse(request, result: events.list(command))
            }
            if request.capability == PlannerCapability.eventGet.rawValue {
                let command = try request.payload.decode(as: EventGetRequest.self,
                    allowedKeys: ["schema", "native_locator"])
                try EventCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .event))
                return try typedResponse(request, result: events.get(command))
            }
            if request.capability == PlannerCapability.eventCreate.rawValue {
                let command = try request.payload.decode(as: EventCreateRequest.self,
                    allowedKeys: ["schema", "title", "start", "end", "all_day", "collection_native_locator", "notes", "location", "url", "time_zone", "alarms", "recurrence_rules"],
                    requiredKeys: ["schema", "title", "start", "end"])
                try EventCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .event))
                return try typedResponse(request, result: events.create(command))
            }
            if request.capability == PlannerCapability.eventUpdate.rawValue {
                let command = try request.payload.decode(as: EventUpdateRequest.self,
                    allowedKeys: ["schema", "native_locator", "span", "changes"])
                try EventCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .event))
                return try typedResponse(request, result: events.update(command))
            }
            if request.capability == PlannerCapability.eventDelete.rawValue {
                let command = try request.payload.decode(as: EventDeleteRequest.self,
                    allowedKeys: ["schema", "native_locator", "span"])
                try EventCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .event))
                return try typedResponse(request, result: events.delete(command))
            }
            if request.capability == PlannerCapability.reminderAuthorizationStatus.rawValue {
                _ = try request.payload.decode(as: EmptyPlannerRequest.self, allowedKeys: ["schema"])
                return .success(request: request, result: try encodeJSONObject(AuthorizationResult(
                    domain: "reminder", authorization: authorizationName(EKEventStore.authorizationStatus(for: .reminder))
                )))
            }
            if request.capability == PlannerCapability.reminderAuthorizationRequest.rawValue {
                _ = try request.payload.decode(as: EmptyPlannerRequest.self, allowedKeys: ["schema"])
                _ = try await store.requestFullAccessToReminders()
                return .success(request: request, result: try encodeJSONObject(AuthorizationResult(
                    domain: "reminder", authorization: authorizationName(EKEventStore.authorizationStatus(for: .reminder))
                )), effect: .init(kind: .authorizationPrompt, state: .applied),
                    evidence: .init(kind: .authorizationReadback, state: .matched))
            }
            if request.capability == PlannerCapability.reminderSourceList.rawValue {
                _ = try request.payload.decode(as: EmptyPlannerRequest.self, allowedKeys: ["schema"])
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return .success(request: request, result: try encodeJSONObject(typedReminderSourceList(store: store)))
            }
            if request.capability == PlannerCapability.reminderCommandValidate.rawValue {
                let command = try request.payload.decode(as: ReminderCommandValidateRequest.self,
                    allowedKeys: ["schema", "commands"])
                try ReminderCommandValidator().validate(command)
                return .success(request: request, result: try encodeJSONObject(ReminderCommandValidateResult(commandCount: command.commands.count)))
            }
            if request.capability == PlannerCapability.reminderCollectionCreate.rawValue {
                let command = try request.payload.decode(as: ReminderCollectionCreateRequest.self,
                    allowedKeys: ["schema", "title", "source_native_locator"], requiredKeys: ["schema", "title"])
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: reminderLists.create(command))
            }
            if request.capability == PlannerCapability.reminderCollectionDelete.rawValue {
                let command = try request.payload.decode(as: ReminderCollectionDeleteRequest.self,
                    allowedKeys: ["schema", "collection_native_locator"])
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: reminderLists.delete(command))
            }
            if request.capability == PlannerCapability.reminderList.rawValue {
                let command = try request.payload.decode(as: ReminderListRequest.self,
                    allowedKeys: ["schema", "collection_native_locator", "limit", "completed"])
                try ReminderCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: await reminders.list(command))
            }
            if request.capability == PlannerCapability.reminderGet.rawValue {
                let command = try request.payload.decode(as: ReminderGetRequest.self,
                    allowedKeys: ["schema", "native_locator"])
                try ReminderCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: reminders.get(command))
            }
            if request.capability == PlannerCapability.reminderCreate.rawValue {
                let command = try request.payload.decode(as: ReminderCreateRequest.self,
                    allowedKeys: ["schema", "title", "collection_native_locator", "notes", "url", "priority", "due", "start", "alarms", "recurrence_rules"],
                    requiredKeys: ["schema", "title"])
                try ReminderCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: reminders.create(command))
            }
            if request.capability == PlannerCapability.reminderUpdate.rawValue {
                let command = try request.payload.decode(as: ReminderUpdateRequest.self,
                    allowedKeys: ["schema", "native_locator", "changes"])
                try ReminderCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: reminders.update(command))
            }
            if request.capability == PlannerCapability.reminderComplete.rawValue || request.capability == PlannerCapability.reminderReopen.rawValue {
                let command = try request.payload.decode(as: ReminderGetRequest.self,
                    allowedKeys: ["schema", "native_locator"])
                try ReminderCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: await reminders.setCompleted(command, completed: request.capability == PlannerCapability.reminderComplete.rawValue))
            }
            if request.capability == PlannerCapability.reminderDelete.rawValue {
                let command = try request.payload.decode(as: ReminderDeleteRequest.self,
                    allowedKeys: ["schema", "native_locator"])
                try ReminderCommandValidator().validate(command)
                try requireFullAccess(EKEventStore.authorizationStatus(for: .reminder))
                return try typedResponse(request, result: reminders.delete(command))
            }
            if request.capability == "capabilities" {
                return try typedResponse(
                    request,
                    result: WorkerCapabilitiesResult(capabilities: capabilityReport())
                )
            }
            throw WorkerProtocolError.unsupportedCapability
        } catch let error as WorkerProtocolError {
            return .failure(request: request, code: error.stableCode)
        } catch is PlannerValidationError {
            return .failure(request: request, code: WorkerProtocolError.invalidPayload.stableCode)
        } catch let error as EventKitWorkerError {
            return workerFailure(request: request, error: error)
        } catch {
            if let response = eventKitFailure(request: request, error: error) {
                return response
            }
            return .failure(request: request, code: "eventkit.operation_failed")
        }
    }

    private func typedResponse<Result: Encodable>(_ request: WorkerRequest, result: Result) throws -> WorkerResponse {
        .success(request: request, result: try encodeJSONObject(result),
            effect: effectOutcome(for: request), evidence: evidenceOutcome(for: request))
    }

    private func capabilityReport() -> [WorkerCapabilityDescriptor] {
        [
            "event.authorization.status", "event.authorization.request",
            "event.source.list", "event.collection.create", "event.collection.delete", "event.command.validate", "event.list", "event.get", "event.create", "event.update", "event.delete",
            "reminder.authorization.status", "reminder.authorization.request",
            "reminder.source.list", "reminder.collection.create", "reminder.collection.delete", "reminder.command.validate", "reminder.list", "reminder.get", "reminder.create",
            "reminder.update", "reminder.complete", "reminder.reopen", "reminder.delete",
        ].map(capabilityDescriptor)
    }

}

private func capabilityDescriptor(_ capability: String) -> WorkerCapabilityDescriptor {
    let authorizationRequest = capability.hasSuffix("authorization.request")
    let delete = capability.hasSuffix(".delete")
    let mutation = authorizationRequest || delete || [
        ".create", ".update", ".complete", ".reopen",
    ].contains(where: capability.hasSuffix)
    let effect = authorizationRequest ? "authorization_prompt" : (mutation ? "mutation" : "read")
    let evidence = authorizationRequest ? "authorization_readback"
        : (delete ? "native_absence_readback" : (mutation ? "native_readback" : "none"))
    let destination = if capability.hasPrefix("event.") &&
        (capability.hasSuffix(".create") || capability.hasSuffix(".update")) {
        "event_collection"
    } else if capability.hasPrefix("reminder.") &&
        (capability.hasSuffix(".create") || capability.hasSuffix(".update")) {
        "reminder_collection"
    } else { "none" }
    return WorkerCapabilityDescriptor(
        capability: capability,
        effect: effect,
        requiredEvidence: evidence,
        destination: destination,
        supportsIncompleteOutcomes: mutation
    )
}

private func effectOutcome(for request: WorkerRequest) -> WorkerEffectOutcome {
    switch request.policy.effect {
    case .read: .init(kind: .none, state: .notApplicable)
    case .authorizationPrompt: .init(kind: .authorizationPrompt, state: .applied)
    case .mutation: .init(kind: .nativeMutation, state: .applied)
    case .dispatch: .init(kind: .outboundDispatch, state: .applied)
    }
}

private func evidenceOutcome(for request: WorkerRequest) -> WorkerEvidence? {
    switch request.policy.requiredEvidence {
    case .none: nil
    case .authorizationReadback: .init(kind: .authorizationReadback, state: .matched)
    case .nativeReadback: .init(kind: .nativeReadback, state: .matched)
    case .nativeAbsenceReadback: .init(kind: .nativeAbsenceReadback, state: .matched)
    case .applicationAcceptance: .init(kind: .applicationAcceptance, state: .matched)
    }
}

func entityRequiringFullAccess(for capability: String) -> EKEntityType? {
    switch capability {
    case "event.source.list", "event.collection.create", "event.collection.delete",
         "event.list", "event.get", "event.create", "event.update", "event.delete":
        .event
    case "reminder.source.list", "reminder.collection.create", "reminder.collection.delete",
         "reminder.list", "reminder.get", "reminder.create", "reminder.update",
         "reminder.complete", "reminder.reopen", "reminder.delete":
        .reminder
    default:
        nil
    }
}

func requireFullAccess(_ status: EKAuthorizationStatus) throws {
    guard status == .fullAccess else { throw EventKitWorkerError.accessUnavailable }
}

func authorizationName(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .fullAccess: "full_access"
    case .writeOnly: "write_only"
    case .notDetermined: "not_determined"
    case .denied: "denied"
    case .restricted: "restricted"
    @unknown default: "unknown"
    }
}
