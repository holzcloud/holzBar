import Testing
@testable import HolzBarCore

@Suite("HubModuleLifecycle")
struct HubModuleLifecycleTests {
    private let registered = ["now-playing", "calendar", "timers"]

    @Test("With the hub off nothing starts and every running module stops")
    func hubOff() {
        let plan = HubModuleLifecycle.plan(
            hubIsOn: false,
            enabled: ["now-playing", "timers"],
            registered: registered,
            running: ["timers", "calendar"]
        )
        #expect(plan.start.isEmpty)
        #expect(plan.stop == ["calendar", "timers"])
        let idle = HubModuleLifecycle.plan(
            hubIsOn: false, enabled: ["timers"], registered: registered, running: []
        )
        #expect(idle.isEmpty)
    }

    @Test("With the hub on and nothing enabled nothing starts")
    func nothingEnabled() {
        let plan = HubModuleLifecycle.plan(hubIsOn: true, enabled: [], registered: registered, running: [])
        #expect(plan.isEmpty)
    }

    @Test("An enabled module without a registration is ignored")
    func unregisteredIgnored() {
        let plan = HubModuleLifecycle.plan(
            hubIsOn: true, enabled: ["clipboard", "widgets"], registered: registered, running: []
        )
        #expect(plan.isEmpty)
    }

    @Test("A registered module that is off does not start, and stops when it runs")
    func disabledStops() {
        let plan = HubModuleLifecycle.plan(
            hubIsOn: true, enabled: ["calendar"], registered: registered, running: ["timers", "calendar"]
        )
        #expect(plan.start.isEmpty)
        #expect(plan.stop == ["timers"])
        let idle = HubModuleLifecycle.plan(hubIsOn: true, enabled: [], registered: registered, running: [])
        #expect(idle.start.isEmpty)
    }

    @Test("A module that already runs changes nothing")
    func alreadyRunning() {
        let plan = HubModuleLifecycle.plan(
            hubIsOn: true, enabled: ["calendar", "timers"], registered: registered, running: ["calendar", "timers"]
        )
        #expect(plan.isEmpty)
        // A second plan with the same input is empty too.
        let again = HubModuleLifecycle.plan(
            hubIsOn: true, enabled: ["calendar", "timers"], registered: registered, running: ["calendar", "timers"]
        )
        #expect(again == plan)
    }

    @Test("Modules start in registration order whatever the set order, and stop alphabetically")
    func orders() {
        let plan = HubModuleLifecycle.plan(
            hubIsOn: true,
            enabled: ["timers", "now-playing", "calendar"],
            registered: registered,
            running: []
        )
        #expect(plan.start == ["now-playing", "calendar", "timers"])
        let stopping = HubModuleLifecycle.plan(
            hubIsOn: true, enabled: [], registered: registered, running: ["timers", "calendar", "now-playing"]
        )
        #expect(stopping.stop == ["calendar", "now-playing", "timers"])
    }

    @Test("A duplicate registration starts once")
    func duplicateRegistration() {
        let plan = HubModuleLifecycle.plan(
            hubIsOn: true,
            enabled: ["calendar"],
            registered: ["calendar", "timers", "calendar"],
            running: []
        )
        #expect(plan.start == ["calendar"])
    }

    @Test("A running module that is no longer registered stops")
    func removedRegistrationStops() {
        let plan = HubModuleLifecycle.plan(
            hubIsOn: true, enabled: ["gone", "timers"], registered: ["timers"], running: ["gone", "timers"]
        )
        #expect(plan.start.isEmpty)
        #expect(plan.stop == ["gone"])
    }

    @Test("The registered order follows the catalog and lists each module once")
    func registeredOrder() {
        let order = HubModuleLifecycle.registeredOrder(
            catalogOrder: ["widgets", "now-playing", "calendar", "timers", "calendar"],
            registrations: ["timers", "unknown", "now-playing", "timers"]
        )
        #expect(order == ["now-playing", "timers"])
        let empty = HubModuleLifecycle.registeredOrder(catalogOrder: ["a"], registrations: [])
        #expect(empty.isEmpty)
        let none = HubModuleLifecycle.registeredOrder(catalogOrder: [], registrations: ["a"])
        #expect(none.isEmpty)
    }
}
