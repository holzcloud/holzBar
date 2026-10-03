import Testing
@testable import HolzBarCore

@Suite("InputMonitors")
struct InputMonitorsTests {
    /// holzBar's default settings: show on click and scroll, smart rehide, the secondary
    /// context menu and showing all sections while dragging on; show on hover off.
    private static let defaults = InputMonitors.Settings(
        showOnClick: true,
        showOnHover: false,
        showOnScroll: true,
        autoRehide: true,
        rehidesSmartly: true,
        secondaryContextMenu: true,
        usesShelf: false,
        showAllSectionsOnUserDrag: true,
        hasCustomAppearance: false
    )

    @Test("Default settings need no mouse-moved tap")
    func defaultSettingsNeedNoMouseMovedTap() {
        let needed = InputMonitors.needed(for: Self.defaults)
        #expect(!needed.contains(.mouseMoved))
    }

    @Test("Show on hover needs the mouse-moved tap")
    func showOnHoverNeedsTheMouseMovedTap() {
        var settings = Self.defaults
        settings.showOnHover = true
        let needed = InputMonitors.needed(for: settings)
        #expect(needed.contains(.mouseMoved))
    }

    @Test("Show on scroll alone needs the scroll monitor")
    func showOnScrollAloneNeedsTheScrollMonitor() {
        let settings = InputMonitors.Settings(showOnScroll: true)
        let needed = InputMonitors.needed(for: settings)
        #expect(needed == [.scrollWheel])
        #expect(!needed.contains(.mouseMoved))
    }

    @Test("Mouse-down is not needed when no click feature is on")
    func mouseDownIsNotNeededWithoutClickFeatures() {
        var settings = Self.defaults
        settings.showOnClick = false
        settings.rehidesSmartly = false
        settings.secondaryContextMenu = false
        settings.showOnHover = false
        let needed = InputMonitors.needed(for: settings)
        #expect(!needed.contains(.mouseDown))

        // Smart rehide alone needs it again; a timed rehide does not.
        settings.rehidesSmartly = true
        let smart = InputMonitors.needed(for: settings)
        #expect(smart.contains(.mouseDown))
        settings.autoRehide = false
        let off = InputMonitors.needed(for: settings)
        #expect(!off.contains(.mouseDown))

        // Show on hover without the Shelf needs it (a click pauses hovering).
        settings.showOnHover = true
        let hover = InputMonitors.needed(for: settings)
        #expect(hover.contains(.mouseDown))
        settings.usesShelf = true
        let hoverWithShelf = InputMonitors.needed(for: settings)
        #expect(!hoverWithShelf.contains(.mouseDown))
    }

    @Test("Drag monitors follow the drag features")
    func dragMonitorsFollowTheDragFeatures() {
        var settings = Self.defaults
        settings.showAllSectionsOnUserDrag = false
        settings.hasCustomAppearance = false
        let none = InputMonitors.needed(for: settings)
        #expect(!none.contains(.mouseDragged))
        #expect(!none.contains(.mouseUp))

        settings.showAllSectionsOnUserDrag = true
        let onDrag = InputMonitors.needed(for: settings)
        #expect(onDrag.isSuperset(of: [.mouseDragged, .mouseUp]))

        settings.showAllSectionsOnUserDrag = false
        settings.hasCustomAppearance = true
        let appearance = InputMonitors.needed(for: settings)
        #expect(appearance.isSuperset(of: [.mouseDragged, .mouseUp]))
    }

    @Test("Saving the user's arrangement needs only the mouse-up monitor")
    func savingTheArrangementNeedsOnlyMouseUp() {
        var settings = Self.defaults
        settings.showAllSectionsOnUserDrag = false
        settings.hasCustomAppearance = false
        settings.savesUserArrangement = true
        let kinds = InputMonitors.needed(for: settings)
        #expect(kinds.contains(.mouseUp))
        #expect(!kinds.contains(.mouseDragged))
    }

    @Test("The space click monitor runs only where a click can change the space")
    func spaceClickMonitorRunsOnlyWhereNeeded() {
        #expect(!InputMonitors.needsSpaceClickMonitor(isFullscreenSpace: false, screenCount: 1))
        #expect(InputMonitors.needsSpaceClickMonitor(isFullscreenSpace: true, screenCount: 1))
        #expect(InputMonitors.needsSpaceClickMonitor(isFullscreenSpace: false, screenCount: 2))
    }
}
