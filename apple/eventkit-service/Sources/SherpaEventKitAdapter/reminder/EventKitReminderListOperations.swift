import SherpaWorkerProtocol
import SherpaPlannerContract
@preconcurrency import EventKit
import Foundation

final class EventKitReminderListOperations {
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func create(_ command: ReminderCollectionCreateRequest) throws -> ReminderCollectionResult {
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = command.title
        list.source = try destinationSource(command.sourceNativeLocator)
        try store.saveCalendar(list, commit: true)
        let verified = try readBack(list)
        return ReminderCollectionResult(.init(
            nativeLocator: verified.calendarIdentifier, title: verified.title,
            type: calendarType(verified.type),
            allowsContentModifications: verified.allowsContentModifications
        ))
    }

    func delete(_ command: ReminderCollectionDeleteRequest) throws -> ReminderCollectionDeleteResult {
        let reference = command.collectionNativeLocator
        guard let list = store.calendars(for: .reminder).first(where: {
            $0.calendarIdentifier == reference
        }) else {
            throw EventKitWorkerError.notFound
        }
        try requireWritableDestination(
            allowsContentModifications: list.allowsContentModifications
        )

        try store.removeCalendar(list, commit: true)
        guard !store.calendars(for: .reminder).contains(where: {
            $0.calendarIdentifier == reference
        }) else {
            throw EventKitWorkerError.verificationFailed
        }
        return ReminderCollectionDeleteResult()
    }

    private func destinationSource(_ reference: String?) throws -> EKSource {
        if let reference {
            guard let source = store.sources.first(where: { $0.sourceIdentifier == reference }) else {
                throw EventKitWorkerError.notFound
            }
            return source
        }
        guard let source = store.defaultCalendarForNewReminders()?.source else {
            throw EventKitWorkerError.notFound
        }
        return source
    }

    private func readBack(_ list: EKCalendar) throws -> EKCalendar {
        guard let verified = store.calendars(for: .reminder).first(where: {
            $0.calendarIdentifier == list.calendarIdentifier
        }) else {
            throw EventKitWorkerError.verificationFailed
        }
        return verified
    }
}
