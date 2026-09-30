import EventKit
import Foundation
import SherpaWorkerProtocol
import SherpaPlannerContract
import SherpaPlannerApplication
import Testing

@testable import SherpaEventKitAdapter

@Test func eventListSortOrderUsesStartThenTitleThenExactReference() throws {
    let start = try #require(parseDate("2026-08-10T00:00:00Z"))
    let later = try #require(parseDate("2026-08-10T01:00:00Z"))
    let keys = [
        eventListSortKey(start: start, title: "same", reference: "ekev1_b"),
        eventListSortKey(start: later, title: "earlier-title", reference: "ekev1_a"),
        eventListSortKey(start: start, title: "same", reference: "ekev1_a"),
        eventListSortKey(start: start, title: "alpha", reference: "ekev1_z"),
    ]

    #expect(keys.sorted().map(\.reference) == ["ekev1_z", "ekev1_a", "ekev1_b", "ekev1_a"])
}

@Test func eventListRechecksHalfOpenRangeRatherThanTrustingTheNativePredicate() throws {
    let from = try #require(parseDate("2026-08-10T00:00:00Z"))
    let to = try #require(parseDate("2026-08-11T00:00:00Z"))

    #expect(eventListRowIsWithinRange(
        start: try #require(parseDate("2026-08-09T23:00:00Z")),
        end: try #require(parseDate("2026-08-10T01:00:00Z")),
        from: from,
        to: to
    ))
    #expect(eventListRowIsWithinRange(
        start: try #require(parseDate("2026-08-10T23:00:00Z")),
        end: try #require(parseDate("2026-08-11T00:30:00Z")),
        from: from,
        to: to
    ))
    #expect(!eventListRowIsWithinRange(start: from, end: from, from: from, to: to))
    #expect(!eventListRowIsWithinRange(
        start: try #require(parseDate("2026-08-09T23:00:00Z")), end: from, from: from, to: to
    ))
    #expect(!eventListRowIsWithinRange(start: to, end: to.addingTimeInterval(1), from: from, to: to))
}

@Test func eventListFilterRejectsAnEscapedCalendarResult() {
    #expect(eventListCalendarMatches(returnedReference: "cal1", selectedReference: nil))
    #expect(eventListCalendarMatches(returnedReference: "cal1", selectedReference: "cal1"))
    #expect(!eventListCalendarMatches(returnedReference: "cal2", selectedReference: "cal1"))
}

@Test func eventListDuplicateReferencesCauseVerificationFailureRatherThanFirstItemSelection() {
    var seen = Set<String>()

    #expect(eventListReferenceWasNotSeen("ekev1_same", seen: &seen))
    #expect(!eventListReferenceWasNotSeen("ekev1_same", seen: &seen))
}

@Test func eventListRejectsAnExplicitEmptyCalendarSelectorBeforeEventKitLookup() {
    let validator = EventCommandValidator()

    #expect(throws: PlannerValidationError.self) {
        try validator.validate(.init(schema: "sherpa.planner.event-list.request.v2",
            from: "2026-08-10T00:00:00Z", to: "2026-08-11T00:00:00Z",
            limit: nil, collectionNativeLocator: ""))
    }
}

@Test func eventWorkerFailureTranslationPreservesMissingAndReadOnlyDestinations() {
    #expect(workerFailure(requestID: "req", error: .notFound).stableErrorCode == "eventkit.not_found")
    #expect(
        workerFailure(requestID: "req", error: .readOnlyDestination).stableErrorCode
            == "eventkit.destination_read_only"
    )
    #expect(
        workerFailure(requestID: "req", error: .accessUnavailable).stableErrorCode
            == "eventkit.access_unavailable"
    )
    #expect(throws: EventKitWorkerError.self) {
        try requireWritableDestination(allowsContentModifications: false)
    }
    #expect(throws: Never.self) {
        try requireWritableDestination(allowsContentModifications: true)
    }
}
