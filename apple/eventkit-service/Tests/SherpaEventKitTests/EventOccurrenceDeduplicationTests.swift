import Testing
@testable import SherpaEventKitAdapter
import EventKit
import Foundation

private struct Occurrence: Equatable {
    let eventIdentifier: String?
    let externalIdentifier: String
    let occurrence: String
    let detached: Bool
    let value: String
}

@Test func keepsDetachedExceptionForTheSameOccurrence() {
    let occurrences = deduplicatingOccurrences(
        [
            Occurrence(
                eventIdentifier: "series", externalIdentifier: "server-series",
                occurrence: "2026-08-20T09:00:00+09:00", detached: false, value: "series"
            ),
            Occurrence(
                eventIdentifier: "series", externalIdentifier: "server-exception",
                occurrence: "2026-08-20T09:00:00+09:00", detached: true, value: "exception"
            ),
        ],
        key: { occurrence in
            occurrence.eventIdentifier.map { "\($0):\(occurrence.occurrence)" }
        },
        shouldReplace: { candidate, existing in candidate.detached && !existing.detached }
    )

    #expect(occurrences.map(\.value) == ["exception"])
}

@Test func keepsDistinctSeriesAndValuesWithoutAnIdentity() {
    let occurrences = deduplicatingOccurrences(
        [
            Occurrence(
                eventIdentifier: "series", externalIdentifier: "server-series",
                occurrence: "2026-08-20T09:00:00+09:00", detached: true, value: "exception"
            ),
            Occurrence(
                eventIdentifier: "another-series", externalIdentifier: "server-other",
                occurrence: "2026-08-20T09:00:00+09:00", detached: false, value: "separate"
            ),
            Occurrence(
                eventIdentifier: nil, externalIdentifier: "server-unidentified",
                occurrence: "2026-08-20T09:00:00+09:00", detached: false, value: "unidentified"
            ),
        ],
        key: { occurrence in
            occurrence.eventIdentifier.map { "\($0):\(occurrence.occurrence)" }
        },
        shouldReplace: { candidate, existing in candidate.detached && !existing.detached }
    )

    #expect(occurrences.map(\.value) == ["exception", "separate", "unidentified"])
}

@Test func trimsOnlyAProvenStaleFutureBranchWithOrWithoutATimeMove() {
    let original = ISO8601DateFormatter().date(from: "2026-08-10T00:00:00Z")!
    let replacement = ISO8601DateFormatter().date(from: "2026-08-10T01:00:00Z")!

    #expect(shouldTrimStaleFutureSeries(
        span: .futureEvents,
        originalStart: original,
        requestedStart: replacement,
        staleStart: original,
        replacementStart: replacement,
        distinctEvents: true
    ))
    #expect(shouldTrimStaleFutureSeries(
        span: .futureEvents,
        originalStart: original,
        requestedStart: original,
        staleStart: original,
        replacementStart: original,
        distinctEvents: true
    ))
    #expect(!shouldTrimStaleFutureSeries(
        span: .futureEvents,
        originalStart: original,
        requestedStart: replacement,
        staleStart: replacement,
        replacementStart: replacement,
        distinctEvents: true
    ))
    #expect(!shouldTrimStaleFutureSeries(
        span: .thisEvent,
        originalStart: original,
        requestedStart: replacement,
        staleStart: original,
        replacementStart: replacement,
        distinctEvents: true
    ))
    #expect(!shouldTrimStaleFutureSeries(
        span: .futureEvents,
        originalStart: original,
        requestedStart: replacement,
        staleStart: original,
        replacementStart: replacement,
        distinctEvents: false
    ))
    #expect(staleFutureSeriesWasRemoved(false))
    #expect(!staleFutureSeriesWasRemoved(true))
}
