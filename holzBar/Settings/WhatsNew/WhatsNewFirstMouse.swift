//
//  WhatsNewFirstMouse.swift
//  holzBar
//

import SwiftUI

/// Hosts its content in a view that takes the first click.
///
/// The What's New window opens above other apps without activating holzBar, so it is not the
/// key window when it appears. A click on an inactive window normally only brings it to the
/// front; with this host the first click on a tab or on Done acts at once, and the click also
/// makes the window key, so that Return and Escape work afterwards. A scene's own hosting view
/// cannot be replaced, which is why the content sits in a hosting view of its own.
struct WhatsNewFirstMouseHost<Content: View>: NSViewRepresentable {
    /// The size proposed when the surrounding layout leaves a dimension open.
    let idealSize: CGSize

    private let content: Content

    init(idealSize: CGSize, @ViewBuilder content: () -> Content) {
        self.idealSize = idealSize
        self.content = content()
    }

    func makeNSView(context: Context) -> WhatsNewHostingView {
        let view = WhatsNewHostingView(rootView: AnyView(content))
        // The size comes from the layout around it, not from the content.
        view.sizingOptions = []
        return view
    }

    func updateNSView(_ nsView: WhatsNewHostingView, context: Context) {
        nsView.rootView = AnyView(content)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WhatsNewHostingView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: idealSize)
    }
}

/// The hosting view of ``WhatsNewFirstMouseHost``.
///
/// A titled window, even one with a hidden title bar, can become key by default, so the
/// window needs no override of `canBecomeKey`; only the first click is accepted here.
final class WhatsNewHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
