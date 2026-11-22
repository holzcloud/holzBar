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
/// logged or stored.
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
    }

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
                refreshSeconds: readouts?.tileRefreshSeconds ?? ReadoutTileRefresh.defaultSeconds
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
        let locale = Locale.autoupdatingCurrent
        return ReadoutTiles.contents(current, stored: readouts.enabledTiles).map {
            ReadoutTileBuilder.tile(for: $0, input: current, rateUnit: readouts.rateUnit, locale: locale)
        }
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
    }

    /// Whether the user switched at least one tile on.
    fileprivate var hasChosenTiles: Bool {
        guard let readouts = appState?.settings.readouts else {
            return false
        }
        return ReadoutTileKind.allCases.contains { readouts.isOn($0) }
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
            metrics.insert(.cpu)
            if readouts.showsThermalLine {
                metrics.insert(.thermal)
            }
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
        if readouts.isOn(.battery) {
            metrics.insert(.power)
        }
        guard !metrics.isEmpty else {
            return nil
        }
        // A load and a rate are the difference of two readings.
        let needsBaseline = !metrics.isDisjoint(with: [.cpu, .network])
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

    private func receive(_ sample: ReadoutSample) {
        guard registeredRequest != nil else {
            return
        }
        var next = reading
        if sample.read.contains(.cpu) {
            next.cpuLoad = baseline.cpuLoad(sample.cpuTicks)
        }
        if sample.read.contains(.thermal) {
            next.thermal = sample.thermal
        }
        if sample.read.contains(.memory) {
            next.memory = sample.memory
        }
        if sample.read.contains(.swap) {
            next.swap = sample.swap
        }
        if sample.read.contains(.memoryPressure) {
            next.pressure = sample.memoryPressure
        }
        if sample.read.contains(.network) {
            next.networkRates = baseline.networkRates(sample.network)
        }
        if sample.read.contains(.diskSpace) {
            next.diskSpace = sample.diskSpace
        }
        if sample.read.contains(.power) {
            next.power = sample.power
            // The first reading that has a battery tells that this Mac has one.
            next.hasBattery = next.hasBattery || sample.power != nil
        }
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
