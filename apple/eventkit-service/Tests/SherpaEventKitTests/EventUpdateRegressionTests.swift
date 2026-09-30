import EventKit
import Foundation
import SherpaWorkerProtocol
import SherpaPlannerApplication
import SherpaPlannerContract
import Testing
@testable import SherpaEventKitAdapter

@Test func allDayUpdateConvertsTheCanonicalExclusiveEndAtADSTBoundary() throws {
    let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let start = try #require(parseDate("2026-11-01T00:00:00-07:00"))
    let canonicalExclusiveEnd = try #require(parseDate("2026-11-02T00:00:00-08:00"))
    let providerInclusiveEnd = try #require(parseDate("2026-11-01T23:59:59-08:00"))

    // `update` converts the supplied canonical end before handing it to
    // EventKit. The opposite UTC offsets here prove the conversion uses the
    // local calendar day, not a fixed 24-hour subtraction.
    let nativeEnd = eventKitAllDayEnd(
        canonicalExclusiveEnd,
        isAllDay: true,
        timeZone: timeZone
    )

    #expect(start < nativeEnd)
    #expect(nativeEnd == providerInclusiveEnd)
    #expect(canonicalAllDayEnd(nativeEnd, isAllDay: true, timeZone: timeZone) == canonicalExclusiveEnd)
}

@Test func eventUpdateRejectsMalformedChangesBeforeResolvingTheNativeReference() {
    let validator = EventCommandValidator()

    #expect(throws: PlannerValidationError.self) {
        try validator.validate(.init(schema: "sherpa.planner.event-update.request.v2",
            nativeLocator: "missing", span: "future", changes: .init()))
    }
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(.init(schema: "sherpa.planner.event-update.request.v2",
            nativeLocator: "missing", span: "invalid", changes: .init(title: .set("valid"))))
    }
    #expect(throws: PlannerValidationError.self) {
        try validator.validate(.init(schema: "sherpa.planner.event-update.request.v2",
            nativeLocator: "missing", span: "this", changes: .init(
                start: .set("2026-08-10T10:00:00+09:00"), end: .set("2026-08-10T09:00:00+09:00"))))
    }
}
