import SherpaPlannerContract
import SherpaWorkerProtocol
@preconcurrency import EventKit
import Foundation

final class EventKitCalendarOperations {
    private let store: EKEventStore
    init(store: EKEventStore) { self.store = store }

    func create(_ request: EventCollectionCreateRequest) throws -> EventCollectionCreateResult {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.title.utf8.count <= 1_024, !request.title.contains("\0")
        else { throw WorkerProtocolError.invalidPayload }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = request.title
        calendar.source = try destinationSource(request.sourceNativeLocator)
        try store.saveCalendar(calendar, commit: true)
        let verified = try readBack(calendar)
        return EventCollectionCreateResult(eventCollection: descriptor(verified))
    }

    func delete(_ request: EventCollectionDeleteRequest) throws -> EventCollectionDeleteResult {
        guard !request.collectionNativeLocator.isEmpty,
              request.collectionNativeLocator.utf8.count <= 4_096,
              !request.collectionNativeLocator.contains("\0")
        else { throw WorkerProtocolError.invalidPayload }
        guard let calendar = store.calendars(for: .event).first(where: {
            $0.calendarIdentifier == request.collectionNativeLocator
        }) else { throw EventKitWorkerError.notFound }
        try requireWritableDestination(allowsContentModifications: calendar.allowsContentModifications)
        try store.removeCalendar(calendar, commit: true)
        guard !store.calendars(for: .event).contains(where: {
            $0.calendarIdentifier == request.collectionNativeLocator
        }) else { throw EventKitWorkerError.verificationFailed }
        return EventCollectionDeleteResult()
    }

    private func destinationSource(_ locator: String?) throws -> EKSource {
        if let locator {
            guard !locator.isEmpty, locator.utf8.count <= 4_096, !locator.contains("\0")
            else { throw WorkerProtocolError.invalidPayload }
            guard let source = store.sources.first(where: { $0.sourceIdentifier == locator })
            else { throw EventKitWorkerError.notFound }
            return source
        }
        guard let source = store.defaultCalendarForNewEvents?.source else { throw EventKitWorkerError.notFound }
        return source
    }

    private func readBack(_ calendar: EKCalendar) throws -> EKCalendar {
        guard let verified = store.calendars(for: .event).first(where: {
            $0.calendarIdentifier == calendar.calendarIdentifier
        }) else { throw EventKitWorkerError.verificationFailed }
        return verified
    }

    private func descriptor(_ calendar: EKCalendar) -> EventCollectionDescriptor {
        EventCollectionDescriptor(nativeLocator: calendar.calendarIdentifier, title: calendar.title,
            type: calendarType(calendar.type), allowsContentModifications: calendar.allowsContentModifications)
    }
}
