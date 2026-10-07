import Testing
@testable import HolzBarCore

/// The camera and microphone indicator and the FaceTime item never hide, whichever app
/// they are attributed to.
@Suite("CaptureIndicatorItems")
struct CaptureIndicatorItemsTests {
    @Test("The capture indicator and the FaceTime item are indicators")
    func indicators() {
        #expect(CaptureIndicatorItems.isIndicator(title: "AudioVideoModule"))
        #expect(CaptureIndicatorItems.isIndicator(title: "FaceTime"))
    }

    @Test("Item-0 is not, because every app's first status item has that title")
    func defaultTitleIsNotAnIndicator() {
        #expect(!CaptureIndicatorItems.isIndicator(title: "Item-0"))
    }

    @Test("Titles are compared exactly")
    func exactTitles() {
        #expect(!CaptureIndicatorItems.isIndicator(title: "audiovideomodule"))
        #expect(!CaptureIndicatorItems.isIndicator(title: "AudioVideoModule-1"))
        #expect(!CaptureIndicatorItems.isIndicator(title: "Clock"))
        #expect(!CaptureIndicatorItems.isIndicator(title: ""))
    }
}
