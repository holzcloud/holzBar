//
//  FileDropDragSource.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The drag source of one stashed file: a transparent layer over a tile that begins a drag of the
/// file's address when the pointer is dragged.
///
/// The drag offers the copy operation only, so the receiver gets the file as it would from a drag
/// out of the Finder and the original stays where it is. The layer reads nothing, moves nothing
/// and deletes nothing; it hands over the address and reports whether the drop was completed.
struct FileDropDragSource: NSViewRepresentable {
    /// The address of the file to drag.
    let url: URL

    /// The image that follows the pointer.
    let icon: NSImage

    /// Called when the drag ended. `completed` is true when the receiver took the file.
    let onFinished: @MainActor (_ completed: Bool) -> Void

    func makeNSView(context: Context) -> FileDropDragSourceView {
        let view = FileDropDragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: FileDropDragSourceView, context: Context) {
        update(view)
    }

    private func update(_ view: FileDropDragSourceView) {
        view.url = url
        view.icon = icon
        view.onFinished = onFinished
        view.setAccessibilityElement(false)
    }
}

/// The view behind ``FileDropDragSource``. It is its own dragging source.
final class FileDropDragSourceView: NSView, NSDraggingSource {
    /// How far the pointer moves, in points, before a drag begins.
    private static let dragThreshold: CGFloat = 4

    var url: URL?
    var icon = NSImage()
    var onFinished: (@MainActor (_ completed: Bool) -> Void)?

    /// Where the pointer went down, in window coordinates, until a drag begins or the button
    /// goes up.
    private var mouseDownPoint: NSPoint?

    /// The hub's panel does not activate holzBar, so the first click already counts.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let url else {
            return
        }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else {
            return
        }
        mouseDownPoint = nil

        let side = CGFloat(DesignTokens.Hub.fileIconSize)
        let frame = NSRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(frame, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    // MARK: NSDraggingSource

    /// Copy only (P-04): the receiver gets a copy and the original stays where it is.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onFinished?(!operation.isEmpty)
    }
}
