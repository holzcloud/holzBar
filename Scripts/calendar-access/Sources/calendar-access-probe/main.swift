//
//  main.swift
//  calendar-access
//
//  The probe is an accessory app bundle (see `build-probe-app.sh`): the Calendar permission
//  belongs to the process that asks, so only a bundle with its own identifier measures what
//  holzBar would get. It reads counts only, prints no event text and writes no file.
//

import AppKit
import CalendarAccessCore

let options: Options
switch Options.parse(Array(CommandLine.arguments.dropFirst()), bundleIdentifier: Bundle.main.bundleIdentifier) {
case .success(let parsed):
    options = parsed
case .failure(let problem):
    Output.emit("usage: calendar-access-probe variant=v1|v2|v3|v4 [watch=SECONDS] [wait=SECONDS] [alert=off]")
    Output.emit("       calendar-access-probe --selftest | --verdict FILE...")
    Output.emit("error: \(problem.message)")
    exit(2)
}

switch options.mode {
case .selftest:
    exit(Probe.selftest() ? 0 : 4)
case .verdict(let files):
    exit(Probe.verdict(ofFiles: files))
case .run(let variant):
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = ProbeDelegate(variant: variant, options: options)
    app.delegate = delegate
    app.run()
}
