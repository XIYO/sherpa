import EventKit
import SherpaEventKitAdapter
import SherpaPlannerContract
import SherpaWorkerProtocol
import Testing
@testable import SherpaEventKitAdapter

@Test func productionGraphModulesAreImportableInCanonicalOrder() {
    _ = SherpaEventKitAdapterBoundary.self
    #expect(PlannerCapability.eventSourceList.rawValue == "event.source.list")
    #expect(PlannerCapability.reminderCollectionCreate.rawValue == "reminder.collection.create")
}

@Test func eventSourceListDTOUsesCanonicalCollectionAndLocatorFields() throws {
    let result = EventSourceListResult(sources: [
        EventSourceDescriptor(
            nativeLocator: "source-1", title: "Source", type: "local",
            eventCollections: [
                EventCollectionDescriptor(
                    nativeLocator: "collection-1", title: "Calendar", type: "local",
                    allowsContentModifications: true
                ),
            ]
        ),
    ])
    let object = try encodeJSONObject(result)
    #expect(object["schema"]?.string == "sherpa.planner.event-source-list.success.v2")
    let source = object["sources"]?.array?.first?.object
    #expect(source?["native_locator"]?.string == "source-1")
    #expect(source?["event_collections"]?.array?.first?.object?["native_locator"]?.string == "collection-1")
    #expect(source?["calendars"] == nil)
}

@Test func legacyCapabilityNamesAreNotDispatched() {
    #expect(entityRequiringFullAccess(for: "event.sources") == nil)
    #expect(entityRequiringFullAccess(for: "event.calendar.create") == nil)
    #expect(entityRequiringFullAccess(for: "reminder.list.create") == nil)
    #expect(entityRequiringFullAccess(for: "event.source.list") == .event)
    #expect(entityRequiringFullAccess(for: "reminder.collection.create") == .reminder)
}

@Test func contractRejectsLegacyLocatorKeys() {
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(EventGetRequest.self, from: Data(#"{"schema":"sherpa.planner.event-get.request.v2","native_reference":"legacy"}"#.utf8))
    }
    let payload = Data(#"{"schema":"sherpa.planner.event-list.request.v2","from":"2027-01-01T00:00:00Z","to":"2027-01-02T00:00:00Z","calendar_native_reference":"legacy"}"#.utf8)
    let decoded = try? JSONDecoder().decode(EventListRequest.self, from: payload)
    #expect(decoded?.collectionNativeLocator == nil)
}
