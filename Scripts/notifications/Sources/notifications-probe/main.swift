//
//  main.swift
//  notifications
//
//  A throwaway spike that ships nothing. It watches the Notification Center process through
//  the Accessibility API and summarises what it can see of a banner; it prints no title,
//  body or app name unless `--show-values` is given, writes no file, uses no private API and
//  no network.
//

import Foundation
import NotificationProbeCore

let usage = """
usage: notifications-probe ax-banner [--trigger T1|T2] [--title TEXT] [--body TEXT] [--seconds N] [--label TEXT] [--show-values]
       notifications-probe selftest
       (--redact is the default; --title and --body are the known texts, compared inside the process)
"""

private func parse(_ arguments: [String]) -> Options? {
    guard let command = arguments.first, ["ax-banner", "selftest"].contains(command) else {
        return nil
    }
    var options = Options(command: command)
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--show-values":
            options.showValues = true
        case "--redact":
            options.showValues = false
        case "--label", "--trigger", "--title", "--body", "--seconds":
            index += 1
            guard index < arguments.count else {
                return nil
            }
            let value = arguments[index]
            switch argument {
            case "--label":
                options.label = value
            case "--trigger":
                guard ["T1", "T2"].contains(value) else {
                    return nil
                }
                options.trigger = value
            case "--title":
                options.title = value
            case "--body":
                options.body = value
            default:
                guard let number = Int(value), (1...600).contains(number) else {
                    return nil
                }
                options.seconds = number
            }
        default:
            return nil
        }
        index += 1
    }
    return options
}

guard let options = parse(Array(CommandLine.arguments.dropFirst())) else {
    Out.emit(usage)
    exit(2)
}

switch options.command {
case "selftest":
    exit(Selftest.run())
default:
    exit(Session.run(options))
}
