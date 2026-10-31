//
//  FileDropIcons.swift
//  holzBar
//

import AppKit
import UniformTypeIdentifiers

/// The icons of the File drop tab's tiles.
///
/// A tile shows the icon of the file's type, worked out from the path alone: a folder's, or the
/// one for the path extension, or the generic one when there is none or it is unknown. No
/// file is opened or read to draw it, so a file on a network volume that cannot be reached
/// never holds the interface up, and macOS has no reason to ask for access to a folder.
@MainActor
enum FileDropIcons {
    /// The icon for the type of the file at an address.
    static func icon(for url: URL) -> NSImage {
        let type: UTType = if url.hasDirectoryPath {
            .folder
        } else {
            UTType(filenameExtension: url.pathExtension) ?? .data
        }
        return NSWorkspace.shared.icon(for: type)
    }
}
