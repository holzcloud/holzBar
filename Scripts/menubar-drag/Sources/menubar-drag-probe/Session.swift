//
//  Session.swift
//  holzBar
//

import AppKit
import MenuBarDragCore

/// One live run of a1 or a2: it tells the maintainer what to do, writes every line through the
/// redactor, counts the gestures and ends the run the same way whatever ends it.
final class Session {
    private let options: Options
    private let generation: Generation
    private var redactor: Redactor
    private var summary = RunSummary()
    private var count = 0
    private var finished = false
    private var stop: () -> Int? = { nil }
    private var drain: () async -> Void = {}

    /// The mechanism that runs, `a1` or `a2`.
    private var mechanism: String {
        options.command
    }

    init(options: Options, generation: Generation) {
        self.options = options
        self.generation = generation
        redactor = Redactor(enabled: options.redact)
    }

    /// Writes the header and the steps and remembers how to stop the tap.
    ///
    /// - Parameters:
    ///   - snapshot: The bar as read at the start; the steps name concrete items from it.
    ///   - stop: Takes the tap out of the event stream and returns its longest callback in
    ///     microseconds.
    ///   - drain: Waits until the reads after the last drop are done.
    func start(
        mode: String,
        snapshot: BarSnapshot,
        stop: @escaping () -> Int?,
        drain: @escaping () async -> Void
    ) {
        self.stop = stop
        self.drain = drain
        write(ProbeOutput.probeLine(mode: mode, label: options.label))
        write(ProbeOutput.systemLine(generation: generation))

        let candidates = snapshot.items.filter { item in
            item.counts && item.kind == .app
                && (generation == .macOS27 || snapshot.positionalSection(of: item) == .visible)
        }
        guard candidates.count >= 2 else {
            print("STEP need at least two app items in the visible part of the bar: start some menu bar apps and run again")
            exit(5)
        }
        let first = redactor.shownID(candidates[0].id)
        let second = redactor.shownID(candidates[1].id)
        for step in steps(first: first, second: second, snapshot: snapshot) {
            print("STEP " + step)
        }
    }

    private func steps(first: String, second: String, snapshot: BarSnapshot) -> [String] {
        var steps = [
            "S0 once, as a baseline: drag \(first) while holding Command, as macOS allows today",
            "S1+S3 three times: drag \(first) to the right of \(second) without holding Command, then back",
        ]
        if generation == .macOS27 {
            steps.append("S2 three times: drag \(first) and release it over holzBar's icon (macOS 27 draws no divider)")
        } else {
            steps.append(
                "S2 three times: drag \(first) to the left of holzBar's hidden divider (holzBar shows the hidden "
                    + "section when the drag starts if \"Show all sections when ⌘ Command + dragging menu bar items\" "
                    + "is on; the divider style must be Chevron)"
            )
            if snapshot.items.contains(where: { $0.kind == .alwaysHiddenDivider && $0.counts }) {
                steps.append("S2b: drag it to the left of the always-hidden divider")
            }
        }
        if mechanism == "a2" {
            steps.append("S4 five times: click \(second) once; its menu should open; close it with Escape")
            steps.append(
                "S5 three times: press on \(second), keep the button down, move down into its menu and release on an entry"
            )
            steps.append(
                "S6 once: press on \(second) and, keeping the button down, slide sideways to the next item; "
                    + "note what happens (today this opens the next menu)"
            )
        }
        steps.append("afterwards: put the items back in holzBar's Settings > Menu Bar Layout")
        return steps
    }

    private func write(_ line: ReportLine) {
        print(line.text)
    }

    /// An intent as the report shows it, with ids and owners through the redactor.
    private func shown(_ intent: DropIntent) -> String {
        intent.rendered(
            generation: generation,
            shownID: { redactor.shownID($0) },
            shownOwner: { redactor.shownOwner($0) }
        )
    }

    /// Writes the RESULT line of one measured drag and counts it.
    func record(_ record: GestureRecord) {
        count += 1
        let line = ProbeOutput.resultLine(
            mech: record.mechanism,
            n: count,
            dragged: redactor.shownID(record.dragged.id),
            result: record.result,
            drop: record.dropX,
            commandHeld: record.commandHeld,
            intent: shown(record.intent),
            landed: record.landed,
            executed: record.executed,
            retried: record.retried,
            tapMaxUs: record.tapMaxUs
        )
        write(line)
        summary.add(record.result, landed: record.landed, refused: record.intent.isRefused)
        finishIfDone()
    }

    /// Writes the CLICK line of one replayed press and counts it.
    func recordClick(_ record: ClickRecord) {
        count += 1
        write(ProbeOutput.clickLine(
            mech: record.mechanism,
            n: count,
            item: redactor.shownID(record.item.id),
            record: record
        ))
        summary.addClick(delayMs: record.replayDelayMs)
        finishIfDone()
    }

    func recordSkip(_ reason: String) {
        var line = ReportLine("SKIP")
        line.add("reason", reason)
        write(line)
    }

    private func finishIfDone() {
        if count >= options.gestures {
            finish()
        }
    }

    /// Ends the run after the time limit: no new press is taken, the reads of the last drop are
    /// waited for, then the run ends as always.
    func finishAfterTimeLimit() async {
        _ = stop()
        await drain()
        finish()
    }

    /// Ends the run, once: stops the tap, writes SUMMARY, asks the questions when a person sits at
    /// a terminal, writes ANSWER and the end line, and exits 0.
    func finish() {
        guard !finished else {
            return
        }
        finished = true
        summary.tapMaxUs = stop()
        write(summary.line(mechanism: mechanism, generation: generation))

        let asked = Question.questions(for: mechanism)
        var answers = [Question: String]()
        if isatty(STDIN_FILENO) != 0 {
            print("Answer in this terminal: y or n, Return skips.")
            for question in asked {
                print(question.text)
                answers[question] = readLine() ?? ""
            }
        }
        write(Question.answerLine(asked: asked, answers: answers))
        print(endLine)
        exit(0)
    }
}
