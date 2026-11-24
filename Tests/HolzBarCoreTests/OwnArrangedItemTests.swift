import Foundation
import Testing
@testable import HolzBarCore

@Suite("OwnArrangedItem")
struct OwnArrangedItemTests {
    private let id = UUID()

    @Test("A widget's, a Dock badge item's and a Dock badge group's autosave name are holzBar's own arranged items")
    func recognisesOwnKinds() {
        #expect(OwnArrangedItem.isAutosaveName("holzBar.Widget.\(id.uuidString)"))
        #expect(OwnArrangedItem.isAutosaveName(DockBadgeItemName.app("com.apple.MobileSMS")))
        #expect(OwnArrangedItem.isAutosaveName("holzBar.DockBadge.App.com.tinyspeck.slackmacgap"))
        #expect(OwnArrangedItem.isAutosaveName(DockBadgeItemName.group(id)))
    }

    @Test("Every other name of holzBar's and every foreign name is refused")
    func refusesOthers() {
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.Replacement.\(id.uuidString)"))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.StandIn.0F3A9C"))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.Spacer.1"))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.Group.\(id.uuidString)"))
        #expect(!OwnArrangedItem.isAutosaveName("com.apple.Safari"))
        #expect(!OwnArrangedItem.isAutosaveName("com.holzcloud.holzBar"))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.Widget."))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.DockBadge.App."))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.DockBadge.App.not a bundle id"))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.DockBadge."))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.DockBadge.Group."))
        #expect(!OwnArrangedItem.isAutosaveName("holzBar.DockBadge.Group.not-a-uuid"))
        #expect(!OwnArrangedItem.isAutosaveName(""))
    }
}
