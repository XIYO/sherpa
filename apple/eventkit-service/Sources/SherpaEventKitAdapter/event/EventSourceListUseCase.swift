import SherpaPlannerContract
@preconcurrency import EventKit

protocol EventSourceListingStore: AnyObject {
    func refreshSourcesIfNecessary()
    func calendars(for entityType: EKEntityType) -> [EKCalendar]
}

extension EKEventStore: EventSourceListingStore {}

func typedEventSourceList(store: some EventSourceListingStore) -> EventSourceListResult {
    // EventKit is a device-local view of remote accounts. Ask it to pull remote
    // source changes before treating this list as discovery evidence.
    store.refreshSourcesIfNecessary()
    let grouped = Dictionary(grouping: store.calendars(for: .event), by: { $0.source.sourceIdentifier })
    let sources = grouped.values.compactMap { collections -> EventSourceDescriptor? in
        guard let source = collections.first?.source else { return nil }
        return EventSourceDescriptor(
            nativeLocator: source.sourceIdentifier,
            title: source.title,
            type: sourceType(source.sourceType),
            eventCollections: collections.map {
                EventCollectionDescriptor(
                    nativeLocator: $0.calendarIdentifier,
                    title: $0.title,
                    type: calendarType($0.type),
                    allowsContentModifications: $0.allowsContentModifications
                )
            }.sorted { $0.nativeLocator < $1.nativeLocator }
        )
    }.sorted { $0.nativeLocator < $1.nativeLocator }
    return EventSourceListResult(sources: sources)
}
