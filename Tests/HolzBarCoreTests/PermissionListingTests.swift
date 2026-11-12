import Testing
@testable import HolzBarCore

@Suite("PermissionListing")
struct PermissionListingTests {
    @Test("The candidates are the four permissions with an object, in today's order")
    func candidates() {
        #expect(PermissionListing.candidates == [.accessibility, .screenRecording, .calendar, .bluetooth])
    }

    @Test("Switched-on modules name the permissions they need")
    func needsOfEnabledModules() {
        #expect(PermissionListing.needs(ofEnabled: ["calendar", "accessory-alerts"], in: ModuleCatalog.all) == [.calendar, .bluetooth])
        #expect(PermissionListing.needs(ofEnabled: ["notifications"], in: ModuleCatalog.all) == [.accessibility])
        #expect(PermissionListing.needs(ofEnabled: ["timers", "no-such-module"], in: ModuleCatalog.all).isEmpty)
        #expect(PermissionListing.needs(ofEnabled: [], in: ModuleCatalog.all).isEmpty)
    }

    @Test("Only candidates are listed, in candidate order")
    func listedKeepsCandidateOrder() {
        #expect(PermissionListing.listed(needed: [.microphone], granted: [], alwaysListed: []).isEmpty)
        #expect(
            PermissionListing.listed(needed: [.bluetooth, .calendar], granted: [.screenRecording], alwaysListed: [])
                == [.screenRecording, .calendar, .bluetooth]
        )
        #expect(
            PermissionListing.listed(needed: [.calendar], granted: [.bluetooth], alwaysListed: [.accessibility])
                == [.accessibility, .calendar, .bluetooth]
        )
    }

    @Test("A granted permission is listed so that it can be revoked; a needed one so that it can be granted (D-57)")
    func grantedAndNeeded() {
        #expect(PermissionListing.listed(needed: [], granted: [.bluetooth], alwaysListed: []) == [.bluetooth])
        #expect(PermissionListing.listed(needed: [.calendar], granted: [], alwaysListed: []) == [.calendar])
    }

    @Test("Accessibility is always listed (D-65, D1)")
    func accessibilityAlwaysListed() {
        #expect(PermissionListing.alwaysListed == [.accessibility])
        #expect(PermissionListing.listed(needed: [], granted: []) == [.accessibility])
    }

    @Test("Every module permission and every always-listed one has an object")
    func everyListablePermissionIsACandidate() {
        let candidates = Set(PermissionListing.candidates)
        for permission in ModuleCatalog.all.compactMap(\.permission) {
            #expect(candidates.contains(permission), "\(permission) has no Permission object")
        }
        #expect(PermissionListing.alwaysListed.isSubset(of: candidates))
    }
}
