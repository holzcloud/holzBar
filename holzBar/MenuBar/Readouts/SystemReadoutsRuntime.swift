//
//  SystemReadoutsRuntime.swift
//  holzBar
//

import Foundation
import Observation
import SwiftUI

/// The running part of the System readouts module of the Notch hub: the readout tiles.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()`` when
/// either goes off. It is a consumer of the shared ``SystemMonitor`` and nothing more: it measures
/// nothing itself. While the hub is open and the Mac is in use it registers one visible consumer,
/// "tiles"; it unregisters when the hub closes, when it shuts down, and when the Mac sleeps, its
/// screens sleep, it locks or the session switches with the hub still open (``ReadoutVisibility``,
/// D-01, D-12, D-20). After the Mac wakes or unlocks it registers again, after the settle delay,
/// only if the hub is still open. With the hub closed nothing of the module is measured (MON-08).
///
/// The tiles show the readings as plain values through the rules of ``ReadoutTiles``; a missing,
/// stuck or impossible value shows an en dash (MON-09). Readings stay in memory and are never
/// logged or stored. The curve tiles (CPU, GPU, memory and network) also keep the last two minutes
/// of their value in a ``ReadoutHistory``, filled only by the deliveries of the open hub and kept
/// while the runtime lives, so a hub opened again within two minutes still has its earlier points
/// (MON-10, D-06, D-18).
@MainActor
@Observable
final class SystemReadoutsRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = ReadoutsSettings.moduleID

    /// The id of the tiles' consumer in the shared monitor.
    private static let consumerID = "tiles"

    let moduleID = SystemReadoutsRuntime.identifier
    let tint = HubTint.accent
    let offersTab = true

    /// The latest readings as the tile rules take them. Changing it redraws the tiles.
    private var reading = ReadoutTileInput()

    /// The last two minutes of the curve tiles. Changing it redraws the curves, which move left
    /// with every delivery.
    private var histories = Histories()

    @ObservationIgnored private weak var appState: AppState?
    /// The earlier readings, from which the loads and rates are made.
    @ObservationIgnored private var baseline = ReadoutBaseline()
    @ObservationIgnored private var visibility = ReadoutVisibility()
    /// What the registered consumer asks for, or `nil` while it is not registered.
    @ObservationIgnored private var registeredRequest: ReadoutRequest?
    /// The one-shot wait for the settle delay after the Mac wakes or unlocks.
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var pauseLoop: ObservationLoop?
    @ObservationIgnored private var choiceLoop: ObservationLoop?

    /// What the settings decide about the request: which tiles and how often.
    private struct Choice: Equatable {
        var tiles: [String]?
        var refreshSeconds: Int
        var readsGPU: Bool
    }

    /// The histories of the tiles that draw a curve; the disk and battery tiles have none (D-18).
    private struct Histories {
        var cpu = ReadoutHistory()
        var gpu = ReadoutHistory()
        var memory = ReadoutHistory()
        var download = ReadoutHistory()
        var upload = ReadoutHistory()
    }

    /// Whether this Mac has an internal battery, asked once.
    private static let hasInternalBattery = PowerSources.internalBattery() != nil

    /// The shortest height of the network curve's scale: 10 kB/s, so a trickle stays a trickle.
    private static let networkScale = ReadoutHistoryScale.rate(floor: 10_000)

    /// Follows the hub and the Mac's rest. Registers at once when the hub is open already (the hub
    /// creates the runtime after it opens, so the first open would be missed otherwise).
    init(appState: AppState) {
        self.appState = appState
        apply(.paused(appState.systemActivityMonitor.isPaused))
        apply(.shown(appState.notchHub.isOpen))
        pauseLoop = ObservationLoop.observe({ [weak appState] in
            appState?.systemActivityMonitor.isPaused ?? false
        }, onChange: { [weak self] isPaused in
            self?.apply(.paused(isPaused))
        })
        choiceLoop = ObservationLoop.observe({ [weak appState] in
            let readouts = appState?.settings.readouts
            return Choice(
                tiles: readouts?.enabledTiles,
                refreshSeconds: readouts?.tileRefreshSeconds ?? ReadoutTileRefresh.defaultSeconds,
                readsGPU: readouts?.readsGPU ?? false
            )
        }, onChange: { [weak self] _ in
            self?.choiceDidChange()
        })
    }

    // MARK: Hub interface

    var tiles: [HubTile] {
        guard let readouts = appState?.settings.readouts else {
            return []
        }
        var current = reading
        current.showsThermalLine = readouts.showsThermalLine
        // The GPU tile exists only with both its own switch and Read GPU load on (D-07); whether
        // the part switched itself off is the monitor's flag, never a value.
        current.gpuEnabled = readouts.readsGPU && readouts.isOn(.gpu)
        current.gpuUnavailable = appState?.systemMonitor.gpuIsUnavailable ?? false
        let locale = Locale.autoupdatingCurrent
        let now = ContinuousClock.now
        // The curves judge gaps by the interval the monitor really reads at, which Low Power Mode
        // doubles (H-01).
        let refreshSeconds = ReadoutSchedule.effectiveSeconds(
            forInterval: readouts.tileRefreshSeconds,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        return ReadoutTiles.contents(current, stored: readouts.enabledTiles).map {
            let drawn = curve(of: $0.kind, now: now, refreshSeconds: refreshSeconds)
            return ReadoutTileBuilder.tile(
                for: $0,
                input: current,
                rateUnit: readouts.rateUnit,
                locale: locale,
                history: drawn?.history,
                summary: drawn?.summary
            )
        }
    }

    /// The mini curve of a tile and what the last two minutes did, or `nil` for a tile without a
    /// curve. CPU, GPU and memory share a fixed scale from 0 to 100 percent; the network's
    /// download and upload share one scale from 0 to the window's peak.
    private func curve(
        of kind: ReadoutTileKind,
        now: ContinuousClock.Instant,
        refreshSeconds: Int
    ) -> (history: HubTileHistory, summary: ReadoutHistorySummary?)? {
        switch kind {
        case .cpu:
            return fraction(histories.cpu, now: now, refreshSeconds: refreshSeconds)
        case .gpu:
            return fraction(histories.gpu, now: now, refreshSeconds: refreshSeconds)
        case .memory:
            return fraction(histories.memory, now: now, refreshSeconds: refreshSeconds)
        case .network:
            let top = ReadoutHistory.top(
                of: [histories.download, histories.upload],
                scale: Self.networkScale,
                now: now
            )
            let history = HubTileHistory(
                primary: histories.download.segments(now: now, refreshSeconds: refreshSeconds, top: top),
                secondary: histories.upload.segments(now: now, refreshSeconds: refreshSeconds, top: top)
            )
            return (history, histories.download.summary(now: now, top: top))
        case .disk, .battery:
            return nil
        }
    }

    private func fraction(
        _ history: ReadoutHistory,
        now: ContinuousClock.Instant,
        refreshSeconds: Int
    ) -> (history: HubTileHistory, summary: ReadoutHistorySummary?) {
        (
            HubTileHistory(primary: history.segments(now: now, refreshSeconds: refreshSeconds, top: 1)),
            history.summary(now: now, top: 1)
        )
    }

    var preferredContentHeight: Double? {
        let count = tiles.count
        return count > 0 ? NotchHubGeometry.contentHeight(overviewTileCount: count) : nil
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(SystemReadoutsBody(runtime: self, host: host))
    }

    func hubVisibilityDidChange(isOpen: Bool) {
        apply(.shown(isOpen))
    }

    func shutDown() {
        pauseLoop?.cancel()
        pauseLoop = nil
        choiceLoop?.cancel()
        choiceLoop = nil
        settleTask?.cancel()
        settleTask = nil
        unregister()
        histories = Histories()
    }

    /// Whether the user switched at least one tile on.
    fileprivate var hasChosenTiles: Bool {
        guard let readouts = appState?.settings.readouts else {
            return false
        }
        return ReadoutTileKind.allCases.contains { kind in
            // The GPU tile exists only while Read GPU load is on.
            (kind != .gpu || readouts.readsGPU) && readouts.isOn(kind)
        }
    }

    // MARK: Visibility

    /// Feeds an event to the visibility rule and does what it says.
    private func apply(_ event: ReadoutVisibility.Event) {
        switch visibility.handle(event, at: .now) {
        case .keep:
            break
        case .register:
            settleTask?.cancel()
            settleTask = nil
            register()
        case .unregister:
            settleTask?.cancel()
            settleTask = nil
            unregister()
        case .waitUntil(let instant):
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                do {
                    try await Task.sleep(until: instant, clock: ContinuousClock())
                } catch {
                    return
                }
                self?.apply(.settleElapsed)
            }
        }
    }

    /// A tile switch or the refresh changed: while registered, ask the monitor again.
    private func choiceDidChange() {
        guard visibility.isVisible else {
            return
        }
        register()
    }

    // MARK: Monitor

    /// What the switched-on tiles need. Empty when no tile that reads is on.
    private func request() -> ReadoutRequest? {
        guard let readouts = appState?.settings.readouts else {
            return nil
        }
        var metrics = Set<ReadoutMetric>()
        if readouts.isOn(.cpu) {
            // The cluster line needs the load of every core, and the total is the sum of the
            // cores, so a chip with clusters reads the cores alone; a chip without clusters has
            // no such line and reads the total (L-02).
            metrics.insert(SystemSamplers.clusterLevels.count >= 2 ? .cpuCores : .cpu)
            if readouts.showsThermalLine {
                metrics.insert(.thermal)
            }
        }
        // The GPU is read only with its tile and the private-interface switch both on (D-07).
        if readouts.readsGPU, readouts.isOn(.gpu) {
            metrics.insert(.gpu)
        }
        if readouts.isOn(.memory) {
            metrics.formUnion([.memory, .swap, .memoryPressure])
        }
        if readouts.isOn(.network) {
            metrics.insert(.network)
        }
        if readouts.isOn(.disk) {
            metrics.insert(.diskSpace)
        }
        // A Mac without a battery never draws the tile, so it never follows power events either
        // (L-01).
        if readouts.isOn(.battery), Self.hasInternalBattery {
            metrics.insert(.power)
        }
        guard !metrics.isEmpty else {
            return nil
        }
        // A load and a rate are the difference of two readings.
        let needsBaseline = !metrics.isDisjoint(with: [.cpu, .cpuCores, .network])
        return ReadoutRequest(
            metrics: metrics,
            intervalSeconds: readouts.tileRefreshSeconds,
            needsBaseline: needsBaseline
        )
    }

    /// Registers the consumer with what the tiles need now, or removes it when no tile needs a
    /// reading. A request that did not change leaves the consumer as it is.
    private func register() {
        guard let appState else {
            return
        }
        guard let request = request() else {
            unregister()
            return
        }
        guard request != registeredRequest else {
            return
        }
        registeredRequest = request
        resetReadings()
        appState.systemMonitor.register(Self.consumerID, kind: .visible, request: request) { [weak self] sample in
            self?.receive(sample)
        }
    }

    /// Removes the consumer and forgets the readings, so the next opening starts from a baseline
    /// and shows an en dash until it has a value.
    private func unregister() {
        appState?.systemMonitor.unregister(Self.consumerID)
        registeredRequest = nil
        resetReadings()
    }

    /// Forgets the readings and the baseline. Whether this Mac has a battery stays known, so the
    /// tiles do not move when the hub opens again.
    private func resetReadings() {
        baseline.reset()
        reading = ReadoutTileInput(hasBattery: reading.hasBattery)
    }

    /// The used share of the memory from 0 to 1, or `nil` for a figure the tile calls impossible.
    private static func usedShare(_ memory: MemoryUse) -> Double? {
        guard memory.total > 0, memory.used <= memory.total else {
            return nil
        }
        return Double(memory.used) / Double(memory.total)
    }

    private func receive(_ sample: ReadoutSample) {
        guard registeredRequest != nil else {
            return
        }
        var next = reading
        let now = ContinuousClock.now
        var nextHistories = histories
        if registeredRequest?.metrics.contains(.cpuCores) == true {
            if sample.read.contains(.cpuCores) {
                // The load of each cluster between this reading and the one before it; none while
                // the levels do not partition the cores, so the tile shows the total only. The
                // total is the sum of the cores (L-02).
                let pair = baseline.coreTicks(sample.cpuCoreTicks)
                next.clusters = pair.flatMap {
                    CPUClusters.loads(levels: SystemSamplers.clusterLevels, previous: $0.previous, current: $0.current)
                } ?? []
                next.cpuLoad = pair.flatMap { CPUClusters.totalLoad(previous: $0.previous, current: $0.current) }
                nextHistories.cpu.append(next.cpuLoad, at: now)
            }
        } else if sample.read.contains(.cpu) {
            next.cpuLoad = baseline.cpuLoad(sample.cpuTicks)
            nextHistories.cpu.append(next.cpuLoad, at: now)
        }
        if sample.read.contains(.thermal) {
            next.thermal = sample.thermal
        }
        if sample.read.contains(.memory) {
            next.memory = sample.memory
            nextHistories.memory.append(next.memory.flatMap(Self.usedShare), at: now)
        }
        if sample.read.contains(.swap) {
            next.swap = sample.swap
        }
        if sample.read.contains(.memoryPressure) {
            next.pressure = sample.memoryPressure
        }
        if sample.read.contains(.network) {
            next.networkRates = baseline.networkRates(sample.network)
            nextHistories.download.append(next.networkRates?.first, at: now)
            nextHistories.upload.append(next.networkRates?.second, at: now)
        }
        if sample.read.contains(.gpu) {
            next.gpuPercent = sample.gpuPercent
            nextHistories.gpu.append(next.gpuPercent.map { Double($0) / 100 }, at: now)
        }
        if sample.read.contains(.diskSpace) {
            next.diskSpace = sample.diskSpace
        }
        if sample.read.contains(.power) {
            next.power = sample.power
            // The first reading that has a battery tells that this Mac has one.
            next.hasBattery = next.hasBattery || sample.power != nil
        }
        histories = nextHistories
        reading = next
    }
}

/// The body of the module's tab: the same tiles as the Overview shows for the module, in the same
/// four columns, or a compact empty state while no tile is switched on.
private struct SystemReadoutsBody: View {
    let runtime: SystemReadoutsRuntime
    let host: any HubHost

    var body: some View {
        if runtime.hasChosenTiles {
            ScrollView {
                HubTileGrid(tiles: runtime.tiles.map { (id: $0.key ?? runtime.moduleID, tile: $0) })
            }
            .scrollIndicators(.hidden)
        } else {
            EmptyState(
                systemImage: "gauge.with.dots.needle.67percent",
                title: Text("No tiles chosen"),
                message: Text("Switch tiles on in this module's settings."),
                actionTitle: "Open Settings",
                isCompact: true
            ) {
                host.openSettings(for: runtime.moduleID)
            }
        }
    }
}
