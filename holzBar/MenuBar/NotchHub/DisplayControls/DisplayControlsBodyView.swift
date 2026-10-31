//
//  DisplayControlsBodyView.swift
//  holzBar
//

import SwiftUI

/// The Display controls tab: a slider row for the volume of the Mac's sound output.
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
        VStack(spacing: Row.gap) {
            brightnessRow
            volumeRow
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
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

    /// The built-in display's brightness: a slider, or one sentence when the part is unavailable.
    private var brightnessRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Image(systemName: "sun.max.fill")
                    .font(HolzBarTheme.Hub.compactSymbolFont)
                    .foregroundStyle(HolzBarTheme.Hub.pillText)
                    .frame(width: Row.slot, height: Row.slot)
                    .accessibilityHidden(true)
                Text("Brightness")
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .lineLimit(1)
                if runtime.gate.isAvailable, runtime.brightness != nil {
                    Slider(value: brightnessLevel, in: DisplayControlsLevel.minimumBrightness...1)
                        .tint(HolzBarTheme.Palette.accent)
                        .accessibilityLabel(Text("Brightness"))
                        .accessibilityValue(Text("\(DisplayControlsLevel.percent(runtime.brightness ?? 0)) percent"))
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: runtime.adjustBrightness(by: 1)
                            case .decrement: runtime.adjustBrightness(by: -1)
                            @unknown default: break
                            }
                        }
                        .onKeyPress(.leftArrow) { stepBrightness(-1) }
                        .onKeyPress(.downArrow) { stepBrightness(-1) }
                        .onKeyPress(.rightArrow) { stepBrightness(1) }
                        .onKeyPress(.upArrow) { stepBrightness(1) }
                    Text(brightnessText)
                        .font(HolzBarTheme.Typography.mono.monospacedDigit())
                        .foregroundStyle(HolzBarTheme.Hub.neutral)
                        .frame(width: Row.valueWidth, alignment: .trailing)
                        .accessibilityHidden(true)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: Row.height)
            if !runtime.gate.isAvailable {
                Text("Brightness is not available on this Mac")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.neutral)
                    .padding(.leading, Row.slot + HolzBarTheme.Spacing.xs)
                    .padding(.bottom, HolzBarTheme.Spacing.xxs)
            }
        }
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

    private var brightnessLevel: Binding<Double> {
        Binding(
            get: { runtime.brightness ?? DisplayControlsLevel.minimumBrightness },
            set: { runtime.setBrightness($0) }
        )
    }

    private var brightnessText: String {
        guard let brightness = runtime.brightness else {
            return "–"
        }
        return "\(DisplayControlsLevel.percent(brightness)) %"
    }

    private func stepBrightness(_ steps: Int) -> KeyPress.Result {
        guard runtime.brightness != nil else {
            return .ignored
        }
        runtime.adjustBrightness(by: steps)
        return .handled
    }

    private var volumeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
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
