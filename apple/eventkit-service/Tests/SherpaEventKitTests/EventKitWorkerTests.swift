import EventKit
import Foundation
import SherpaWorkerProtocol
import Testing
@testable import SherpaEventKitAdapter

@Test func mapsUnavailableEventKitAccessToUserAction() throws {
    let response = try #require(
        eventKitFailure(
            requestID: "req-authorization",
            error: NSError(
                domain: EKError.errorDomain,
                code: EKError.eventStoreNotAuthorized.rawValue
            )
        )
    )

    #expect(response.status == .failed)
    #expect(response.stableErrorCode == "eventkit.access_unavailable")
    #expect(response.error?.retry == .never)
}

@Test func everyEventAndReminderOperationRequiresFullAccess() throws {
    #expect(entityRequiringFullAccess(for: "event.source.list") == .event)
    #expect(entityRequiringFullAccess(for: "event.create") == .event)
    #expect(entityRequiringFullAccess(for: "reminder.source.list") == .reminder)
    #expect(entityRequiringFullAccess(for: "reminder.complete") == .reminder)
    #expect(entityRequiringFullAccess(for: "event.authorization.status") == nil)
    #expect(entityRequiringFullAccess(for: "reminder.authorization.status") == nil)
    #expect(entityRequiringFullAccess(for: "capabilities") == nil)
    #expect(entityRequiringFullAccess(for: "reminder.unknown") == nil)

    try requireFullAccess(.fullAccess)
    for status in [
        EKAuthorizationStatus.writeOnly,
        .notDetermined,
        .denied,
        .restricted,
    ] {
        #expect(throws: EventKitWorkerError.self) { try requireFullAccess(status) }
    }
    #expect(authorizationName(.fullAccess) == "full_access")
    #expect(authorizationName(.writeOnly) == "write_only")
    #expect(authorizationName(.notDetermined) == "not_determined")
    #expect(authorizationName(.denied) == "denied")
    #expect(authorizationName(.restricted) == "restricted")
}

@Test func advertisesCurrentCalendarAndReminderCapabilities() async throws {
    let request = try WorkerRequest(data: Data(
        #"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-capabilities","operation_id":"op-capabilities","capability":"capabilities","payload":{"schema":"sherpa.planner.test.request.v2"},"deadline_ms":1000,"idempotency_key":"idem-capabilities","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8
    ))

    let response = await EventKitWorker().handle(request)
    let capabilities: [String] = if case let .object(result)? = response.result,
        case let .array(values)? = result["capabilities"] {
        values.compactMap { value in
            guard case let .object(descriptor) = value,
                  case let .string(capability)? = descriptor["capability"] else { return nil }
            return capability
        }
    } else { [] }

    #expect(response.status == .succeeded)
    #expect(capabilities.contains("event.source.list"))
    #expect(capabilities.contains("event.collection.create"))
    #expect(capabilities.contains("event.collection.delete"))
    #expect(capabilities.contains("event.list"))
    #expect(capabilities.contains("event.get"))
    #expect(capabilities.contains("event.create"))
    #expect(capabilities.contains("event.update"))
    #expect(capabilities.contains("event.delete"))
    #expect(capabilities.contains("reminder.source.list"))
    #expect(capabilities.contains("reminder.collection.create"))
    #expect(capabilities.contains("reminder.collection.delete"))
    #expect(capabilities.contains("reminder.list"))
    #expect(capabilities.contains("reminder.get"))
    #expect(capabilities.contains("reminder.create"))
    #expect(capabilities.contains("reminder.update"))
    #expect(capabilities.contains("reminder.complete"))
    #expect(capabilities.contains("reminder.reopen"))
    #expect(capabilities.contains("reminder.delete"))
    #expect(capabilities.allSatisfy {
        !$0.contains("attendee") && !$0.contains("invitation") && !$0.contains("rsvp")
    })
}

@Test func provisionalInvitationCapabilityRemainsUnsupported() async throws {
    let request = try WorkerRequest(data: Data(
        #"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-invitation","operation_id":"op-invitation","capability":"event.invitation.create","payload":{"schema":"sherpa.planner.test.request.v2"},"deadline_ms":1000,"idempotency_key":"idem-invitation","policy":{"effect":"mutation","required_evidence":"native_readback","artifact_directory":null}}"#.utf8
    ))

    let response = await EventKitWorker().handle(request)

    #expect(response.status == .failed)
    #expect(response.stableErrorCode == "protocol.unsupported_capability")
}
