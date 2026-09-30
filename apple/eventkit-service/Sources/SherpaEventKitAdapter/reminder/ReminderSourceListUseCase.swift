import SherpaPlannerContract
@preconcurrency import EventKit

func typedReminderSourceList(store: some EventSourceListingStore) -> ReminderSourceListResult {
    store.refreshSourcesIfNecessary()
    let grouped = Dictionary(grouping: store.calendars(for: .reminder), by: { $0.source.sourceIdentifier })
    return ReminderSourceListResult(sources: grouped.values.compactMap { collections in
        guard let source = collections.first?.source else { return nil }
        return ReminderSourceDescriptor(nativeLocator: source.sourceIdentifier, title: source.title,
            type: sourceType(source.sourceType), reminderCollections: collections.map {
                ReminderCollectionDescriptor(nativeLocator: $0.calendarIdentifier, title: $0.title,
                    type: calendarType($0.type), allowsContentModifications: $0.allowsContentModifications)
            }.sorted { $0.nativeLocator < $1.nativeLocator })
    }.sorted { $0.nativeLocator < $1.nativeLocator })
}
