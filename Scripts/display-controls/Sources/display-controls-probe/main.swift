//
//  main.swift
//  display-controls
//
//  A throwaway spike that ships nothing. It reads and measures; it changes a level only with
//  `--allow-change`, restores it, prints no display or device name unless `--show-values` is
//  given, writes no file and uses no network.
//

import DisplayProbeCore
import Foundation

let usage = """
usage: display-controls-probe displays [--label TEXT]
       display-controls-probe brightness [--allow-change] [--set VALUE] [--label TEXT] [--show-values]
       display-controls-probe volume [--allow-change] [--label TEXT] [--show-values]
       display-controls-probe listen [--seconds N] [--label TEXT]
       display-controls-probe selftest
       (--redact is the default)
"""

private func parse(_ arguments: [String]) -> Options? {
    guard let command = arguments.first, ["displays", "brightness", "volume", "listen", "selftest"].contains(command) else {
        return nil
    }
    var options = Options(command: command)
    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--allow-change":
            options.allowChange = true
        case "--show-values":
            options.showValues = true
        case "--redact":
            options.showValues = false
        case "--label", "--set", "--seconds":
            index += 1
            guard index < arguments.count else {
                return nil
            }
            let value = arguments[index]
            if argument == "--label" {
                options.label = value
            } else if argument == "--set" {
                guard let number = Double(value), (0.05...1.0).contains(number) else {
                    return nil
                }
                options.setValue = number
            } else {
                guard let number = Int(value), number > 0 else {
                    return nil
                }
                options.seconds = number
            }
        default:
            return nil
        }
        index += 1
    }
    // A value is set by hand only together with the change option.
    if options.setValue != nil, !options.allowChange {
        return nil
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
