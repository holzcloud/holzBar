//
//  HolzBarGradientPicker.swift
//  holzBar
//

import SwiftUI

struct HolzBarGradientPicker<Label: View>: View {
    @Binding private var gradient: HolzBarGradient
    @State private var selection: Int?
    @State private var window: NSWindow?

    private let supportsOpacity: Bool
    private let label: Label

    init(
        gradient: Binding<HolzBarGradient>,
        supportsOpacity: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }

    init(
        _ labelKey: LocalizedStringKey,
        gradient: Binding<HolzBarGradient>,
        supportsOpacity: Bool = true
    ) where Label == Text {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.label = Text(labelKey)
    }

    /// Creates a new gradient picker.
    ///
    /// - Parameters:
    ///   - gradient: A binding to a gradient.
    ///   - supportsOpacity: A Boolean value indicating whether the
    ///     picker should support opacity.
    init(
        gradient: Binding<HolzBarGradient>,
        supportsOpacity: Bool = true
    ) where Label == EmptyView {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.label = EmptyView()
    }

    var body: some View {
        LabeledContent {
            HolzBarGradientPickerRoot(
                gradient: $gradient,
                selection: $selection,
                window: $window,
                supportsOpacity: supportsOpacity
            )
            .onWindowChange(update: $window)
            .task(id: window.map(ObjectIdentifier.init)) {
                // A window that closes ends the editing of a stop.
                guard let window else {
                    return
                }
                for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) {
                    selection = nil
                }
            }
        } label: {
            label
        }
    }
}

private struct HolzBarGradientPickerRoot: View {
    @Environment(\.isEnabled) private var isEnabled

    @Binding var gradient: HolzBarGradient
    @Binding var selection: Int?
    /// A binding, not a value: the key monitor keeps the closure from the first
    /// render, when the window is not known yet, and must read the current window.
    @Binding var window: NSWindow?
    @State private var lastUpdated: Int?

    let supportsOpacity: Bool

    private let handleWidth: CGFloat = 10

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    var body: some View {
        gradient.swiftUIView(using: .displayP3)
            .clipShape(borderShape)
            .overlay {
                borderView
            }
            .padding(.vertical, 2)
            .overlay {
                GeometryReader { geometry in
                    insertionReader(geometry: geometry)
                    handles(geometry: geometry)
                }
                .padding(.horizontal, handleWidth / 2)
            }
            .frame(width: 200, height: 24)
            .shadow(radius: 2)
            .onTapGesture(count: 2) {
                distributeStops()
            }
            .onKeyDown(key: .delete, isEnabled: selection != nil) { event in
                guard isKeyDownForPicker(event) else {
                    return .ignored
                }
                deleteSelectedStop()
                return .handled
            }
            .onKeyDown(key: .escape, isEnabled: selection != nil) { event in
                guard isKeyDownForPicker(event) else {
                    return .ignored
                }
                selection = nil
                dismissColorPanel()
                return .handled
            }
            .onChange(of: gradient) { oldValue, newValue in
                gradientChanged(from: oldValue, to: newValue)
            }
            .onChange(of: selection) { oldValue, newValue in
                selectionChanged(from: oldValue, to: newValue)
            }
            .task(id: selection) {
                // While a stop is selected, the colour panel edits its colour.
                guard selection != nil else {
                    return
                }
                let center = NotificationCenter.default
                for await _ in center.notifications(named: NSColorPanel.colorDidChangeNotification, object: NSColorPanel.shared) {
                    colorPanelColorDidChange()
                }
            }
            .task(id: selection) {
                // Closing the colour panel ends the editing of the stop. Selecting another
                // stop closes and reopens the panel, which must not end the new selection.
                guard let selected = selection else {
                    return
                }
                let center = NotificationCenter.default
                for await _ in center.notifications(named: NSWindow.willCloseNotification, object: NSColorPanel.shared) {
                    guard !Task.isCancelled, selection == selected else {
                        return
                    }
                    selection = nil
                }
            }
            .compositingGroup()
            .allowsHitTesting(isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private var borderView: some View {
        borderShape
            .strokeBorder(.tertiary)
            .overlay {
                centerTickMark
            }
    }

    @ViewBuilder
    private var centerTickMark: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(width: 1, height: 6)
    }

    @ViewBuilder
    private func insertionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .contentShape(borderShape)
            .onTapGesture { location in
                insertStop(at: (location.x / geometry.size.width), select: true)
            }
    }

    @ViewBuilder
    private func handles(geometry: GeometryProxy) -> some View {
        ForEach(gradient.stops.indices, id: \.self) { index in
            HolzBarGradientPickerHandle(
                gradient: $gradient,
                selection: $selection,
                lastUpdated: $lastUpdated,
                index: index,
                geometry: geometry,
                width: handleWidth
            )
        }
    }

    /// Returns a Boolean value that indicates whether a key press is meant for
    /// the picker: it goes to the picker's window, no text is being edited there,
    /// and no modifier is held.
    ///
    /// The key monitor sees every key press in the app, including those for the
    /// colour panel's fields and for other windows.
    private func isKeyDownForPicker(_ event: NSEvent) -> Bool {
        guard
            let window,
            event.window === window,
            !(window.firstResponder is NSText)
        else {
            return false
        }
        return event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private func insertStop(at location: CGFloat, select: Bool) {
        var location = location.clamped(to: 0...1)
        if abs(location - 0.5) <= 0.025 {
            location = 0.5
        }
        if let color = gradient.color(at: location) {
            gradient.stops.append(.stop(color, location: location))
        } else {
            gradient.stops.append(.black(location: location))
        }
        if select, let index = gradient.stops.indices.last {
            Task {
                self.selection = index
            }
        }
    }

    private func gradientChanged(from oldValue: HolzBarGradient, to newValue: HolzBarGradient) {
        guard oldValue != newValue else {
            return
        }
        if newValue.stops.isEmpty {
            gradient = oldValue
        }
    }

    private func selectionChanged(from oldValue: Int?, to newValue: Int?) {
        guard oldValue != newValue else {
            return
        }

        if newValue != nil {
            dismissColorPanel()
            openColorPanel()
            prepareColorPanel()
        }
    }

    /// Shows the selected stop's colour in the colour panel, with opacity if supported.
    private func prepareColorPanel() {
        if
            let selection,
            gradient.stops.indices.contains(selection),
            let color = NSColor(cgColor: gradient.stops[selection].color),
            NSColorPanel.shared.color != color
        {
            NSColorPanel.shared.color = color
        }
        if NSColorPanel.shared.showsAlpha != supportsOpacity {
            NSColorPanel.shared.showsAlpha = supportsOpacity
        }
    }

    /// Gives the selected stop the colour panel's colour.
    private func colorPanelColorDidChange() {
        let color = NSColorPanel.shared.color
        guard
            let selection,
            NSColorPanel.shared.isVisible,
            gradient.stops.indices.contains(selection),
            gradient.stops[selection].color != color.cgColor
        else {
            return
        }
        gradient.stops[selection].color = color.cgColor
    }

    private func openColorPanel() {
        if !NSColorPanel.shared.isVisible {
            NSColorPanel.shared.orderFrontRegardless()
        }
    }

    private func dismissColorPanel() {
        if NSColorPanel.shared.isVisible {
            NSColorPanel.shared.close()
        }
    }

    private func deleteSelectedStop() {
        guard
            let index = selection.take(),
            gradient.stops.indices.contains(index)
        else {
            return
        }
        gradient.stops.remove(at: index)
    }

    private func distributeStops() {
        guard !gradient.stops.isEmpty else {
            return
        }
        if gradient.stops.count == 1 {
            gradient.stops[0].location = 0.5
        } else {
            let last = CGFloat(gradient.stops.count - 1)
            let stops = gradient.stops
            let sortedIndices = stops.indices.sorted { stops[$0].location < stops[$1].location }
            let newStops = sortedIndices
                .enumerated()
                .map { n, index in
                    stops[index].withLocation(CGFloat(n) / last)
                }
            gradient.stops = newStops
            // The selection is an index, so it follows the selected stop to its new place.
            selection = selection.flatMap { sortedIndices.firstIndex(of: $0) }
        }
    }
}

private struct HolzBarGradientPickerHandle: View {
    @Binding var gradient: HolzBarGradient
    @Binding var selection: Int?
    @Binding var lastUpdated: Int?

    let index: Int
    let geometry: GeometryProxy
    let width: CGFloat

    private var isSelected: Bool {
        index == selection
    }

    private var isLastUpdated: Bool {
        index == lastUpdated
    }

    private var stop: HolzBarGradient.ColorStop? {
        guard gradient.stops.indices.contains(index) else {
            return nil
        }
        return gradient.stops[index]
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
        } else {
            Capsule(style: .circular)
        }
    }

    var body: some View {
        handleView
            .gesture(
                DragGesture(minimumDistance: 2).onChanged { value in
                    update(with: value)
                }
            )
            .onTapGesture {
                selection = isSelected ? nil : index
            }
            .onKeyPress(.space) {
                selection = isSelected ? nil : index
                return .handled
            }
            .onChange(of: isSelected) { _, newValue in
                if newValue {
                    lastUpdated = index
                }
            }
    }

    @ViewBuilder
    private var handleView: some View {
        if let stop {
            borderShape
                .fill(Color(cgColor: stop.color))
                .strokeBorder(isSelected ? AnyShapeStyle(.clear) : AnyShapeStyle(.tertiary))
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                    in: borderShape.inset(by: -2)
                )
                .contentShape([.interaction, .focusEffect], borderShape)
                .frame(width: width)
                .position(x: geometry.size.width * stop.location, y: geometry.size.height / 2)
                .zIndex(isLastUpdated ? 2 : stop.location)
                .compositingGroup()
        }
    }

    private func update(with value: DragGesture.Value) {
        guard gradient.stops.indices.contains(index) else {
            return
        }

        var location = (value.location.x / geometry.size.width).clamped(to: 0...1)

        if
            !NSEvent.modifierFlags.contains(.command),
            abs(value.velocity.width) <= 75 && abs(location - 0.5) <= 0.025
        {
            location = 0.5
        }

        gradient.stops[index].location = location
        lastUpdated = index
    }
}
