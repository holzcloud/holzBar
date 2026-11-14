//
//  IslandView.swift
//  holzBar
//

import SwiftUI

/// The content of the Notch hub's panel: one pure black island that grows out of the notch, and
/// the selected module's content on it (concept section 10b).
///
/// The island is one shape with no glass, no gradient and no stroke, black in every appearance, so
/// that it and the camera housing are one object. Its width and height each follow their own
/// animation (``IslandPresentation``). The content sits at a rectangle of the layout and never
/// stretches with the shape: it appears a moment after the shape starts to grow, from a blur and a
/// smaller scale; under Reduce Motion nothing blurs or scales and only the opacity changes.
///
/// The island shows one module at a time. Every body fills the content rectangle and scrolls
/// inside it when it needs more. Choosing another module cross-fades the content while it rises a
/// few points; when the new content has another height the shape follows with the opening's
/// spring, and the module row rides on its lower edge. Under Reduce Motion the height changes at
/// once and the content only fades. The arrow keys step through the modules while the hub has the
/// keyboard, and Esc closes it.
///
/// While the hub is closed and something is live, the same shape is the notch widened at menu bar
/// height and ``IslandLiveView`` draws the top activity on it. VoiceOver is told once when a new
/// activity comes to the top.
///
/// A context line below the notch says why the module in front is in front, in one fixed sentence
/// per reason (``HubContext/Reason``) that never names an event, a track or a file. VoiceOver is
/// told it once for each opening.
struct IslandView: View {
    let presentation: IslandPresentation
    let model: NotchHubModel
    let host: any HubHost

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var hasKeyboardFocus: Bool

    /// The opening whose context line VoiceOver was last told.
    @State private var announcedOpening = 0

    /// The live activity VoiceOver was last told about.
    @State private var announcedLiveKey: String?

    private var canvasWidth: CGFloat {
        CGFloat(presentation.canvas.width)
    }

    private var canvasHeight: CGFloat {
        CGFloat(presentation.canvas.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            closingLayer
            island
            topRow
            contextLine
            content
            moduleRow
            liveContent
                .animation(presentation.liveContentAnimation, value: presentation.showsLiveContent)
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .focusable(presentation.takesKeyboard)
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            step(by: -1)
        }
        .onKeyPress(.rightArrow) {
            step(by: 1)
        }
        .onKeyPress(.escape) {
            host.close()
            return .handled
        }
        .onAppear {
            if presentation.takesKeyboard {
                hasKeyboardFocus = true
            }
            announceContextLine()
            announceLiveActivity()
        }
        .onChange(of: presentation.openingCount) {
            // A hub that opens again while it closes keeps this view.
            announceContextLine()
        }
        .onChange(of: presentation.liveBoard?.compact?.key) {
            announceLiveActivity()
        }
        .onChange(of: presentation.takesKeyboard) { _, takesKeyboard in
            // A hub that opens again while it closes keeps this view.
            if takesKeyboard {
                hasKeyboardFocus = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notch hub"))
    }

    /// Tells VoiceOver why the module is in front, once for each opening; a later change of the
    /// line during the same opening is not announced.
    private func announceContextLine() {
        guard presentation.openingCount != announcedOpening, let reason = model.frontReason else {
            return
        }
        announcedOpening = presentation.openingCount
        AccessibilityNotification.Announcement(reason.line).post()
    }

    /// Tells VoiceOver once that an activity started or came to the top. The activity's own title
    /// is read; an alert that announces itself is not read twice.
    private func announceLiveActivity() {
        guard let activity = presentation.liveBoard?.compact else {
            announcedLiveKey = nil
            return
        }
        guard activity.key != announcedLiveKey else {
            return
        }
        announcedLiveKey = activity.key
        if !activity.announcesItself {
            AccessibilityNotification.Announcement(activity.title).post()
        }
    }

    /// Moves to the next or previous tab, wrapping.
    private func step(by delta: Int) -> KeyPress.Result {
        model.select(HubTabStrip.step(from: model.selectedID, by: delta, in: model.allTabIDs))
        return .handled
    }

    // MARK: The island

    /// The transparent rest of the panel, under the island: a click in the margin of a transition
    /// or in a concave cut-out closes the hub instead of being swallowed. At rest the panel is the
    /// shape, so there is almost nothing of it.
    private var closingLayer: some View {
        Color.clear
            .frame(width: canvasWidth, height: canvasHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                host.close()
            }
            .accessibilityHidden(true)
    }

    /// The black shape, centred at the top of the canvas, with the lower-edge line under Increase
    /// Contrast. The width, the height and the corners each carry the animation that belongs to
    /// them, so the island can widen with one spring and deepen with another. Its hit area is the
    /// shape itself: a click in a concave corner or beside a rounded bottom corner never reaches
    /// the island, and the layer under it closes the hub.
    private var island: some View {
        let topRadius = CGFloat(presentation.topRadius)
        let bottomRadius = CGFloat(presentation.bottomRadius)
        return ZStack {
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(HolzBarTheme.Island.surface)
            if contrast == .increased {
                IslandLowerEdge(topRadius: topRadius, bottomRadius: bottomRadius)
                    .stroke(HolzBarTheme.Island.edge, lineWidth: HolzBarTheme.Island.edgeWidth)
            }
        }
        .animation(presentation.heightAnimation, value: presentation.bottomRadius)
        .frame(width: CGFloat(presentation.width))
        .animation(presentation.widthAnimation, value: presentation.width)
        .frame(height: CGFloat(presentation.height))
        .animation(presentation.heightAnimation, value: presentation.height)
        .contentShape(IslandShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .offset(x: CGFloat(presentation.centreX - (presentation.canvas.x + presentation.canvas.width / 2)))
        .animation(presentation.widthAnimation, value: presentation.centreX)
        .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
    }

    // MARK: The content

    /// The status pills beside the notch and the settings gear below it, from the top of the
    /// shape down to the end of the context-line row. It shows only while the hub is open, never in
    /// the live state.
    @ViewBuilder
    private var topRow: some View {
        if let layout = presentation.layout {
            let area = NotchHubGeometry.Rect(
                x: layout.shape.x,
                y: layout.shape.y,
                width: layout.shape.width,
                height: layout.contextRow.maxY - layout.shape.y
            )
            staged(IslandTopRowView(model: model, layout: layout, host: host), in: area, alignment: .topLeading)
        }
    }

    /// The context line, centred in its row below the notch and clear of the gear at the row's end.
    @ViewBuilder
    private var contextLine: some View {
        if let area = presentation.layout?.contextRow, let reason = model.frontReason {
            let room = CGFloat(area.width) - 2 * (HolzBarTheme.Island.gearSize + HolzBarTheme.Spacing.xs)
            staged(
                IslandContextLine(line: reason.line, maxWidth: max(room, 0)),
                in: area,
                alignment: .center
            )
        }
    }

    /// The selected module's content or the Overview, in the layout's content rectangle.
    @ViewBuilder
    private var content: some View {
        if let area = presentation.layout?.content {
            staged(selectedContent, in: area, alignment: .top)
        }
    }

    /// The row of module buttons, in the layout's module row rectangle; it comes and goes with
    /// the content.
    @ViewBuilder
    private var moduleRow: some View {
        if let area = presentation.layout?.moduleRow {
            // The row's place is the animated one, so it rides on the shape's lower edge.
            staged(
                IslandModuleRowView(model: model, fit: presentation.rowFit),
                in: area,
                alignment: .center,
                top: presentation.moduleRowY
            )
        }
    }

    /// The live state: the top activity's symbol and short value on the widened notch, over the
    /// shape's own rectangle. It shows only while the hub is closed.
    @ViewBuilder
    private var liveContent: some View {
        if presentation.showsLiveContent, let board = presentation.liveBoard, let live = presentation.liveLayout {
            IslandLiveView(
                board: board,
                layout: live,
                origin: CGPoint(
                    x: live.shape.x - presentation.canvas.x,
                    y: live.shape.y - presentation.canvas.y
                )
            ) {
                presentation.onLiveTap?()
            }
            // It fades in and out with the animation of ``IslandPresentation/liveContentAnimation``.
            .transition(.opacity)
        }
    }

    /// Places a part of the island at its rectangle of the layout, relative to the canvas, and
    /// stages it with the content: it appears after the shape starts to grow, from a blur and a
    /// smaller scale, and leaves first.
    ///
    /// A part that rides on the shape's lower edge passes its own `top`, in display coordinates,
    /// instead of the rectangle's, and it moves with the animation of
    /// ``IslandPresentation/rowAnimation``.
    private func staged(
        _ part: some View,
        in area: NotchHubGeometry.Rect,
        alignment: Alignment,
        top: Double? = nil
    ) -> some View {
        let isShown = presentation.contentShown
        return part
            .frame(width: CGFloat(area.width), height: CGFloat(area.height), alignment: alignment)
            .blur(radius: reduceMotion || isShown ? 0 : HolzBarTheme.Island.contentBlur)
            .scaleEffect(reduceMotion || isShown ? 1 : HolzBarTheme.Island.contentScale, anchor: .top)
            .opacity(isShown ? 1 : 0)
            .animation(presentation.contentAnimation, value: isShown)
            .offset(
                x: CGFloat(area.x - presentation.canvas.x),
                y: CGFloat((top ?? area.y) - presentation.canvas.y)
            )
            .animation(presentation.rowAnimation, value: top)
            // A part never fades in as a view that is inserted; only its opacity moves.
            .transition(.identity)
    }

    /// The Overview, or the selected module's body, one at a time. Both fill the content area, and
    /// a body that needs more scrolls inside it. Choosing another module cross-fades them: the new
    /// content rises into place while it fades in, the old one fades out. Under Reduce Motion
    /// the content only fades.
    private var selectedContent: some View {
        ZStack(alignment: .top) {
            selectedBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(model.selectedID)
                .transition(switchTransition)
        }
        .animation(reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandSwitch, value: model.selectedID)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private var selectedBody: some View {
        if let runtime = model.selectedRuntime {
            runtime.makeBody(host: host)
        } else {
            HubOverviewView(model: model, host: host)
        }
    }

    /// The new content fades in while it rises into place; the old content only fades out.
    private var switchTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: DesignTokens.Island.switchRise)),
            removal: .opacity
        )
    }
}

/// The context line: a small sparkles symbol and one fixed sentence in quiet white. It stays one
/// line, shrinks a little before it truncates, and its tooltip carries the full text.
private struct IslandContextLine: View {
    let line: String
    let maxWidth: CGFloat

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(HolzBarTheme.Island.contextSymbolFont)
                .accessibilityHidden(true)
            Text(line)
                .font(HolzBarTheme.Island.contextFont)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(HolzBarTheme.Island.contextText)
        .frame(maxWidth: maxWidth)
        .help(line)
    }
}

/// The sentence that says why a module is in front. Never a name, a title or a file.
private extension HubContext.Reason {
    var line: String {
        switch self {
        case .meetingSoon: String(localized: "In front because your meeting starts soon")
        case .meetingNow: String(localized: "In front because your meeting is on")
        case .liveActivity: String(localized: "In front because something is running")
        case .music: String(localized: "In front because music is playing")
        case .overview: String(localized: "Overview: nothing is active right now")
        case .chosen: String(localized: "Chosen by you")
        }
    }
}

/// Hosts ``IslandView`` in the panel.
///
/// The panel's frame comes from the geometry, so the view never sizes the window; the safe area
/// is zero, because the island lies over the notch's strip. It adds no shadow work of its own:
/// the window's shadow is handled where the frame is (concept section 10b).
final class IslandHostingView: NSHostingView<IslandView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(view: IslandView) {
        super.init(rootView: view)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: IslandView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
