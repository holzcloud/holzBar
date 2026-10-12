import Testing
@testable import HolzBarCore

@Suite("OwnBundle")
struct OwnBundleTests {
    private let own = "com.holzcloud.holzBar"
    private let autosave = "holzBar.Widget.6F1D2E3A-7B4C-4D5E-8F90-A1B2C3D4E5F6"

    @Test("holzBar's bundle matches whatever its case, a widget's autosave name does not")
    func matching() {
        #expect(OwnBundle.matches("com.holzcloud.holzBar", bundleIdentifier: own))
        #expect(OwnBundle.matches("COM.HOLZCLOUD.HOLZBAR", bundleIdentifier: own))
        #expect(!OwnBundle.matches(autosave, bundleIdentifier: own))
        #expect(!OwnBundle.matches("com.apple.Safari", bundleIdentifier: own))
        // The identifier is the caller's, not a copy kept here.
        #expect(OwnBundle.matches("com.example.fork", bundleIdentifier: "com.example.fork"))
        #expect(!OwnBundle.matches("com.holzcloud.holzBar", bundleIdentifier: "com.example.fork"))
    }

    @Test("A widget's item key stands for its autosave name, never for holzBar's bundle (CR-01, CR-02)")
    func widgetKey() {
        #expect(OwnBundle.layoutKey(forItemKey: "\(own):\(autosave)", bundleIdentifier: own) == autosave)
        #expect(OwnBundle.widgetAutosaveName(inItemKey: "\(own):\(autosave)", bundleIdentifier: own) == autosave)
        // A second item of the same title carries a number.
        #expect(OwnBundle.layoutKey(forItemKey: "\(own):\(autosave):2", bundleIdentifier: own) == autosave)
    }

    @Test("An application's key is its namespace; holzBar's own items and system items have none")
    func applicationKey() {
        #expect(OwnBundle.layoutKey(forItemKey: "com.getdropbox.dropbox:Dropbox", bundleIdentifier: own) == "com.getdropbox.dropbox")
        // holzBar's own items that are no widgets are never an application key.
        #expect(OwnBundle.layoutKey(forItemKey: "\(own):Item-0", bundleIdentifier: own) == nil)
        #expect(OwnBundle.layoutKey(forItemKey: "\(own):", bundleIdentifier: own) == nil)
        #expect(OwnBundle.layoutKey(forItemKey: own, bundleIdentifier: own) == nil)
        // A namespace that is no bundle identifier, such as a system item's UUID.
        #expect(OwnBundle.layoutKey(forItemKey: "6F1D2E3A:Clock", bundleIdentifier: own) == nil)
        #expect(OwnBundle.layoutKey(forItemKey: "", bundleIdentifier: own) == nil)
    }

    @Test("Another application's item that is titled like a widget is not a widget")
    func foreignTitle() {
        #expect(OwnBundle.widgetAutosaveName(inItemKey: "com.example.app:\(autosave)", bundleIdentifier: own) == nil)
        // A malformed identifier is no autosave name.
        #expect(OwnBundle.widgetAutosaveName(inItemKey: "\(own):holzBar.Widget.nope", bundleIdentifier: own) == nil)
    }

    @Test("The item's own layout key is used, unless it is holzBar's bundle (CR-02)")
    func itemLayoutKey() {
        let widgetKey = "\(own):\(autosave)"
        // The item says better than the key's namespace which application owns it.
        #expect(OwnBundle.layoutKey(forItemKey: "com.apple.controlcenter:Item-0", itemLayoutKey: "com.example.real", bundleIdentifier: own) == "com.example.real")
        // A widget item's layout key is its autosave name.
        #expect(OwnBundle.layoutKey(forItemKey: widgetKey, itemLayoutKey: autosave, bundleIdentifier: own) == autosave)
        // An item that reports holzBar's bundle never gives an application key, whatever its
        // identity key says.
        #expect(OwnBundle.layoutKey(forItemKey: "com.example.app:Thing", itemLayoutKey: own, bundleIdentifier: own) == nil)
        // Without the item, the key itself decides: the widget by its autosave name.
        #expect(OwnBundle.layoutKey(forItemKey: widgetKey, itemLayoutKey: nil, bundleIdentifier: own) == autosave)
    }
}
