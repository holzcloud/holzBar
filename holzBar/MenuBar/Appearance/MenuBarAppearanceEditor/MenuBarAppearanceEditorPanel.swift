//
//  MenuBarAppearanceEditorPanel.swift
//  holzBar
//

import SwiftUI

/// A panel that contains a portable version of the menu bar
/// appearance editor interface.
final class MenuBarAppearanceEditorPanel: NSPanel {
    /// The default screen to show the panel on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// The shared app state.
    private weak var appState: AppState?

    /// Observers of the app's appearance and the panel's visibility.
    private var observations = [NSKeyValueObservation]()

    /// Overridden to always be `true`.
    override var canBecomeKey: Bool { true }

    /// Creates a menu bar appearance editor panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.title = String(localized: "Menu Bar Appearance")
        self.titlebarAppearsTransparent = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureContentView(with: appState)
        configureObservers()
    }

    /// Configures the panel's content view.
    private func configureContentView(with appState: AppState) {
        let hostingView = MenuBarAppearanceEditorHostingView(appState: appState)
        setFrame(hostingView.frame, display: true)
        contentView = hostingView
    }

    /// Configures the internal observers for the panel.
    private func configureObservers() {
        // Make sure the panel takes on the app's appearance.
        appearance = NSApp.effectiveAppearance
        observations = [
            NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.appearance = NSApp.effectiveAppearance
                }
            },
            observe(\.isVisible, options: [.initial, .new]) { panel, _ in
                Task { @MainActor in
                    if panel.isVisible {
                        NSColorPanel.shared.hidesOnDeactivate = false
                    } else {
                        // A preview turned on in the panel ends with it.
                        panel.appState?.appearanceManager.previewConfiguration = nil
                        NSColorPanel.shared.hidesOnDeactivate = true
                        NSColorPanel.shared.close()
                    }
                }
            },
        ]
    }

    /// Updates the panel's position for display on the given screen.
    private func updatePosition(for screen: NSScreen) {
        let originX = screen.visibleFrame.midX - frame.width / 2
        let originY = screen.visibleFrame.maxY
        setFrameTopLeftPoint(CGPoint(x: originX, y: originY))
    }

    /// Shows the panel on the given screen.
    func show(on screen: NSScreen) {
        updatePosition(for: screen)
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - MenuBarAppearanceEditorHostingView

private final class MenuBarAppearanceEditorHostingView: NSHostingView<MenuBarAppearanceEditorContentView> {
    override var intrinsicContentSize: CGSize {
        CGSize(width: 550, height: 600)
    }

    init(appState: AppState) {
        super.init(rootView: MenuBarAppearanceEditorContentView(appState: appState))
        setFrameSize(intrinsicContentSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: MenuBarAppearanceEditorContentView) {
        fatalError("init(rootView:) has not been implemented")
    }
}

// MARK: - MenuBarAppearanceEditorContentView

private struct MenuBarAppearanceEditorContentView: View {
    var appState: AppState

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        content
            .background {
                HolzBarGround(showsGlows: false)
                    .ignoresSafeArea()
            }
            .environment(appState)
    }

    @ViewBuilder
    private var content: some View {
        if #available(macOS 26.0, *) {
            scrollContent
                .scrollEdgeEffectStyle(.hard, for: .vertical)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    footer
                }
        } else {
            VStack(spacing: 0) {
                scrollContent
                footer
            }
        }
    }

    private var scrollContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: HolzBarTheme.SettingsKit.groupGap) {
                MenuBarAppearanceEditor(
                    appearanceManager: appState.appearanceManager,
                    location: .panel
                )
            }
            .padding(.horizontal, HolzBarTheme.SettingsKit.paneMarginHorizontal)
            .padding(.top, HolzBarTheme.SettingsKit.paneMarginTop)
            .padding(.bottom, HolzBarTheme.SettingsKit.paneMarginBottom)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                dismissWindow()
            }
        }
        .buttonBorderShape(.capsule)
        .padding(HolzBarTheme.Spacing.sm)
    }
}
