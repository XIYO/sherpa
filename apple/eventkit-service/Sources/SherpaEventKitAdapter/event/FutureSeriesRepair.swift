import SherpaWorkerProtocol
@preconcurrency import EventKit
import Foundation

/// The repair is deliberately narrow: it never chooses between two events.
/// It removes the old branch only after EventKit has separately exposed the
/// source occurrence and a distinct replacement branch at their exact starts.
func shouldTrimStaleFutureSeries(
    span: EKSpan,
    originalStart: Date,
    requestedStart: Date,
    staleStart: Date?,
    replacementStart: Date?,
    distinctEvents: Bool
) -> Bool {
    span == .futureEvents
        && distinctEvents
        && staleStart.map { sameInstant($0, originalStart) } == true
        && replacementStart.map { sameInstant($0, requestedStart) } == true
}

func staleFutureSeriesWasRemoved(_ remainingOriginalOccurrence: Bool) -> Bool {
    !remainingOriginalOccurrence
}

func sameInstant(_ lhs: Date, _ rhs: Date) -> Bool {
    abs(lhs.timeIntervalSince(rhs)) < 0.001
}
