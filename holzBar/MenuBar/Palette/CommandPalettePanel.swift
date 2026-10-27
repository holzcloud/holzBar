//
//  CommandPalettePanel.swift
//  holzBar
//

import OSLog
import SwiftUI

/// A Spotlight-like panel where typing finds a holzBar action, a profile, a rule or a menu bar
/// item and Return runs it.
///
/// The panel is holzBar's own window and needs no permission. It keeps no history: what the
/// user ran is not stored, and item names are shown but never logged.
final class CommandPalettePanel: NSPanel {
    private weak var appState: AppState?
    private let model = CommandPaletteModel()
    private var observerTasks = [Task<Void, Never>]()

    private lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
        if let self, event.window !== self {
            close()
        }
        return event
    }

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        setAccessibilityLabel(String(localized: "Command Palette"))
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        appearance = NSApp.effectiveAppearance
        // Close when the space or the screens change, as the search panel does.
        observerTasks = [
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                    self?.close()
                }
            },
            Task { [weak self] in
                let center = NotificationCenter.default
                for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                    self?.close()
                }
            },
        ]
    }

    /// Shows the palette on the screen with the mouse.
    func show() {
        guard let appState else {
            return
        }
        // The palette lists the items of the hidden sections, so it asks as showing them does.
        if appState.hiddenItemsLock.requiresAuthentication {
            appState.hiddenItemsLock.authenticate { [weak self] in
                self?.show()
            }
            return
        }
        guard let screen = NSScreen.screenWithMouse ?? NSScreen.main else {
            Logger.default.error("Missing screen for the command palette")
            return
        }
        model.reset(commands: CommandPaletteCommands.make(appState: appState))
        let hostingView = CommandPaletteHostingView(model: model) { [weak self] command in
            self?.run(command)
        }
        hostingView.setFrameSize(hostingView.intrinsicContentSize)
        setFrame(hostingView.frame, display: true)
        contentView = hostingView
        let topLeft = CGPoint(
            x: screen.frame.midX - frame.width / 2,
            y: screen.frame.midY + (frame.height / 2) + (screen.frame.height / 8)
        )
        cascadeTopLeft(from: topLeft)
        makeKeyAndOrderFront(nil)
        mouseDownMonitor.start()
    }

    func toggle() {
        if isVisible { close() } else { show() }
    }

    override func close() {
        super.close()
        contentView = nil
        mouseDownMonitor.stop()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// Closes the panel, then runs the command on the next turn, so the window that had the
    /// focus before gets it back first.
    private func run(_ command: PaletteCommand) {
        close()
        guard let appState else {
            return
        }
        Task { @MainActor in
            CommandPaletteCommands.perform(command, appState: appState)
        }
    }
}

private final class CommandPaletteHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(model: CommandPaletteModel, run: @escaping (PaletteCommand) -> Void) {
        super.init(rootView: CommandPaletteView(run: run).environment(model).erasedToAnyView())
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Model

@MainActor
@Observable
final class CommandPaletteModel {
    var query = "" {
        didSet {
            results = ActionCatalog.results(for: query, in: commands)
            selection = results.first?.id
        }
    }

    private(set) var results = [PaletteCommand]()
    var selection: PaletteCommand.ID?

    @ObservationIgnored private var commands = [PaletteCommand]()

    func reset(commands: [PaletteCommand]) {
        self.commands = commands
        query = ""
        results = commands
        selection = commands.first?.id
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            return
        }
        let current = results.firstIndex { $0.id == selection } ?? 0
        selection = results[min(max(current + offset, 0), results.count - 1)].id
    }

    var selectedCommand: PaletteCommand? {
        results.first { $0.id == selection }
    }
}

// MARK: - View

private struct CommandPaletteView: View {
    @Environment(CommandPaletteModel.self) private var model
    @FocusState private var fieldIsFocused: Bool

    let run: (PaletteCommand) -> Void

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TextField("Type a command", text: $model.query)
                .textFieldStyle(.plain)
                .font(HolzBarTheme.Typography.searchField)
                .padding(15)
                .focused($fieldIsFocused)
                .onSubmit {
                    if let command = model.selectedCommand {
                        run(command)
                    }
                }
                .accessibilityLabel(Text("Command Palette"))
                .accessibilityValue(Text("\(model.results.count) results"))
            Divider()
            resultList
        }
        .background {
            VisualEffectView(material: .sheet, blendingMode: .behindWindow)
                .opacity(0.5)
        }
        .frame(width: 600, height: 400)
        .fixedSize()
        .task {
            fieldIsFocused = true
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if model.results.isEmpty {
            Text("No matching command")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.results) { command in
                            row(for: command)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selection) {
                    if let selection = model.selection {
                        proxy.scrollTo(selection)
                    }
                }
            }
        }
    }

    private func row(for command: PaletteCommand) -> some View {
        let isSelected = command.id == model.selection
        return Button {
            run(command)
        } label: {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Image(systemName: CommandPaletteCommands.symbol(for: command))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .accessibilityHidden(true)
                Text(verbatim: command.title)
                    .lineLimit(1)
                Spacer()
                CommandPaletteCommands.kindLabel(for: command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.25) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(command.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
