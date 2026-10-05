//
//  HotkeyRecorder.swift
//  holzBar
//

import SwiftUI

// MARK: - HotkeyRecorder

struct HotkeyRecorder<Label: View>: View {
    @State private var model: HotkeyRecorderModel

    private let label: Label

    init(hotkey: Hotkey, @ViewBuilder label: () -> Label) {
        self._model = State(wrappedValue: HotkeyRecorderModel(hotkey: hotkey))
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
        ) { _ in
            Button("OK") {
                model.presentedProblem = nil
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
            } else if model.hotkey.isEnabled {
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
        } else if model.hotkey.isEnabled {
            if let keyCombination = model.hotkey.keyCombination {
                Text(keyCombination.displayValue)
            } else {
                Text("ERROR")
            }
        } else {
            Text("Record Hotkey")
        }
    }

    @ViewBuilder
    private var trailingSegmentLabel: some View {
        let (name, label, padding) = if model.isRecording {
            ("escape", "Cancel", 6.0)
        } else if model.hotkey.isEnabled {
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

        /// The title of the alert that explains the problem.
        var title: String {
            switch self {
            case .systemReserved:
                String(localized: "Hotkey is reserved by macOS")
            case .optionOnly:
                String(localized: "macOS does not allow this hotkey")
            }
        }

        /// The message of the alert, which says what to do instead.
        var message: String {
            switch self {
            case .systemReserved:
                String(localized: "macOS uses this combination for one of its own shortcuts. Choose another one.")
            case .optionOnly:
                String(localized: "Since macOS 15, a hotkey whose only modifiers are Option, or Option and Shift, cannot be registered. Add Command or Control.")
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

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
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
        hotkey.keyCombination = keyCombination
        stopRecording()
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
