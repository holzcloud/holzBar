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

    @Test("Drag in the Menu Bar needs its tap only while the module is on")
    func dragInTheMenuBarNeedsItsTapOnlyWhileOn() {
        #expect(!InputMonitors.needed(for: Self.defaults).contains(.menuBarDrag))
        #expect(!InputMonitors.needed(for: InputMonitors.Settings()).contains(.menuBarDrag))
        #expect(InputMonitors.needed(for: InputMonitors.Settings(dragsWithoutCommand: true)) == [.menuBarDrag])
        var settings = Self.defaults
        settings.dragsWithoutCommand = true
        #expect(InputMonitors.needed(for: settings).contains(.menuBarDrag))
    }

    @Test("A Command-drag that sets the section watches only the modifier keys until Command is held")
    func commandDragWatchesOnlyTheModifierKeys() {
        let idle = InputMonitors.needed(for: InputMonitors.Settings(setsSectionOnCommandDrag: true))
        #expect(idle == [.modifierFlags])
        let held = InputMonitors.needed(for: InputMonitors.Settings(setsSectionOnCommandDrag: true, commandHeld: true))
        #expect(held == [.modifierFlags, .mouseDown, .mouseUp])
        #expect(!held.contains(.mouseDragged))
    }

    @Test("An armed press keeps the mouse monitors after Command was released")
    func armedPressKeepsTheMouseMonitors() {
        let armed = InputMonitors.needed(
            for: InputMonitors.Settings(setsSectionOnCommandDrag: true, commandHeld: false, commandDragArmed: true)
        )
        #expect(armed == [.modifierFlags, .mouseDown, .mouseUp])
        // Once the press is handled and Command is up, they stop again.
        let done = InputMonitors.needed(for: InputMonitors.Settings(setsSectionOnCommandDrag: true))
        #expect(done == [.modifierFlags])
    }

    @Test("Command held or armed without the switch needs nothing")
    func commandWithoutTheSwitchNeedsNothing() {
        let settings = InputMonitors.Settings(commandHeld: true, commandDragArmed: true)
        #expect(InputMonitors.needed(for: settings).isEmpty)
    }

    @Test("The Command-drag flag never removes a monitor another setting needs")
    func commandDragKeepsTheOtherKinds() {
        var settings = Self.defaults
        let without = InputMonitors.needed(for: settings)
        settings.showOnHover = true
        settings.dragsWithoutCommand = true
        settings.savesUserArrangement = true
        let base = InputMonitors.needed(for: settings)
        settings.setsSectionOnCommandDrag = true
        // Command not held: only the modifier-flags monitor is added.
        #expect(InputMonitors.needed(for: settings) == base.union([.modifierFlags]))
        settings.commandHeld = true
        #expect(InputMonitors.needed(for: settings) == base.union([.modifierFlags, .mouseDown, .mouseUp]))
        #expect(InputMonitors.needed(for: settings).isSuperset(of: without))
        var defaults = Self.defaults
        defaults.setsSectionOnCommandDrag = true
        defaults.commandHeld = true
        #expect(InputMonitors.needed(for: defaults) == without.union([.modifierFlags, .mouseDown, .mouseUp]))
    }

    @Test("The default settings need no monitor")
    func defaultSettingsNeedNoMonitor() {
        #expect(InputMonitors.needed(for: InputMonitors.Settings()).isEmpty)
        #expect(!InputMonitors.Settings().setsSectionOnCommandDrag)
    }

    @Test("The space click monitor runs only where a click can change the space")
    func spaceClickMonitorRunsOnlyWhereNeeded() {
        #expect(!InputMonitors.needsSpaceClickMonitor(isFullscreenSpace: false, screenCount: 1))
        #expect(InputMonitors.needsSpaceClickMonitor(isFullscreenSpace: true, screenCount: 1))
        #expect(InputMonitors.needsSpaceClickMonitor(isFullscreenSpace: false, screenCount: 2))
    }
}
