//
//  MenuBarSearchModel.swift
//  holzBar
//

import Cocoa
import Observation

@MainActor
@Observable
final class MenuBarSearchModel {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag)
    }

    var searchText = ""
    var displayedItems = [SectionedListItem<ItemID>]()
    var selection: ItemID?
    private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// Observers of the panel's screen and visibility.
    @ObservationIgnored private var observations = [NSKeyValueObservation]()

    func performSetup(with panel: MenuBarSearchPanel) {
        // The colour follows the panel's screen while the panel is visible.
        let update: @Sendable (MenuBarSearchPanel) -> Void = { [weak self] panel in
            Task { @MainActor in
                guard panel.isVisible, let screen = panel.screen else {
                    return
                }
                self?.updateAverageColorInfo(for: screen)
            }
        }
        observations = [
            panel.observe(\.screen, options: [.initial, .new]) { panel, _ in
                update(panel)
            },
            panel.observe(\.isVisible, options: [.new]) { panel, _ in
                update(panel)
            },
        ]
    }

    private func updateAverageColorInfo(for screen: NSScreen) {
        // Nothing captures the screen before Screen Recording is granted.
        guard ScreenCapture.cachedCheckPermissions() else {
            return
        }

        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        guard
            let image = ScreenCapture.captureWindows(
                with: [menuBarWindow.windowID, wallpaperWindow.windowID],
                screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
                option: .nominalResolution
            ),
            let color = image.averageColor(option: .ignoreAlpha)
        else {
            return
        }

        let info = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)

        if averageColorInfo != info {
            averageColorInfo = info
        }
    }
}
