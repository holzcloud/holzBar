//
//  main.swift
//  now-playing
//
//  A throwaway spike that ships nothing (38-01): it measures which public source tells holzBar
//  what plays. The commands are `notify`, `mediaremote`, `keys`, `artwork`, `access` and
//  `selftest`. Titles, artists, albums and file names are never printed unless `--show-values`
//  is given; the probe writes no file and opens no network connection.
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

func usageError(_ message: String) -> Never {
    Output.emit(Options.usage)
    Output.emit("error: \(message)")
    exit(2)
}

switch options.command {
case "selftest":
    exit(Selftest.run() ? 0 : 4)
case "notify":
    NotifyListener.run(session: Session(options: options))
case "mediaremote":
    if let problem = MediaRemoteCheck.validate(options) { usageError(problem.message) }
    MediaRemoteCheck.run(session: Session(options: options))
case "keys":
    if let problem = LocalChecks.validateKeys(options) { usageError(problem.message) }
    LocalChecks.runKeys(session: Session(options: options))
case "artwork":
    if let problem = LocalChecks.validateArtwork(options) { usageError(problem.message) }
    LocalChecks.runArtwork(session: Session(options: options))
case "access":
    LocalChecks.runAccess(session: Session(options: options))
default:
    Output.emit(Options.usage)
    Output.emit("error: unknown command \(options.command)")
    exit(2)
}
