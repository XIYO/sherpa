import EventKit
import Testing
@testable import SherpaEventKitAdapter

@Test func eventSourceDiscoveryRefreshesRemoteSourcesBeforeReadingCalendars() {
    let store = EventSourceListingStoreSpy()

    let result = typedEventSourceList(store: store)

    #expect(store.requestedEntities == [.event])
    #expect(result.sources.isEmpty)
}

@Test func reminderSourceDiscoveryRefreshesRemoteSourcesBeforeReadingCalendars() {
    let store = EventSourceListingStoreSpy()

    let result = typedReminderSourceList(store: store)

    #expect(store.requestedEntities == [.reminder])
    #expect(result.sources.isEmpty)
}

private final class EventSourceListingStoreSpy: EventSourceListingStore {
    private(set) var refreshRequested = false
    private(set) var requestedEntities: [EKEntityType] = []

    func refreshSourcesIfNecessary() {
        refreshRequested = true
    }

    func calendars(for entityType: EKEntityType) -> [EKCalendar] {
        #expect(refreshRequested)
        requestedEntities.append(entityType)
        return []
    }
}
