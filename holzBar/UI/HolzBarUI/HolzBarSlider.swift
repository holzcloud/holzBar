//
//  HolzBarSlider.swift
//  holzBar
//

import SwiftUI

/// A compact slider with its value label drawn inside: the track fills up to the value,
/// a drag (or click) sets the value, the arrow keys move it by one step while it has
/// keyboard focus, and VoiceOver reads and adjusts it. The value math is `SliderValue`.
/// It replaces the CompactSlider package with the same look.
struct HolzBarSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View {
    @Binding private var value: Value

    @FocusState private var isFocused: Bool
    @State private var isHovering = false
    @State private var isDragging = false

    private let bounds: ClosedRange<Value>
    private let step: Value?
    private let valueLabel: ValueLabel

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
    }

    init(
        _ valueLabelKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil
    ) where ValueLabel == Text {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = Text(valueLabelKey)
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var height: CGFloat {
        if #available(macOS 26.0, *) { 24 } else { 22 }
    }

    private var doubleBounds: ClosedRange<Double> {
        Double(bounds.lowerBound)...Double(bounds.upperBound)
    }

    private var doubleStep: Double? {
        step.map { Double($0) }
    }

    /// Hovered, dragged or focused, like the slider this one replaces.
    private var isHighlighted: Bool {
        isFocused || isHovering || isDragging
    }

    /// The number of steps, when a tick for each one fits.
    private var tickCount: Int? {
        guard let doubleStep, doubleStep > 0 else {
            return nil
        }
        let count = Int(((doubleBounds.upperBound - doubleBounds.lowerBound) / doubleStep).rounded())
        return (2...60).contains(count) ? count : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = SliderValue.fraction(of: Double(value), in: doubleBounds)
            ZStack(alignment: .leading) {
                Color(nsColor: .labelColor).opacity(0.075)
                Rectangle()
                    .fill(Color.accentColor.opacity(isHighlighted ? 0.75 : 0.5))
                    .frame(width: width * fraction)
                if isHighlighted, let tickCount {
                    ticks(count: tickCount, width: width)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        guard width > 0 else {
                            return
                        }
                        setValue(SliderValue.value(atFraction: gesture.location.x / width, in: doubleBounds, step: doubleStep))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: height)
        .overlay {
            valueLabel
                .frame(height: height)
                .allowsHitTesting(false)
        }
        .clipShape(borderShape)
        .contentShape([.interaction, .focusEffect], borderShape)
        .onHover { hovering in
            isHovering = hovering
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in
            move(by: -1)
            return .handled
        }
        .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in
            move(by: 1)
            return .handled
        }
        // VoiceOver sees a system slider with the value label as its label: it reads
        // the value and adjusts it by one step, like the arrow keys.
        .accessibilityRepresentation {
            Slider(value: doubleValue, in: doubleBounds, step: accessibilityStep) {
                valueLabel
            }
        }
    }

    /// The value as a `Double`, for the accessibility slider.
    private var doubleValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { setValue(SliderValue.snapped($0, in: doubleBounds, step: doubleStep)) }
        )
    }

    /// The step VoiceOver adjusts by: the slider's step, or one hundredth of the range.
    private var accessibilityStep: Double {
        doubleStep ?? (doubleBounds.upperBound - doubleBounds.lowerBound) / 100
    }

    private func ticks(count: Int, width: CGFloat) -> some View {
        Path { path in
            let spacing = width / CGFloat(count)
            for index in 1..<count {
                let x = (spacing * CGFloat(index)).rounded() + 0.5
                path.move(to: CGPoint(x: x, y: (height - 10) / 2))
                path.addLine(to: CGPoint(x: x, y: (height + 10) / 2))
            }
        }
        .stroke(Color(nsColor: .labelColor).opacity(0.4), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func move(by count: Int) {
        setValue(SliderValue.increment(Double(value), by: count, in: doubleBounds, step: doubleStep))
    }

    private func setValue(_ newValue: Double) {
        let converted = Value(newValue)
        if converted != value {
            value = converted
        }
    }
}
