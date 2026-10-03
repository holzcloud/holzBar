//
//  ItemHintsPanel.swift
//  holzBar
//

import AppKit
import SwiftUI

// MARK: - ItemHintsPanel

/// Shows every menu bar item with a letter under the menu bar; typing the letter opens the
/// item's menu (item hints, THAW-14).
///
/// The panel reads keys only while it is key, and only the keys it needs (letters, Delete
/// and Escape); nothing is logged. It shows the images holzBar already has, or the item's
/// name, so it needs no Screen Recording.
final class ItemHintsPanel: NSPanel {
    /// The shared app state.
    private weak var appState: AppState?

    /// The hints on display and what was typed.
    private let model = ItemHintsModel()

    /// Whether the panel is closing, so losing key status meanwhile does not close it again.
    private var isClosing = false

    /// The panel takes keys without activating holzBar.
    override var canBecomeKey: Bool { true }

    /// Creates the panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.title = String(localized: "Open an Item by Letter")
        self.isFloatingPanel = true
        self.animationBehavior = .none
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    /// Shows or closes the hints.
    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    /// Shows the hints under the menu bar of the display with the pointer.
    func show() {
        guard
            let appState,
            let screen = NSScreen.screenWithMouse ?? NSScreen.main
        else {
            return
        }
        let cache = appState.itemManager.itemCache
        let items = MenuBarSection.Name.allCases.flatMap { name in
            cache[name].filter { !$0.isControlItem }.map { (item: $0, section: name) }
        }
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        let hints = ItemHints.letters(count: items.count)
        model.entries = zip(items, hints).enumerated().map { index, pair in
            ItemHintsModel.Entry(
                item: pair.0.item,
                hint: pair.1,
                startsSection: index > 0 && items[index - 1].section != pair.0.section
            )
        }
        model.typed = ""
        model.maxWidth = screen.visibleFrame.width - 40

        let hostingView = NSHostingView(
            rootView: ItemHintsView(model: model, imageCache: appState.imageCache) { [weak self] entry in
                self?.open(entry)
            }
        )
        let size = hostingView.fittingSize
        contentView = hostingView
        let menuBarHeight = screen.getMenuBarHeight() ?? 0
        setFrame(
            CGRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - menuBarHeight - size.height - 4,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        makeKeyAndOrderFront(nil)
    }

    /// Handles the keys while the panel is key.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }
        switch KeyCode(rawValue: Int(event.keyCode)) {
        case .escape:
            close()
        case .delete:
            if !model.typed.isEmpty {
                model.typed.removeLast()
            }
        default:
            guard
                let characters = event.charactersIgnoringModifiers?.lowercased(),
                characters.count == 1,
                let character = characters.first,
                character.isLetter
            else {
                NSSound.beep()
                return
            }
            let typed = model.typed + String(character)
            switch ItemHints.match(typed: typed, hints: model.entries.map(\.hint)) {
            case .item(let index):
                open(model.entries[index])
            case .pending:
                model.typed = typed
            case .none:
                NSSound.beep()
            }
        }
    }

    /// A click elsewhere closes the hints.
    override func resignKey() {
        super.resignKey()
        if isVisible, !isClosing {
            close()
        }
    }

    /// Closes the hints and opens the item's menu.
    private func open(_ entry: ItemHintsModel.Entry) {
        close()
        guard let itemManager = appState?.itemManager else {
            return
        }
        let item = entry.item
        Task {
            // Lets the panel go away before the click.
            try? await Task.sleep(for: .milliseconds(25))
            await itemManager.openItem(item, mouseButton: .left, shelfDisplayID: nil)
        }
    }

    override func close() {
        guard !isClosing else {
            return
        }
        isClosing = true
        defer {
            isClosing = false
        }
        super.close()
        contentView = nil
        model.entries = []
        model.typed = ""
    }
}

// MARK: - ItemHintsModel

/// The hints the panel shows.
@MainActor
@Observable
private final class ItemHintsModel {
    /// One item with its letters.
    struct Entry: Identifiable {
        let item: MenuBarItem
        let hint: String
        /// Whether a separator comes before the item, because its section starts here.
        let startsSection: Bool

        var id: String { hint }
    }

    /// The items with their hints, in bar order: visible, hidden, always hidden.
    var entries = [Entry]()

    /// The letters typed so far.
    var typed = ""

    /// The widest the hints may be.
    var maxWidth: CGFloat = 800
}

// MARK: - ItemHintsView

/// The hints, in rows as wide as the display allows.
private struct ItemHintsView: View {
    var model: ItemHintsModel
    var imageCache: MenuBarItemImageCache
    let open: (ItemHintsModel.Entry) -> Void

    /// The width of one hint.
    private let cellWidth: CGFloat = 64

    /// The hints split into rows.
    private var rows: [[ItemHintsModel.Entry]] {
        let perRow = max(1, Int(model.maxWidth / (cellWidth + 6)))
        return stride(from: 0, to: model.entries.count, by: perRow).map { start in
            Array(model.entries[start..<min(start + perRow, model.entries.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: 6) {
                    ForEach(row) { entry in
                        if entry.startsSection {
                            Divider()
                                .frame(height: 30)
                                .accessibilityHidden(true)
                        }
                        hintButton(for: entry)
                    }
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(4)
        .fixedSize()
    }

    @ViewBuilder
    private func hintButton(for entry: ItemHintsModel.Entry) -> some View {
        let isDimmed = !model.typed.isEmpty && !entry.hint.hasPrefix(model.typed)
        Button {
            open(entry)
        } label: {
            VStack(spacing: 3) {
                Group {
                    if let image = imageCache.images[entry.item.tag]?.nsImage {
                        Image(nsImage: image)
                    } else {
                        Text(entry.item.displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: cellWidth, height: 22)
                Text(entry.hint.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.3 : 1)
        .help(entry.item.displayName)
        .accessibilityLabel("\(entry.hint.uppercased()), \(entry.item.displayName)")
    }
}
