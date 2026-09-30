import Foundation
import SherpaPlannerContract
import SherpaWorkerProtocol
import Testing
@testable import SherpaEventKitAdapter

@Test func eventPatchDistinguishesOmittedFieldsFromExplicitClear() throws {
    let data = Data(#"{"schema":"sherpa.planner.event-update.request.v2","native_locator":"evt","span":"this","changes":{"notes":null}}"#.utf8)
    let command = try JSONDecoder().decode(EventUpdateRequest.self, from: data)
    #expect(command.changes.title == nil)
    #expect(command.changes.notes == .clear)
    #expect(!command.changes.isEmpty)
}

@Test func eventCommandValidationIsStrictAndSideEffectFree() async throws {
    let valid = try WorkerRequest(data: Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-validate","operation_id":"op-validate","capability":"event.command.validate","payload":{"schema":"sherpa.planner.event-command-validate.request.v2","commands":[{"capability":"event.create","payload":{"schema":"sherpa.planner.event-create.request.v2","title":"Synthetic","start":"2026-08-10T00:00:00Z","end":"2026-08-10T01:00:00Z"}}]},"deadline_ms":1000,"idempotency_key":"idem-validate","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8))
    let accepted = await EventKitWorker().handle(valid)
    #expect(accepted.status == .succeeded)

    let invalid = try WorkerRequest(data: Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-invalid","operation_id":"op-invalid","capability":"event.command.validate","payload":{"schema":"sherpa.planner.event-command-validate.request.v2","commands":[{"capability":"event.create","payload":{"schema":"sherpa.planner.event-create.request.v2","title":"Synthetic","start":"2026-08-10T00:00:00Z","end":"2026-08-10T01:00:00Z"}},{"capability":"event.create","payload":{"schema":"sherpa.planner.event-create.request.v2","title":" ","start":"2026-08-10T00:00:00Z","end":"2026-08-10T01:00:00Z"}}]},"deadline_ms":1000,"idempotency_key":"idem-invalid","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8))
    let rejected = await EventKitWorker().handle(invalid)
    #expect(rejected.status == .failed)
    #expect(rejected.stableErrorCode == "protocol.invalid_payload")
}

@Test func eventAlarmDTORejectsFieldsFromTheOtherVariant() {
    let data = Data(#"{"kind":"absolute","date":"2026-08-10T00:00:00Z","offset_seconds":-60}"#.utf8)
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(EventAlarm.self, from: data)
    }
}
