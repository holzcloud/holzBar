//
//  main.swift
//  now-playing
//
//  A throwaway spike that ships nothing (38-01): it measures which public source tells holzBar
//  what plays. The commands are `notify`, `mediaremote` and `selftest` here; the others are added by
//  the later tasks of the plan. Titles, artists, albums and file names are never printed unless
//  `--show-values` is given; the probe writes no file and opens no network connection.
//

import Foundation

let options: Options
switch Options.parse(Array(CommandLine.arguments.dropFirst())) {
case .success(let parsed):
    options = parsed
case .failure(let problem):
    Output.emit(Options.usage)
    Output.emit("error: \(problem.message)")
    exit(2)
}

switch options.command {
case "selftest":
    exit(Selftest.run() ? 0 : 4)
case "notify":
    NotifyListener.run(session: Session(options: options))
case "mediaremote":
    if let problem = MediaRemoteCheck.validate(options) {
        Output.emit(Options.usage)
        Output.emit("error: \(problem.message)")
        exit(2)
    }
    MediaRemoteCheck.run(session: Session(options: options))
default:
    Output.emit(Options.usage)
    Output.emit("error: unknown command \(options.command)")
    exit(2)
}
