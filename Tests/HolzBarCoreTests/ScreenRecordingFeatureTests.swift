import Testing
@testable import HolzBarCore

@Suite("ScreenRecordingFeature")
struct ScreenRecordingFeatureTests {
    @Test("Every feature that captures the screen says why")
    func everyFeatureSaysWhy() {
        for feature in ScreenRecordingFeature.allCases {
            #expect(!feature.reason.isEmpty)
            #expect(feature.reason.hasSuffix("."))
            #expect(!feature.name.isEmpty)
        }
    }

    @Test("The features are the Shelf, the search, the layout pane and menu bar shapes")
    func theFeatures() {
        #expect(ScreenRecordingFeature.allCases == [.shelf, .search, .layoutPane, .menuBarShape])
    }

    @Test("The permissions window summary names every feature")
    func summaryNamesEveryFeature() {
        let summary = ScreenRecordingFeature.summary
        #expect(summary.hasSuffix("."))
        for feature in ScreenRecordingFeature.allCases {
            #expect(summary.contains(feature.name), "The summary does not name \(feature.name)")
        }
    }
}
