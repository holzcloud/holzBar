//
//  DisplayControlsBodyView.swift
//  holzBar
//

import SwiftUI

/// The Display controls tab: a brightness slider for each display macOS can change, a card with
/// a slider for each control of each external monitor that answers DDC/CI, then a slider row
/// for the volume of the Mac's sound output.
///
/// The row follows the concept's slider row: a 28 pt slot with a 16 pt symbol, the name, the
/// system slider and the value in a 44 pt column. The hub is always dark, so the row uses fixed
/// white tints. Nothing here repeats: the state is read when the tab appears and the runtime
/// reads it again when the hub opens.
struct DisplayControlsBodyView: View {
    let runtime: DisplayControlsRuntime

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(spacing: Row.gap) {
                displayCards
                volumeRow
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            runtime.refresh()
        }
    }

    /// The sizes of the slider row (design concept, section 10).
    private enum Row {
        static let height: CGFloat = 36
        static let slot: CGFloat = 28
        static let valueWidth: CGFloat = 44
        static let gap = HolzBarTheme.Spacing.xxs
        static let disabledOpacity = 0.4
    }

    /// Whether the output has a volume the app can show and set.
    private var isAvailable: Bool {
        runtime.plan != .unsupported && runtime.volume != nil
    }

    /// The display cards in the tab's order: an external monitor's card where the module controls
    /// it over DDC, else the display's brightness row; a sentence when the brightness part is
    /// unavailable, nothing for a display while the Brightness setting is off.
    @ViewBuilder
    private var displayCards: some View {
        if runtime.showsBrightness, !runtime.gate.isAvailable {
            card {
                Text("Brightness is not available on this Mac")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .frame(maxWidth: .infinity, minHeight: Row.height, alignment: .leading)
            }
        }
        ForEach(runtime.displayOrder, id: \.self) { id in
            if let monitor = runtime.externals.first(where: { $0.id == id }) {
                externalCard(monitor)
            } else if runtime.showsBrightness, runtime.gate.isAvailable,
                      let display = runtime.displays.first(where: { $0.id == id }) {
                brightnessRow(display)
            }
        }
    }

    /// An external monitor's card: a header with its name and the Preview badge, then the rows
    /// of the controls it reported. The rows carry no visible name; the symbol says which control
    /// it is and the name is the accessibility label and the tooltip.
    private func externalCard(_ monitor: DisplayControlsRuntime.ExternalMonitor) -> some View {
        card {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Text(verbatim: monitor.name)
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .lineLimit(1)
                    .truncationMode(.tail)
                PreviewBadge()
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(height: Row.slot)
            switch monitor.state {
            case .reading, .ready:
                ForEach(DDCCapabilities.rows(confirmed: Set(monitor.values.keys)), id: \.self) { control in
                    externalRow(control, monitor: monitor)
                }
            case .doesNotAnswer:
                caption(Text("This display does not answer DDC. Turn on DDC/CI in the display's own menu."))
            case .indistinguishable:
                caption(Text("macOS cannot change this display from here"))
            case .unavailable:
                caption(Text("External monitor control is not available on this Mac. Restart holzBar to try again."))
            }
        }
    }

    /// The row of one confirmed control of an external monitor. Brightness and contrast have a
    /// floor of 2 percent, so a slip cannot make the screen unreadable.
    @ViewBuilder
    private func externalRow(_ control: DDCControl, monitor: DisplayControlsRuntime.ExternalMonitor) -> some View {
        switch control {
        case .brightness:
            levelRow(
                symbol: "sun.max.fill",
                label: String(localized: "Brightness"),
                control: .brightness,
                monitor: monitor,
                range: DDCLevel.brightnessFloor...1
            )
        case .contrast:
            levelRow(
                symbol: "circle.lefthalf.filled",
                label: String(localized: "Contrast"),
                control: .contrast,
                monitor: monitor,
                range: DDCLevel.contrastFloor...1
            )
        case .volume, .mute:
            EmptyView()
        }
    }

    /// The one line a card shows instead of rows: the state and, where there is one, its next
    /// step. It wraps, so a long translation never clips; a state is never shown by dimming alone.
    private func caption(_ text: Text) -> some View {
        text
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Hub.neutral)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Row.slot + HolzBarTheme.Spacing.xs)
            .padding(.bottom, HolzBarTheme.Spacing.xxs)
    }

    /// One level row of an external monitor: the control's symbol in the 28 pt slot, the slider
    /// and the value. The slider shows the level requested while it moves and the level the
    /// monitor reports afterwards.
    private func levelRow(
        symbol: String,
        label: String,
        control: DDCControl,
        monitor: DisplayControlsRuntime.ExternalMonitor,
        range: ClosedRange<Double>
    ) -> some View {
        let shown = runtime.externalLevel(control: control, display: monitor.id) ?? range.lowerBound
        return HStack(spacing: HolzBarTheme.Spacing.xs) {
            Image(systemName: symbol)
                .font(HolzBarTheme.Hub.compactSymbolFont)
                .foregroundStyle(HolzBarTheme.Hub.pillText)
                .frame(width: Row.slot, height: Row.slot)
                .help(label)
                .accessibilityHidden(true)
            Slider(value: externalLevel(control: control, monitor: monitor, fallback: range.lowerBound), in: range)
                .tint(HolzBarTheme.Palette.accent)
                .accessibilityLabel(Text(verbatim: "\(label), \(monitor.name)"))
                .accessibilityValue(Text("\(DisplayControlsLevel.percent(shown)) percent"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: runtime.adjustExternalLevel(by: 1, control: control, display: monitor.id)
                    case .decrement: runtime.adjustExternalLevel(by: -1, control: control, display: monitor.id)
                    @unknown default: break
                    }
                }
                .onKeyPress(.leftArrow) { stepExternal(-1, control: control, monitor: monitor) }
                .onKeyPress(.downArrow) { stepExternal(-1, control: control, monitor: monitor) }
                .onKeyPress(.rightArrow) { stepExternal(1, control: control, monitor: monitor) }
                .onKeyPress(.upArrow) { stepExternal(1, control: control, monitor: monitor) }
            Text(verbatim: "\(DisplayControlsLevel.percent(shown)) %")
                .font(HolzBarTheme.Typography.mono.monospacedDigit())
                .foregroundStyle(HolzBarTheme.Hub.neutral)
                .frame(width: Row.valueWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(height: Row.height)
    }

    /// The slider's value: the level requested or reported, requested through the runtime.
    private func externalLevel(
        control: DDCControl,
        monitor: DisplayControlsRuntime.ExternalMonitor,
        fallback: Double
    ) -> Binding<Double> {
        Binding(
            get: { runtime.externalLevel(control: control, display: monitor.id) ?? fallback },
            set: { runtime.setExternalLevel($0, control: control, display: monitor.id) }
        )
    }

    /// An arrow key steps an external monitor's level by 5 percent when its slider has focus.
    private func stepExternal(
        _ steps: Int,
        control: DDCControl,
        monitor: DisplayControlsRuntime.ExternalMonitor
    ) -> KeyPress.Result {
        guard runtime.externalLevel(control: control, display: monitor.id) != nil else {
            return .ignored
        }
        runtime.adjustExternalLevel(by: steps, control: control, display: monitor.id)
        return .handled
    }

    /// One display's brightness: a slider where macOS can change it, a caption where it cannot.
    private func brightnessRow(_ display: DisplayControlsRuntime.DisplayBrightness) -> some View {
        let isAdjustable = display.canChange && display.value != nil
        return card {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Image(systemName: "sun.max.fill")
                    .font(HolzBarTheme.Hub.compactSymbolFont)
                    .foregroundStyle(HolzBarTheme.Hub.pillText)
                    .frame(width: Row.slot, height: Row.slot)
                    .accessibilityHidden(true)
                Text(verbatim: display.name)
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Slider(value: brightnessLevel(display), in: DisplayControlsLevel.minimumBrightness...1)
                    .tint(HolzBarTheme.Palette.accent)
                    .disabled(!isAdjustable)
                    .opacity(isAdjustable ? 1 : Row.disabledOpacity)
                    .accessibilityLabel(Text(verbatim: "\(String(localized: "Brightness")), \(display.name)"))
                    .accessibilityValue(Text("\(DisplayControlsLevel.percent(display.value ?? 0)) percent"))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: runtime.adjustBrightness(by: 1, for: display.id)
                        case .decrement: runtime.adjustBrightness(by: -1, for: display.id)
                        @unknown default: break
                        }
                    }
                    .onKeyPress(.leftArrow) { stepBrightness(-1, display) }
                    .onKeyPress(.downArrow) { stepBrightness(-1, display) }
                    .onKeyPress(.rightArrow) { stepBrightness(1, display) }
                    .onKeyPress(.upArrow) { stepBrightness(1, display) }
                Text(brightnessText(display))
                    .font(HolzBarTheme.Typography.mono.monospacedDigit())
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .frame(width: Row.valueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(height: Row.height)
            if !display.canChange {
                Text("macOS cannot change this display from here")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .padding(.leading, Row.slot + HolzBarTheme.Spacing.xs)
                    .padding(.bottom, HolzBarTheme.Spacing.xxs)
            }
        }
    }

    /// The row's chrome: the hub's tile fill and hairline border around the content.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(HolzBarTheme.Spacing.xs)
            .background(
                .white.opacity(reduceTransparency ? DesignTokens.Hub.tileFillAlphaOpaque : DesignTokens.Hub.tileFillAlpha),
                in: HolzBarTheme.shape(CGFloat(DesignTokens.Hub.tileRadius))
            )
            .overlay {
                HolzBarTheme.shape(CGFloat(DesignTokens.Hub.tileRadius))
                    .stroke(.white.opacity(DesignTokens.Hub.fileTileBorderAlpha), lineWidth: HolzBarTheme.Spacing.hairline)
            }
            .accessibilityElement(children: .contain)
    }

    private func brightnessLevel(_ display: DisplayControlsRuntime.DisplayBrightness) -> Binding<Double> {
        Binding(
            get: { display.value ?? DisplayControlsLevel.minimumBrightness },
            set: { runtime.setBrightness($0, for: display.id) }
        )
    }

    private func brightnessText(_ display: DisplayControlsRuntime.DisplayBrightness) -> String {
        guard let value = display.value else {
            return "–"
        }
        return "\(DisplayControlsLevel.percent(value)) %"
    }

    /// An arrow key steps a display's brightness by 5 percent when its slider has focus.
    private func stepBrightness(_ steps: Int, _ display: DisplayControlsRuntime.DisplayBrightness) -> KeyPress.Result {
        guard display.canChange, display.value != nil else {
            return .ignored
        }
        runtime.adjustBrightness(by: steps, for: display.id)
        return .handled
    }

    private var volumeRow: some View {
        card {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                muteButton
                Text(verbatim: runtime.outputName ?? String(localized: "Volume"))
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Slider(value: level, in: 0...1)
                    .tint(HolzBarTheme.Palette.accent)
                    .disabled(!isAvailable)
                    .opacity(isAvailable ? 1 : Row.disabledOpacity)
                    .accessibilityLabel(Text("Volume"))
                    .accessibilityValue(Text("\(DisplayControlsLevel.percent(runtime.volume ?? 0)) percent"))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: runtime.adjustVolume(by: 1)
                        case .decrement: runtime.adjustVolume(by: -1)
                        @unknown default: break
                        }
                    }
                    .onKeyPress(.leftArrow) { step(-1) }
                    .onKeyPress(.downArrow) { step(-1) }
                    .onKeyPress(.rightArrow) { step(1) }
                    .onKeyPress(.upArrow) { step(1) }
                Text(valueText)
                    .font(HolzBarTheme.Typography.mono.monospacedDigit())
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .frame(width: Row.valueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(height: Row.height)
            if !isAvailable {
                Text("This output has no volume control")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .padding(.leading, Row.slot + HolzBarTheme.Spacing.xs)
                    .padding(.bottom, HolzBarTheme.Spacing.xxs)
            }
        }
    }

    /// The mute button in the 28 pt slot. It is disabled where the output has no mute that can
    /// be set, and it states its state to VoiceOver.
    private var muteButton: some View {
        Button {
            runtime.setMuted(!runtime.isMuted)
        } label: {
            Image(systemName: runtime.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(HolzBarTheme.Hub.compactSymbolFont)
                .foregroundStyle(HolzBarTheme.Hub.pillText)
                .frame(width: Row.slot, height: Row.slot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!runtime.canMute)
        .opacity(runtime.canMute ? 1 : Row.disabledOpacity)
        .accessibilityLabel(runtime.isMuted ? Text("Unmute") : Text("Mute"))
        .accessibilityAddTraits(runtime.isMuted ? .isSelected : [])
    }

    /// An arrow key steps the level by 5 percent when the slider has focus.
    private func step(_ steps: Int) -> KeyPress.Result {
        guard isAvailable else {
            return .ignored
        }
        runtime.adjustVolume(by: steps)
        return .handled
    }

    /// The slider's value: the level read back, written through the runtime.
    private var level: Binding<Double> {
        Binding(
            get: { runtime.volume ?? 0 },
            set: { runtime.setVolume($0) }
        )
    }

    private var valueText: String {
        guard isAvailable, let volume = runtime.volume else {
            return "–"
        }
        return "\(DisplayControlsLevel.percent(volume)) %"
    }
}
