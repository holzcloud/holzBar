//
//  ScreenCorners.swift
//  Ice
//

import AppKit
import Combine

/// Draws rounded corners on every display.
///
/// Each corner is a small window that ignores the mouse and sits above
/// everything, fullscreen apps included, filled black outside a quarter circle.
@MainActor
final class ScreenCorners {
    /// A corner of a screen.
    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private var panels = [NSPanel]()
    private var cancellables = Set<AnyCancellable>()

    /// Starts following the given appearance manager's configuration.
    func performSetup(with appearanceManager: MenuBarAppearanceManager) {
        appearanceManager.$configuration
            .map { ($0.roundsScreenCorners, $0.screenCornerRadius) }
            .removeDuplicates { $0 == $1 }
            .combineLatest(
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .replace(with: ())
                    .prepend(())
            )
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] settings, _ in
                self?.update(isEnabled: settings.0, radius: settings.1)
            }
            .store(in: &cancellables)
    }

    private func update(isEnabled: Bool, radius: Double) {
        for panel in panels {
            panel.close()
        }
        panels.removeAll()
        guard isEnabled else {
            return
        }
        for screen in NSScreen.screens {
            for corner in Corner.allCases {
                panels.append(makePanel(for: corner, on: screen, radius: radius))
            }
        }
    }

    private func makePanel(for corner: Corner, on screen: NSScreen, radius: Double) -> NSPanel {
        let frame = screen.frame
        let size = CGSize(width: radius, height: radius)
        let origin = switch corner {
        case .topLeft: CGPoint(x: frame.minX, y: frame.maxY - radius)
        case .topRight: CGPoint(x: frame.maxX - radius, y: frame.maxY - radius)
        case .bottomLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .bottomRight: CGPoint(x: frame.maxX - radius, y: frame.minY)
        }
        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = CornerView(corner: corner)
        panel.orderFrontRegardless()
        return panel
    }

    /// Fills its bounds black outside a quarter circle that touches the corner.
    private final class CornerView: NSView {
        private let corner: Corner

        init(corner: Corner) {
            self.corner = corner
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            let radius = bounds.width
            // The centre of the circle lies at the corner opposite the screen's corner.
            let center = switch corner {
            case .topLeft: CGPoint(x: radius, y: 0)
            case .topRight: CGPoint(x: 0, y: 0)
            case .bottomLeft: CGPoint(x: radius, y: radius)
            case .bottomRight: CGPoint(x: 0, y: radius)
            }
            let path = NSBezierPath(rect: bounds)
            path.appendOval(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
        }
    }
}
