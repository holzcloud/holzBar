//
//  HotkeyRecorder.swift
//  holzBar
//

import OSLog
import SwiftUI

// MARK: - HotkeyRecorder

struct HotkeyRecorder<Label: View>: View {
    @State private var model: HotkeyRecorderModel

    private let label: Label

    /// Creates a recorder for the given hotkey.
    ///
    /// - Parameter settings: The Hotkeys settings, which hold the other hotkeys that may
    ///   already use a typed combination.
    init(hotkey: Hotkey, settings: HotkeysSettings, @ViewBuilder label: () -> Label) {
        self._model = State(wrappedValue: HotkeyRecorderModel(hotkey: hotkey, settings: settings))
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            segmentStack
        } label: {
            label
        }
        .alert(
            model.presentedProblem?.title ?? "",
            isPresented: $model.isPresentingProblem,
            presenting: model.presentedProblem
        ) { problem in
            switch problem {
            case .alreadyUsed(let holder, _, let keyCombination):
                Button("Replace") {
                    model.replace(holder, with: keyCombination)
                }
                // Recording goes on, so that the user can type another combination.
                Button("Cancel", role: .cancel) { }
            case .systemReserved, .optionOnly, .registrationFailed:
                Button("OK") {
                    model.presentedProblem = nil
                }
            }
        } message: { problem in
            Text(problem.message)
        }
        .onDisappear {
            // Recording disables the hotkey, so register it again when the
            // recorder goes away (another Settings pane, a closed popover).
            model.stopRecording()
        }
    }

    @ViewBuilder
    private var segmentStack: some View {
        HStack(spacing: 1) {
            leadingSegment
            trailingSegment
        }
        .frame(width: 132, height: 24)
    }

    @ViewBuilder
    private var leadingSegment: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else {
                model.startRecording()
            }
        } label: {
            leadingSegmentLabel
        }
        .buttonStyle(
            HotkeyRecorderButtonStyle(
                segment: .leading,
                isHighlighted: model.isRecording
            )
        )
    }

    @ViewBuilder
    private var trailingSegment: some View {
        Button {
            if model.isRecording {
                model.stopRecording()
            } else if model.hotkey.keyCombination != nil {
                model.hotkey.keyCombination = nil
            } else {
                model.startRecording()
            }
        } label: {
            trailingSegmentLabel
        }
        .buttonStyle(
            HotkeyRecorderButtonStyle(
                segment: .trailing,
                isHighlighted: false
            )
        )
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var leadingSegmentLabel: some View {
        if model.isRecording {
            Text("Type Hotkey")
        } else if let keyCombination = model.hotkey.keyCombination {
            Text(keyCombination.displayValue)
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var trailingSegmentLabel: some View {
        let (name, label, padding) = if model.isRecording {
            ("escape", "Cancel", 6.0)
        } else if model.hotkey.keyCombination != nil {
            ("xmark", "Clear", 7.5)
        } else {
            ("record.circle", "Record", 5.5)
        }
        Image(systemName: name)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .padding(padding)
            .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

// MARK: - HotkeyRecorderModel

@MainActor
@Observable
private final class HotkeyRecorderModel {

    private(set) var isRecording = false

    /// A reason why the recorder refused the typed combination.
    enum Problem {
        /// macOS uses the combination for one of its own shortcuts.
        case systemReserved
        /// The only modifiers are Option, or Option and Shift, which macOS 15 and
        /// later do not register.
        case optionOnly
        /// Another holzBar hotkey has the combination, and the system registers a
        /// combination only once per app.
        case alreadyUsed(holder: Hotkey, holderName: String, keyCombination: KeyCombination)
        /// The system did not register the combination, so the hotkey kept its previous one.
        case registrationFailed

        /// The title of the alert that explains the problem.
        var title: String {
            switch self {
            case .systemReserved:
                String(localized: "Hotkey is reserved by macOS")
            case .optionOnly:
                String(localized: "macOS does not allow this hotkey")
            case .alreadyUsed:
                String(localized: "Hotkey already in use")
            case .registrationFailed:
                String(localized: "Hotkey could not be registered")
            }
        }

        /// The message of the alert, which says what to do instead.
        var message: String {
            switch self {
            case .systemReserved:
                String(localized: "macOS uses this combination for one of its own shortcuts. Choose another one.")
            case .optionOnly:
                String(localized: "Since macOS 15, a hotkey whose only modifiers are Option, or Option and Shift, cannot be registered. Add Command or Control.")
            case .alreadyUsed(_, let holderName, _):
                String(localized: "\u{201C}\(holderName)\u{201D} already uses this combination. Use it here instead?")
            case .registrationFailed:
                String(localized: "macOS did not accept this combination. Choose another one.")
            }
        }
    }

    /// The problem the alert presents, if any.
    var presentedProblem: Problem?

    /// A Boolean value that indicates whether the alert for a problem is presented.
    ///
    /// Setting it to `false` clears the problem.
    var isPresentingProblem: Bool {
        get {
            presentedProblem != nil
        }
        set {
            if !newValue {
                presentedProblem = nil
            }
        }
    }

    let hotkey: Hotkey

    /// The Hotkeys settings, which hold the other hotkeys.
    private let settings: HotkeysSettings

    /// The hotkey's key combination when recording started, which it gets back when the
    /// system does not register a new one.
    @ObservationIgnored private var keyCombinationBeforeRecording: KeyCombination?

    /// The recorder that is recording, if any.
    ///
    /// Only one recorder records at a time, because each one's monitor
    /// swallows every key press in the app.
    private static weak var current: HotkeyRecorderModel?

    @ObservationIgnored private lazy var monitor = EventMonitor.local(for: .keyDown) { [weak self] event in
        guard let self else {
            return event
        }
        // While the alert for a problem is shown, it gets the key presses
        // (Return, Escape), and recording resumes once it is dismissed.
        guard presentedProblem == nil else {
            return event
        }
        handleKeyDown(event: event)
        return nil
    }

    init(hotkey: Hotkey, settings: HotkeysSettings) {
        self.hotkey = hotkey
        self.settings = settings
    }

    isolated deinit {
        // A backstop for a recorder that goes away without disappearing first.
        if isRecording {
            hotkey.enable()
        }
    }

    func startRecording() {
        guard !isRecording else {
            return
        }
        Self.current?.stopRecording()
        Self.current = self
        keyCombinationBeforeRecording = hotkey.keyCombination
        hotkey.disable()
        monitor.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else {
            return
        }
        monitor.stop()
        hotkey.enable()
        isRecording = false
    }

    private func handleKeyDown(event: NSEvent) {
        let keyCombination = KeyCombination(event: event)
        let refusesOptionOnly = if #available(macOS 15.0, *) { true } else { false }
        switch keyCombination.modifiers.rejection(refusesOptionOnly: refusesOptionOnly) {
        case .missing:
            if keyCombination.key == .escape {
                stopRecording()
            } else {
                NSSound.beep()
            }
            return
        case .shiftOnly:
            NSSound.beep()
            return
        case .optionOnly:
            // Keep recording, so that the user can type another combination.
            presentedProblem = .optionOnly
            return
        case nil:
            break
        }
        guard !keyCombination.isSystemReserved else {
            presentedProblem = .systemReserved
            return
        }
        // The system registers a combination only once per app, so another hotkey that
        // has it would leave this one dead. Ask whether to move it here.
        if let holder = settings.hotkey(using: keyCombination, except: hotkey.target) {
            presentedProblem = .alreadyUsed(
                holder: holder,
                holderName: settings.name(of: holder.target),
                keyCombination: keyCombination
            )
            return
        }
        if !assign(keyCombination) {
            presentedProblem = .registrationFailed
        }
    }

    /// Moves the key combination from the other hotkey that has it to this one.
    func replace(_ holder: Hotkey, with keyCombination: KeyCombination) {
        // Clear the other hotkey first, so that the combination is free to register.
        let wasHolderEnabled = holder.isEnabled
        holder.keyCombination = nil
        guard assign(keyCombination) else {
            // The other hotkey keeps its combination, registered only if it was before
            // (the always-hidden section's hotkey is not while the section is off).
            holder.keyCombination = keyCombination
            if !wasHolderEnabled {
                holder.disable()
            }
            // The alert that offered the replacement is still closing.
            Task {
                presentedProblem = .registrationFailed
            }
            return
        }
    }

    /// Gives the hotkey the key combination and stops recording.
    ///
    /// - Returns: `false` when the system did not register the combination; the hotkey
    ///   then gets back its previous combination and recording goes on.
    private func assign(_ keyCombination: KeyCombination) -> Bool {
        hotkey.keyCombination = keyCombination
        guard hotkey.isEnabled else {
            Logger.hotkeys.error("Could not register the hotkey of \(self.hotkey.target.logDescription, privacy: .public)")
            hotkey.keyCombination = keyCombinationBeforeRecording
            if isRecording {
                hotkey.disable()
            }
            return false
        }
        stopRecording()
        return true
    }
}

// MARK: - HotkeyRecorderButtonStyle

private struct HotkeyRecorderButtonStyle: ButtonStyle {
    enum Segment {
        case leading
        case trailing
    }

    var segment: Segment
    var isHighlighted: Bool

    private var radii: RectangleCornerRadii {
        let r: CGFloat = if #available(macOS 26.0, *) { 6 } else { 5 }
        return switch segment {
        case .leading: RectangleCornerRadii(topLeading: r, bottomLeading: r)
        case .trailing: RectangleCornerRadii(bottomTrailing: r, topTrailing: r)
        }
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        } else {
            UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let isProminent = configuration.isPressed != isHighlighted
        borderShape
            .fill(isProminent ? .tertiary : .quaternary)
            .opacity(isProminent ? 0.5 : 0.75)
            .overlay {
                configuration.label
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .contentShape([.interaction, .focusEffect], borderShape)
    }
}
