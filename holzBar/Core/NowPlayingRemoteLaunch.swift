//
//  NowPlayingRemoteLaunch.swift
//  holzBar
//

import Foundation

/// How the Now Playing bridge starts Apple's perl with the helper: the script, the arguments, the
/// environment and the limit of a line, and nothing else.
///
/// The bridge configures its process only from this plan, so it is the one place that decides
/// what perl runs. The script is a constant that only loads the helper's library and calls one
/// of two exported functions; it contains no `system`, `exec`, `open`, `eval` or `require`, no
/// backtick and no environment access. The function is one of a closed set. The path of the
/// helper must be absolute, inside the app's bundle once `.` and `..` are resolved, and end with
/// the framework's executable name. The environment is two fixed variables, so nothing the user
/// or another process set (such as `PERL5OPT` or `PERL5LIB`) reaches perl. This file does not
/// name perl itself: the bridge does, and it is the only file that may.
nonisolated enum NowPlayingRemoteLaunch {
    /// The two functions the helper exports for perl to call.
    enum Function: String, CaseIterable, Sendable {
        /// Prints the state once and returns.
        case get = "nowplaying_get"
        /// Prints the state, then every change, until the process ends.
        case stream = "nowplaying_stream"
    }

    /// The name of the helper's executable inside its framework.
    static let executableName = "NowPlayingRemote"

    /// The most bytes of one line of the helper's output (as the parser reads).
    static let maxLineBytes = NowPlayingRemoteMessage.maxLineBytes

    /// The whole environment of the child: the system tools and the plain locale.
    static let environment: [String: String] = [
        "PATH": "/usr/bin:/bin",
        "LC_ALL": "C",
    ]

    /// The perl program: loads the library at the path in its first argument, finds the function
    /// named by its second and calls it. Exits 3 when the library cannot be loaded and 4 when the
    /// function is missing, the codes of the helper's own errors.
    static let script = """
        use DynaLoader;
        my ($path, $name) = @ARGV;
        my $library = DynaLoader::dl_load_file($path, 0) or exit 3;
        my $symbol = DynaLoader::dl_find_symbol($library, $name) or exit 4;
        my $function = DynaLoader::dl_install_xsub("main::run", $symbol);
        &$function;
        """

    /// The arguments for perl, or `nil` when the helper's path is not acceptable.
    ///
    /// - Parameters:
    ///   - helperPath: The path of the helper's executable.
    ///   - bundlePath: The path of holzBar.app.
    ///   - function: The function to call.
    static func arguments(helperPath: String, bundlePath: String, function: Function) -> [String]? {
        guard !hasControlCharacter(helperPath), !hasControlCharacter(bundlePath),
              let bundle = components(of: bundlePath), !bundle.isEmpty,
              let helper = components(of: helperPath),
              helper.count > bundle.count,
              helper.starts(with: bundle),
              helper.last == executableName else {
            return nil
        }
        return ["-e", script, "--", "/" + helper.joined(separator: "/"), function.rawValue]
    }

    /// The parts of an absolute path with `.` and `..` resolved, or `nil` for a relative path or
    /// one that climbs above the root. Symbolic links are not followed.
    private static func components(of path: String) -> [String]? {
        guard path.hasPrefix("/") else {
            return nil
        }
        var result = [String]()
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." {
                continue
            }
            if part == ".." {
                guard !result.isEmpty else {
                    return nil
                }
                result.removeLast()
            } else {
                result.append(String(part))
            }
        }
        return result
    }

    private static func hasControlCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
