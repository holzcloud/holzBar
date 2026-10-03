import Testing
@testable import HolzBarCore

@Suite("MenuBarBackendKind")
struct MenuBarBackendKindTests {
    @Test("macOS 14 and 15 use the window list")
    func windowList() {
        #expect(MenuBarBackendKind(majorVersion: 14) == .windowList)
        #expect(MenuBarBackendKind(majorVersion: 15) == .windowList)
    }

    @Test("macOS 26 uses the item service")
    func service26() {
        #expect(MenuBarBackendKind(majorVersion: 26) == .service26)
    }

    @Test("macOS 27 and later use Accessibility")
    func accessibility27() {
        #expect(MenuBarBackendKind(majorVersion: 27) == .accessibility27)
        #expect(MenuBarBackendKind(majorVersion: 28) == .accessibility27)
    }

    @Test("The running macOS has a backend")
    func current() {
        let kind = MenuBarBackendKind.current
        #expect([.windowList, .service26, .accessibility27].contains(kind))
    }
}
