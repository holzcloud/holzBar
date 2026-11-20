//
//  DDCBus.swift
//  holzBar
//

import Foundation

/// One control of an external monitor as the monitor reports it: the raw value now and the
/// largest raw value it accepts.
nonisolated struct DDCControlValue: Equatable, Sendable {
    /// The control.
    let control: DDCControl
    /// The raw value now.
    let current: UInt16
    /// The largest raw value the monitor accepts, never 0.
    let maximum: UInt16
}

/// What a survey found out about one display.
nonisolated struct DDCDisplayReport: Equatable, Sendable {
    /// What a display answered, or why it was not asked.
    enum Outcome: Equatable, Sendable {
        /// The display answered; these are the controls that read.
        case answered([DDCControlValue])
        /// The display gave no answer. `tried` is `false` when it was not asked, because no DDC
        /// channel could be paired with it.
        case noAnswer(tried: Bool)
        /// The display is identical to another one and cannot be told apart, so it is never
        /// read or written.
        case indistinguishable
    }

    /// The display's identifier.
    let id: UInt32
    /// What was found.
    let outcome: Outcome
}

/// Talks DDC/CI to external monitors, one transaction at a time.
///
/// Every I2C transfer blocks for tens of milliseconds, so the bus runs on its own serial queue,
/// never on the main actor or the cooperative pool. A transfer has no suspension point between
/// its writes and its read, so two transfers can never interleave; waits are `usleep` on that
/// queue. Only `Sendable` value structs leave the actor: the services, which are not
/// `Sendable`, stay inside it. Nothing is logged or stored here, and display names never enter
/// it. The functions it calls are those of ``IOAVServiceBridge``, which is the only file that
/// names them, and nothing reaches it while the module's switch is off.
actor DDCBus {
    /// The queue every transfer runs on, and the actor's executor.
    private nonisolated let queue = DispatchSerialQueue(label: "com.holzcloud.holzBar.DDCBus", qos: .userInitiated)

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Whether this Mac can use the bus: Apple silicon only. On another Mac nothing is looked
    /// up and ``load()`` answers that the symbol is missing.
    nonisolated static var supportsThisMac: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    /// The outcome of the one attempt to load, kept for the life of the bus.
    private var loaded: (result: PrivateFeatureGate.LoadResult, functions: IOAVServiceBridge.Functions?)?

    /// The channels found by the last walk of the registry.
    private var endpoints = [IOAVServiceBridge.Endpoint]()

    /// The display identifiers of the last survey; the registry is walked again only when they
    /// change, because every walk creates a service per display.
    private var surveyedIDs: Set<UInt32>?

    /// The pairing of the last survey: display to index in ``endpoints``, and the ties.
    private var pairing = DDCDisplayMatch.Result(pairs: [:], indistinguishable: [])

    /// The controls read successfully in this session, with the maximum read. A control is
    /// written only after it was read, and never above its maximum.
    private var readControls = [UInt32: [DDCControl: UInt16]]()

    /// Looks the functions up, the first time only; later calls return the same result. On a
    /// Mac that is not Apple silicon nothing is looked up. The framework is always present, so
    /// the answer is `.loaded` or `.symbolMissing`.
    func load() -> PrivateFeatureGate.LoadResult {
        if let loaded {
            return loaded.result
        }
        let functions = Self.supportsThisMac ? IOAVServiceBridge.resolve() : nil
        let attempt = (result: functions == nil ? PrivateFeatureGate.LoadResult.symbolMissing : .loaded, functions: functions)
        loaded = attempt
        return attempt.result
    }

    /// Pairs the given displays with DDC channels and reads the brightness of each paired
    /// display. The registry is walked the first time and again only when the set of display
    /// identifiers differs from the last survey. Stops early when the calling task is
    /// cancelled.
    func survey(_ displays: [DDCDisplayMatch.Display]) -> [DDCDisplayReport] {
        guard let functions = loaded?.functions else {
            return displays.map { DDCDisplayReport(id: $0.id, outcome: .noAnswer(tried: false)) }
        }
        let identifiers = Set(displays.map(\.id))
        if surveyedIDs != identifiers {
            endpoints = IOAVServiceBridge.endpoints(using: functions)
            surveyedIDs = identifiers
            readControls = [:]
        }
        pairing = DDCDisplayMatch.match(displays: displays, framebuffers: endpoints.map(\.framebuffer))

        var reports = [DDCDisplayReport]()
        for display in displays {
            guard !Task.isCancelled else {
                break
            }
            let outcome: DDCDisplayReport.Outcome
            if pairing.indistinguishable.contains(display.id) {
                outcome = .indistinguishable
            } else if pairing.pairs[display.id] != nil {
                if let value = read(.brightness, of: display.id) {
                    outcome = .answered([value])
                } else {
                    outcome = .noAnswer(tried: true)
                }
            } else {
                outcome = .noAnswer(tried: false)
            }
            reports.append(DDCDisplayReport(id: display.id, outcome: outcome))
        }
        return reports
    }

    /// Reads a control of a display. Tries up to ``DDCTiming/attempts`` transfers and accepts
    /// the first reply that ``DDCReply`` validates; a control the monitor says it does not have
    /// ends the read at once. Returns `nil` when the display is not paired, the functions are not
    /// loaded or no transfer gave a value.
    func read(_ control: DDCControl, of display: UInt32) -> DDCControlValue? {
        guard let functions = loaded?.functions, let endpoint = endpoint(for: display) else {
            return nil
        }
        let request = DDCPacket.getRequest(control)
        for attempt in 0..<DDCTiming.attempts {
            guard !Task.isCancelled else {
                return nil
            }
            if attempt > 0 {
                usleep(DDCTiming.retryWait)
            }
            guard let bytes = IOAVServiceBridge.transfer(
                request,
                replyLength: DDCPacket.getReplyLength,
                endpoint: endpoint,
                functions: functions
            ) else {
                continue
            }
            switch DDCReply.parse(bytes, expecting: control) {
            case let .value(current, maximum):
                readControls[display, default: [:]][control] = maximum
                return DDCControlValue(control: control, current: current, maximum: maximum)
            case .unsupported:
                return nil
            case .nullMessage, .invalid:
                continue
            }
        }
        return nil
    }

    /// The channel paired with a display, or `nil` when it has none.
    private func endpoint(for display: UInt32) -> IOAVServiceBridge.Endpoint? {
        guard let index = pairing.pairs[display], endpoints.indices.contains(index) else {
            return nil
        }
        return endpoints[index]
    }
}
