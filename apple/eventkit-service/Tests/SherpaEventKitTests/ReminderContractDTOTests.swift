import Foundation
import SherpaPlannerContract
import SherpaWorkerProtocol
import Testing
@testable import SherpaEventKitAdapter

@Test func reminderCommandValidationIsAllOrNothingAndSideEffectFree() async throws {
    let valid = try WorkerRequest(data: Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-reminder-validate","operation_id":"op-reminder-validate","capability":"reminder.command.validate","payload":{"schema":"sherpa.planner.reminder-command-validate.request.v2","commands":[{"capability":"reminder.create","payload":{"schema":"sherpa.planner.reminder-create.request.v2","title":"Synthetic","due":{"year":2026,"month":8,"day":10}}},{"capability":"reminder.complete","payload":{"schema":"sherpa.planner.reminder-complete.request.v2","native_locator":"opaque-reminder"}}]},"deadline_ms":1000,"idempotency_key":"idem-reminder-validate","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8))
    let accepted = await EventKitWorker().handle(valid)
    #expect(accepted.status == .succeeded)

    let invalid = try WorkerRequest(data: Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-reminder-invalid","operation_id":"op-reminder-invalid","capability":"reminder.command.validate","payload":{"schema":"sherpa.planner.reminder-command-validate.request.v2","commands":[{"capability":"reminder.create","payload":{"schema":"sherpa.planner.reminder-create.request.v2","title":"Synthetic"}},{"capability":"reminder.create","payload":{"schema":"sherpa.planner.reminder-create.request.v2","title":" "}}]},"deadline_ms":1000,"idempotency_key":"idem-reminder-invalid","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8))
    let rejected = await EventKitWorker().handle(invalid)
    #expect(rejected.status == .failed)
    #expect(rejected.stableErrorCode == "protocol.invalid_payload")
}

@Test func reminderUpdatePatchDistinguishesClearFromOmission() throws {
    let data = Data(#"{"schema":"sherpa.planner.reminder-update.request.v2","native_locator":"opaque","changes":{"notes":null,"priority":4}}"#.utf8)
    let command = try JSONDecoder().decode(ReminderUpdateRequest.self, from: data)
    #expect(command.changes.title == nil)
    #expect(command.changes.notes == .clear)
    #expect(command.changes.priority == .set(4))
}
