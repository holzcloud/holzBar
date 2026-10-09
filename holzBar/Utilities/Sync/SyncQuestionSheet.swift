//
//  SyncQuestionSheet.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The question sheet of the sync: an `NSAlert` shown as a sheet on the Settings window, with the rows in an `NSHostingView`
/// accessory (28-UI-SPEC "The conflict sheet").
///
/// The sheet decides nothing: the engine's question says what to show, and the pressed button and the pop-up picks go back as
/// the engine's answer. It never opens by itself; the host opens it from a click on Choose Settings…, or as the continuation of
/// a join the user just started. It starts no nested run loop (`beginSheetModal`), one is open at a time, and none of its
/// buttons is the default: Use and Keep replace values and cannot be undone, so a Return meant for a panel before never
/// answers, and Escape is the last button (Later, or Cancel while joining) in every language.
@MainActor
final class SyncQuestionSheet: SyncQuestionPresenting {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: Presenting

    func present(_ question: SyncQuestion, on window: NSWindow) async -> SyncAnswerRequest? {
        guard let appState, window.isVisible, !window.isMiniaturized, window.attachedSheet == nil else {
            return nil
        }
        let model = SyncQuestionModel(question: question, names: .live(appState: appState))
        guard !model.entries.isEmpty else {
            return nil
        }
        let kind = question.kind
        let isBystander = kind == .bystander

        let alert = NSAlert()
        alert.messageText = String(localized: "Which settings should holzBar use?")
        alert.informativeText = Self.bodyText(for: kind)
        let accessory = Self.accessory(for: model)
        alert.accessoryView = accessory

        // AppKit order: Use, Keep, then Later or Cancel; a bystander sheet has Use Chosen Settings and Later.
        let use = alert.addButton(withTitle: isBystander ? String(localized: "Use Chosen Settings") : String(localized: "Use Settings from Sync Folder"))
        let keep = isBystander ? nil : alert.addButton(withTitle: String(localized: "Keep This Mac's Settings"))
        let last = alert.addButton(withTitle: kind == .joining ? String(localized: "Cancel") : String(localized: "Later"))
        // Either choice replaces values and cannot be undone: the buttons say so (HIG), and neither is the default.
        use.hasDestructiveAction = true
        keep?.hasDestructiveAction = true
        use.keyEquivalent = ""
        keep?.keyEquivalent = ""
        // Escape in every language, not only for the English title.
        last.keyEquivalent = "\u{1B}"

        // Use and Keep wait for a pick in every pop-up; with every row decided elsewhere nothing is left to answer.
        let state = ButtonState(model: model)
        Self.apply(state, use: use, keep: keep, last: last, kind: kind)
        let buttonLoop = ObservationLoop.observe(
            { ButtonState(model: model) },
            onChange: { state in
                Self.apply(state, use: use, keep: keep, last: last, kind: kind)
            }
        )
        // A row that another Mac decides meanwhile is dimmed; the host's steps are the only trigger, nothing polls.
        let settingsSync = appState.settingsSync
        let rowLoop = ObservationLoop.observe(
            { settingsSync.questionRevision },
            onChange: { _ in
                model.refresh(current: settingsSync.currentQuestion(of: kind))
            }
        )

        // Focus starts on the first pop-up that has no pick, else on the last button, never on a destructive one.
        if model.firstUndecidedChoice != nil {
            alert.window.initialFirstResponder = accessory
        } else {
            alert.window.initialFirstResponder = last
        }

        let response = await alert.beginSheetModal(for: window)
        buttonLoop.cancel()
        rowLoop.cancel()

        switch response {
        case .alertFirstButtonReturn:
            return model.canAnswer ? model.request(for: isBystander ? .useChosen : .use) : nil
        case .alertSecondButtonReturn where !isBystander:
            return model.canAnswer ? model.request(for: .keep) : nil
        case .alertSecondButtonReturn, .alertThirdButtonReturn:
            // Done writes nothing; Later and Cancel say so.
            return model.isFinished ? nil : model.request(for: kind == .joining ? .cancel : .later)
        default:
            return nil
        }
    }

    // MARK: Texts

    /// The body of the sheet: what the rows are about.
    private static func bodyText(for kind: SyncQuestionKind) -> String {
        switch kind {
        case .running:
            String(localized: "You changed these settings on this Mac, and they were changed differently on another Mac. Your other settings stay as they are on all your Macs.")
        case .joining:
            String(localized: "These settings differ between this Mac and the sync folder.")
        case .bystander:
            String(localized: "Your other Macs changed these settings differently. Choose which value to use on all your Macs.")
        }
    }

    // MARK: Accessory

    /// The rows and the footer, 480 pt wide. The list is as tall as its rows, and scrolls above 240 pt.
    private static func accessory(for model: SyncQuestionModel) -> NSView {
        let natural = NSHostingController(rootView: SyncQuestionGrid(model: model))
            .sizeThatFits(in: CGSize(width: SyncQuestionRows.width, height: 10_000))
            .height
        let height = min(natural, SyncQuestionRows.maximumListHeight)
        let hosting = NSHostingView(rootView: SyncQuestionRows(model: model, listHeight: height))
        hosting.setFrameSize(hosting.fittingSize)
        return hosting
    }

    // MARK: Buttons

    /// What decides the state of the buttons.
    private struct ButtonState: Equatable {
        var canAnswer: Bool
        var isFinished: Bool

        init(model: SyncQuestionModel) {
            canAnswer = model.canAnswer
            isFinished = model.isFinished
        }
    }

    private static func apply(_ state: ButtonState, use: NSButton, keep: NSButton?, last: NSButton, kind: SyncQuestionKind) {
        use.isEnabled = state.canAnswer
        keep?.isEnabled = state.canAnswer
        if state.isFinished {
            last.title = String(localized: "Done")
        } else {
            last.title = kind == .joining ? String(localized: "Cancel") : String(localized: "Later")
        }
    }
}

// MARK: - Names

extension SyncRowNames {
    /// The names as the running app shows them.
    static func live(appState: AppState) -> SyncRowNames {
        SyncRowNames(
            hotkey: { target in
                appState.settings.hotkeys.name(of: target)
            },
            item: { key in
                appState.itemManager.item(withIdentityKey: key)?.displayName ?? key
            },
            application: { identifier in
                NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first?.localizedName ?? identifier
            },
            icon: { data in
                guard let imageSet = try? JSONDecoder().decode(ControlItemImageSet.self, from: data) else {
                    return nil
                }
                return SyncIconPicture(
                    name: imageSet.name.rawValue,
                    image: imageSet.hidden.nsImage(for: appState),
                    isCustom: imageSet.name == .custom
                )
            }
        )
    }
}
