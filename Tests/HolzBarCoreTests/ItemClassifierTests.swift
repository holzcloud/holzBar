import Testing
@testable import HolzBarCore

@Suite("ItemClassifier")
struct ItemClassifierTests {
    private func item(
        _ namespace: String,
        _ title: String,
        category: String? = nil,
        section: Int = 0
    ) -> ClassifiableItem {
        ClassifiableItem(
            key: "\(namespace):\(title)",
            namespace: namespace,
            title: title,
            applicationCategory: category,
            section: section
        )
    }

    @Test("The essentials stay visible")
    func essentials() {
        #expect(ItemClassifier.classify(item("com.apple.controlcenter", "Clock")) == .essential)
        #expect(ItemClassifier.classify(item("com.apple.controlcenter", "WiFi")) == .essential)
    }

    @Test("Control Center extras are set and forget, unknown ones stay")
    func controlCenter() {
        #expect(ItemClassifier.classify(item("com.apple.controlcenter", "Bluetooth")) == .setAndForget)
        #expect(ItemClassifier.classify(item("com.apple.controlcenter", "SomethingNew")) == .unknown)
    }

    @Test("A live value is information, whatever the application")
    func liveValues() {
        let cpu = item("com.example.monitor", "CPU 12%", category: "public.app-category.utilities")
        #expect(ItemClassifier.classify(cpu) == .information)
        #expect(ItemClassifier.proposals(for: [cpu]).isEmpty)
    }

    @Test("Categories decide for applications without better knowledge")
    func categories() {
        #expect(ItemClassifier.classify(item("com.example.tool", "Tool", category: "public.app-category.utilities")) == .setAndForget)
        #expect(ItemClassifier.classify(item("com.example.dev", "Dev", category: "public.app-category.developer-tools")) == .setAndForget)
        #expect(ItemClassifier.classify(item("com.example.chat", "Chat", category: "public.app-category.social-networking")) == .communication)
        #expect(ItemClassifier.classify(item("com.example.game", "Game", category: "public.app-category.games")) == .unknown)
        #expect(ItemClassifier.classify(item("com.example.none", "None")) == .unknown)
    }

    @Test("Known helpers are set and forget")
    func knownHelpers() {
        #expect(ItemClassifier.classify(item("com.getdropbox.dropbox", "Dropbox")) == .setAndForget)
    }

    @Test("Only visible set-and-forget items are proposed, with their reason")
    func proposals() {
        let items = [
            item("com.apple.controlcenter", "Clock"),
            item("com.apple.controlcenter", "Bluetooth"),
            item("com.apple.controlcenter", "Display", section: 1),
            item("com.getdropbox.dropbox", "Dropbox"),
            item("com.example.tool", "Tool", category: "public.app-category.utilities"),
            item("com.example.chat", "Chat", category: "public.app-category.social-networking"),
            item("com.example.other", "Other"),
        ]
        let proposals = ItemClassifier.proposals(for: items)
        #expect(proposals.map(\.item.title) == ["Bluetooth", "Dropbox", "Tool"])
        #expect(proposals.map(\.reason) == [.systemExtra, .knownHelper, .backgroundTool])
    }

    @Test("Nothing is proposed for an arrangement of essentials and unknowns")
    func nothingToPropose() {
        let items = [item("com.apple.controlcenter", "Battery"), item("com.example.other", "Other")]
        #expect(ItemClassifier.proposals(for: items).isEmpty)
    }

    @Test("An item of holzBar's own is never proposed, whatever its application's category")
    func ownItemsAreNeverProposed() {
        // A widget reads the category of holzBar itself, which is a utility (CR-01).
        let widget = ClassifiableItem(
            key: "com.holzcloud.holzBar:holzBar.Widget.6F1D2E3A-7B4C-4D5E-8F90-A1B2C3D4E5F6",
            namespace: "com.holzcloud.holzBar",
            title: "holzBar.Widget.6F1D2E3A-7B4C-4D5E-8F90-A1B2C3D4E5F6",
            applicationCategory: "public.app-category.utilities",
            section: 0,
            isOwnItem: true
        )
        #expect(ItemClassifier.classify(widget) == .unknown)
        #expect(ItemClassifier.proposals(for: [widget]).isEmpty)

        // The same facts for an application that is not holzBar's are proposed.
        var other = widget
        other.isOwnItem = false
        #expect(ItemClassifier.proposals(for: [other]).map(\.item.key) == [other.key])
    }
}
