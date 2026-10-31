//
//  TimersBodyView.swift
//  holzBar
//

import SwiftUI

/// The Timers tab: a form to start a timer on the left, the list of timers on the right.
///
/// The remaining time and the progress bar are drawn by the system from a date range, so the
/// view runs no timer of its own and refreshes nothing every second.
struct TimersBodyView: View {
    let runtime: TimersRuntime
    let host: any HubHost

    private enum Mode: Hashable {
        case length
        case until
        case stopwatch
    }

    private enum Field: Hashable {
        case length
        case label
        case moment
    }

    @State private var mode = Mode.length
    @State private var lengthText = ""
    @State private var label = ""
    @State private var moment = Self.defaultMoment()
    @State private var message: LocalizedStringKey?
    @FocusState private var focus: Field?

    var body: some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.lg) {
            form
                .frame(width: 300)
            list
        }
        .padding(.vertical, HolzBarTheme.Spacing.xxs)
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
        .onChange(of: focus) { _, field in
            if field != nil {
                host.takeKeyboard()
            }
        }
        .onChange(of: label) {
            if label.count > TimerBoard.maximumLabelLength {
                label = String(label.prefix(TimerBoard.maximumLabelLength))
            }
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            HStack(spacing: HolzBarTheme.Spacing.xxs) {
                ForEach(TimerInput.presets, id: \.self) { preset in
                    Chip(LocalizedStringKey(TimersFormat.length(preset)), isSelected: false) {
                        start(length: preset)
                    }
                }
            }
            Picker("Timer type", selection: $mode) {
                Text("Length").tag(Mode.length)
                Text("Until").tag(Mode.until)
                Text("Stopwatch").tag(Mode.stopwatch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                switch mode {
                case .length:
                    TextField("25, 1:30 or 1h 30m", text: $lengthText)
                        .focused($focus, equals: .length)
                        .onSubmit(startTyped)
                case .until:
                    DatePicker("Until", selection: $moment, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .focused($focus, equals: .moment)
                case .stopwatch:
                    Text("Counts up until you stop it.")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Start", action: startTyped)
                    .buttonStyle(.borderedProminent)
                    .tint(HolzBarTheme.Palette.accent)
            }
            TextField("Label", text: $label)
                .focused($focus, equals: .label)
                .onSubmit(startTyped)
            if let message {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(.small)
        .textFieldStyle(.roundedBorder)
    }

    private static func defaultMoment() -> Date {
        let hourAhead = Date.now.addingTimeInterval(3_600).timeIntervalSince1970
        return Date(timeIntervalSince1970: (hourAhead / 60).rounded(.down) * 60)
    }

    private func startTyped() {
        switch mode {
        case .length:
            guard let seconds = TimerInput.parseLength(lengthText) else {
                message = "Enter a length such as 25, 1:30 or 1h 30m"
                return
            }
            start(length: seconds)
        case .until:
            show(runtime.startMoment(moment, label: label))
        case .stopwatch:
            show(runtime.startStopwatch(label: label))
        }
    }

    private func start(length seconds: Double) {
        show(runtime.startLength(seconds, label: label))
    }

    /// Clears the form after a start, or says in words why there was none.
    private func show(_ result: TimerBoard.StartResult) {
        switch result {
        case .started:
            message = nil
            lengthText = ""
            label = ""
            moment = Self.defaultMoment()
        case .refused(.full):
            message = "Remove a timer to start another."
        case .refused(.lengthOutOfRange):
            message = "Enter a length such as 25, 1:30 or 1h 30m"
        case .refused(.momentTooSoon):
            message = "Choose a moment a little later."
        case .refused(.momentTooFar):
            message = "Choose a moment within the next year."
        }
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if runtime.board.items.isEmpty {
            Text("No timers yet")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: HolzBarTheme.Spacing.xs) {
                    ForEach(runtime.board.ordered) { item in
                        row(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ item: TimerItem) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            info(item)
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text(LocalizedStringKey(isRunning(item) ? "Pause" : "Resume"))) {
                    toggle(item)
                }
                .accessibilityAction(named: Text("Restart")) {
                    runtime.restart(item.id)
                }
                .accessibilityAction(named: Text("Remove")) {
                    runtime.remove(item.id)
                }
            if canPause(item) {
                iconButton(isRunning(item) ? "pause.fill" : "play.fill", title: isRunning(item) ? "Pause" : "Resume") {
                    toggle(item)
                }
            }
            if !isMoment(item) {
                iconButton("arrow.counterclockwise", title: "Restart") {
                    runtime.restart(item.id)
                }
            }
            iconButton("xmark", title: "Remove") {
                runtime.remove(item.id)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func isRunning(_ item: TimerItem) -> Bool {
        switch item.state {
        case .running, .counting: true
        case .paused, .finished, .halted: false
        }
    }

    private func isMoment(_ item: TimerItem) -> Bool {
        if case .moment = item.kind {
            return true
        }
        return false
    }

    /// Whether the pause or resume button shows: a running or paused timer of kind length, or
    /// a stopwatch.
    private func canPause(_ item: TimerItem) -> Bool {
        if isMoment(item) {
            return false
        }
        if case .finished = item.state {
            return false
        }
        return true
    }

    private func toggle(_ item: TimerItem) {
        if isRunning(item) {
            runtime.pause(item.id)
        } else {
            runtime.resume(item.id)
        }
    }

    private func info(_ item: TimerItem) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
            HStack {
                Text(verbatim: TimersFormat.name(of: item))
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: HolzBarTheme.Spacing.xs)
                status(of: item)
            }
            switch item.state {
            case .running(let start, let end):
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(HolzBarTheme.Palette.danger)
            case .paused:
                ProgressView(value: runtime.board.fraction(of: item.id, now: .now) ?? 0)
                    .tint(HolzBarTheme.Palette.textTertiary)
            case .finished, .counting, .halted:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func status(of item: TimerItem) -> some View {
        switch item.state {
        case .running(let start, let end):
            Text(timerInterval: start...end, countsDown: true)
                .font(HolzBarTheme.Typography.mono)
                .monospacedDigit()
                .foregroundStyle(HolzBarTheme.Palette.text)
        case .counting(let since):
            Text(timerInterval: since...TimersFormat.stopwatchEnd(from: since), countsDown: false)
                .font(HolzBarTheme.Typography.mono)
                .monospacedDigit()
                .foregroundStyle(HolzBarTheme.Palette.text)
        case .paused(let remaining, _):
            stopped(TimersFormat.clock(remaining))
        case .halted(let elapsed):
            stopped(TimersFormat.clock(elapsed))
        case .finished:
            Label("Done", systemImage: "bell.fill")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.danger)
        }
    }

    private func stopped(_ clock: String) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            Text(verbatim: clock)
                .font(HolzBarTheme.Typography.mono)
                .monospacedDigit()
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            Text("Paused")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        }
    }

    private func iconButton(_ symbol: String, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }
}
