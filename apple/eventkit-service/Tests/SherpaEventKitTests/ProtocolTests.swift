import Foundation
import SherpaWorkerProtocol
import Testing
@testable import SherpaEventKitAdapter

@Test func parsesAValidRequest() throws {
    let data = Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-1","operation_id":"op-1","capability":"capabilities","payload":{},"deadline_ms":1000,"idempotency_key":"idem-1","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8)
    let request = try WorkerRequest(data: data)
    #expect(request.requestID == "req-1")
    #expect(request.capability == "capabilities")
    #expect(request.effect == .read)
}

@Test func rejectsUnknownEnvelopeFields() {
    let data = Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-1","operation_id":"op-1","capability":"capabilities","payload":{},"deadline_ms":1000,"idempotency_key":"idem-1","policy":{"effect":"read","required_evidence":"none","artifact_directory":null},"unexpected":true}"#.utf8)
    #expect(throws: WorkerProtocolError.self) {
        _ = try WorkerRequest(data: data)
    }
}

@Test func rejectsUnsafeLogIdentifiers() {
    let data = Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.planner.v2","request_id":"req-1","operation_id":"op-1","capability":"capabilities\nprivate","payload":{},"deadline_ms":1000,"idempotency_key":"idem-1","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8)
    #expect(throws: WorkerProtocolError.self) {
        _ = try WorkerRequest(data: data)
    }
}

@Test func rejectsAnUnsupportedVersion() {
    let data = Data(#"{"kind":"request","protocol_version":"1.0.0","application_contract":"sherpa.planner.v2","request_id":"req-1","operation_id":"op-1","capability":"capabilities","payload":{},"deadline_ms":1000,"idempotency_key":"idem-1","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8)
    #expect(throws: WorkerProtocolError.self) {
        _ = try WorkerRequest(data: data)
    }
}

@Test func occurrenceAwareEventLocatorRoundTripsOpaqueIdentifiers() throws {
    let occurrence = try #require(ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
    let observed = try #require(ISO8601DateFormatter().date(from: "2026-08-03T00:00:00Z"))
    let locator = EventLocator(
        eventIdentifier: "opaque:id/with+symbols",
        occurrenceDate: occurrence,
        observedStartDate: observed
    )
    #expect(try EventLocator(wireValue: locator.wireValue) == locator)
}

@Test func eventLocatorRejectsMalformedVersionedValues() {
    #expect(throws: WorkerProtocolError.self) {
        _ = try EventLocator(wireValue: "ekev1:not+base64:-:-")
    }
}
