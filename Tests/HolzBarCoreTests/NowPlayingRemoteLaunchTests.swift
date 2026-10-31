//
//  NowPlayingRemoteLaunchTests.swift
//  holzBarTests
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("NowPlayingRemoteLaunch")
struct NowPlayingRemoteLaunchTests {
    private let bundle = "/Applications/holzBar.app"
    private let helper = "/Applications/holzBar.app/Contents/Frameworks/NowPlayingRemote.framework/Versions/A/NowPlayingRemote"

    @Test("An absolute helper path inside the bundle gives perl its script, the path and the function")
    func acceptedPath() {
        for function in NowPlayingRemoteLaunch.Function.allCases {
            let arguments = NowPlayingRemoteLaunch.arguments(helperPath: helper, bundlePath: bundle, function: function)
            #expect(arguments == ["-e", NowPlayingRemoteLaunch.script, "--", helper, function.rawValue])
        }
        #expect(NowPlayingRemoteLaunch.Function.get.rawValue == "nowplaying_get")
        #expect(NowPlayingRemoteLaunch.Function.stream.rawValue == "nowplaying_stream")
    }

    @Test("A path with dots that stays inside the bundle is resolved, and the resolved path is what perl gets")
    func resolvedPath() {
        let winding = "/Applications/holzBar.app/Contents/./Frameworks/../Frameworks/NowPlayingRemote.framework/Versions/A/NowPlayingRemote"
        let arguments = NowPlayingRemoteLaunch.arguments(helperPath: winding, bundlePath: bundle + "/", function: .stream)
        #expect(arguments?.dropFirst(3).first == helper)
    }

    @Test("A path outside the bundle, one that climbs out of it and a sibling folder are refused")
    func refusedLocations() {
        let refused = [
            "/tmp/NowPlayingRemote",
            "/Applications/holzBar.app/Contents/Frameworks/../../../Other.app/Contents/NowPlayingRemote",
            "/Applications/holzBar.app/../Evil/NowPlayingRemote",
            "/Applications/holzBar.appendix/Contents/Frameworks/NowPlayingRemote.framework/NowPlayingRemote",
            "/Applications/holzBar.app/NowPlayingRemote.framework/..",
            "/Applications/holzBar.app",
            "/../NowPlayingRemote",
        ]
        for path in refused {
            #expect(
                NowPlayingRemoteLaunch.arguments(helperPath: path, bundlePath: bundle, function: .get) == nil,
                "path \(path)"
            )
        }
    }

    @Test("A relative path, a control character and a wrong file name are refused")
    func refusedShapes() {
        let refused = [
            "Contents/Frameworks/NowPlayingRemote.framework/Versions/A/NowPlayingRemote",
            "",
            helper + "\n",
            "/Applications/holzBar.app/Contents/Frameworks/NowPlayingRemote.framework/Versions/A/NowPlaying\u{0}Remote",
            "/Applications/holzBar.app/Contents/Frameworks/NowPlayingRemote.framework/Versions/A/Other",
            "/Applications/holzBar.app/Contents/Frameworks/NowPlayingRemote.framework/Versions/A/NowPlayingRemote2",
        ]
        for path in refused {
            #expect(
                NowPlayingRemoteLaunch.arguments(helperPath: path, bundlePath: bundle, function: .get) == nil,
                "path \(path.debugDescription)"
            )
        }
        #expect(NowPlayingRemoteLaunch.arguments(helperPath: helper, bundlePath: "", function: .get) == nil)
        #expect(NowPlayingRemoteLaunch.arguments(helperPath: helper, bundlePath: "holzBar.app", function: .get) == nil)
        #expect(NowPlayingRemoteLaunch.arguments(helperPath: helper, bundlePath: "/", function: .get) == nil)
    }

    @Test("The environment is exactly PATH and LC_ALL, and a line is at most 64 KB")
    func environmentAndLimit() {
        #expect(Set(NowPlayingRemoteLaunch.environment.keys) == ["PATH", "LC_ALL"])
        #expect(NowPlayingRemoteLaunch.environment["PATH"] == "/usr/bin:/bin")
        #expect(NowPlayingRemoteLaunch.environment["LC_ALL"] == "C")
        #expect(NowPlayingRemoteLaunch.maxLineBytes == 65_536)
        #expect(NowPlayingRemoteLaunch.Function.allCases.count == 2)
    }

    @Test("The script loads a library and calls a function, and can do nothing else")
    func scriptContent() {
        let script = NowPlayingRemoteLaunch.script
        for needed in ["dl_load_file", "dl_find_symbol", "dl_install_xsub", "exit 3", "exit 4"] {
            #expect(script.contains(needed), "needs \(needed)")
        }
        for forbidden in ["system", "exec", "open", "eval", "require", "`", "%ENV", "$ENV", "qx", "fork", "kill", "unlink"] {
            #expect(!script.contains(forbidden), "must not contain \(forbidden)")
        }
        #expect(!script.contains("perl"))
    }
}
