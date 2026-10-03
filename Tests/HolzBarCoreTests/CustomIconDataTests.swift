import Testing
@testable import HolzBarCore

@Suite("CustomIconData")
struct CustomIconDataTests {
    @Test("Bitmap formats are decoded")
    func bitmapFormatsAreDecoded() {
        for type in ["public.png", "public.jpeg", "public.tiff", "public.heic", "com.compuserve.gif"] {
            #expect(CustomIconData.accepts(typeIdentifier: type, byteCount: 1000))
        }
    }

    @Test("Documents and vector formats are not decoded")
    func documentsAreNotDecoded() {
        for type in ["com.adobe.pdf", "com.adobe.encapsulated-postscript", "public.svg-image", "com.apple.pict", "public.data"] {
            #expect(!CustomIconData.accepts(typeIdentifier: type, byteCount: 1000))
        }
        #expect(!CustomIconData.accepts(typeIdentifier: nil, byteCount: 1000))
    }

    @Test("Empty or very large data is not decoded")
    func sizeLimits() {
        #expect(!CustomIconData.accepts(typeIdentifier: "public.png", byteCount: 0))
        #expect(CustomIconData.accepts(typeIdentifier: "public.png", byteCount: CustomIconData.maximumByteCount))
        #expect(!CustomIconData.accepts(typeIdentifier: "public.png", byteCount: CustomIconData.maximumByteCount + 1))
    }

    @Test("Pixel sizes are limited")
    func pixelLimits() {
        #expect(CustomIconData.accepts(pixelWidth: 64, pixelHeight: 34))
        #expect(CustomIconData.accepts(pixelWidth: CustomIconData.maximumPixelSize, pixelHeight: 1))
        #expect(!CustomIconData.accepts(pixelWidth: 0, pixelHeight: 34))
        #expect(!CustomIconData.accepts(pixelWidth: 64, pixelHeight: CustomIconData.maximumPixelSize + 1))
        #expect(!CustomIconData.accepts(pixelWidth: 100_000, pixelHeight: 100_000))
    }

    @Test("A chosen icon is stored small")
    func storedSizeIsSmall() {
        #expect(CustomIconData.storedPixelSize <= CustomIconData.maximumPixelSize)
        #expect(CustomIconData.allowedTypeIdentifiers.contains("public.png"))
    }
}
