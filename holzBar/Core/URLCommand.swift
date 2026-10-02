//
//  URLCommand.swift
//  holzBar
//

import Foundation

/// A command another app sends to holzBar with a URL such as `holzbar://toggle/hidden`.
///
/// The host names the command and the path holds its arguments. The parse only reads the
/// URL; `URLCommands` decides what each command does and ignores unknown ones.
struct URLCommand: Equatable, Sendable {
    /// The command, lower-cased.
    let name: String

    /// The command's arguments: the path components, percent-decoded, case kept.
    let arguments: [String]

    /// Reads the command in `url`.
    ///
    /// - Parameters:
    ///   - url: The URL to read.
    ///   - scheme: The scheme holzBar accepts, compared case-insensitively.
    /// - Returns: `nil` for another scheme or a URL without a command.
    init?(url: URL, scheme: String) {
        guard
            let urlScheme = url.scheme,
            urlScheme.lowercased() == scheme.lowercased(),
            let host = url.host(percentEncoded: false),
            !host.isEmpty
        else {
            return nil
        }
        self.name = host.lowercased()
        self.arguments = url.path(percentEncoded: true)
            .split(separator: "/")
            .map { component in
                component.removingPercentEncoding ?? String(component)
            }
    }
}
