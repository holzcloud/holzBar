import Testing
@testable import HolzBarCore

@Suite("UngovernedItemOwners")
struct UngovernedItemOwnersTests {
    @Test("explorer.exe is an ungoverned owner, whatever its case")
    func explorerIsListed() {
        #expect(UngovernedItemOwners.contains(namespace: "explorer.exe"))
        #expect(UngovernedItemOwners.contains(namespace: "EXPLORER.EXE"))
        #expect(UngovernedItemOwners.contains(namespace: "Explorer.exe"))
    }

    @Test("Other owners are governed")
    func othersAreNot() {
        #expect(!UngovernedItemOwners.contains(namespace: "explorer"))
        #expect(!UngovernedItemOwners.contains(namespace: "sideloadly-daemon"))
        #expect(!UngovernedItemOwners.contains(namespace: "com.apple.controlcenter"))
        #expect(!UngovernedItemOwners.contains(namespace: ""))
    }

    @Test("Only explorer.exe is listed")
    func onlyExplorerIsListed() {
        #expect(UngovernedItemOwners.processNames == ["explorer.exe"])
    }

    @Test("An automatic pass leaves an ungoverned item alone, the user's arrangement moves it")
    func reconcilingRule() {
        #expect(!UngovernedItemOwners.allowsReconciling(isUngoverned: true, arrangedByUser: false))
        #expect(UngovernedItemOwners.allowsReconciling(isUngoverned: true, arrangedByUser: true))
        #expect(UngovernedItemOwners.allowsReconciling(isUngoverned: false, arrangedByUser: false))
        #expect(UngovernedItemOwners.allowsReconciling(isUngoverned: false, arrangedByUser: true))
    }
}
