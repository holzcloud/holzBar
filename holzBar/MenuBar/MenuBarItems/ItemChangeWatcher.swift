//
//  ItemChangeWatcher.swift
//  holzBar
//

import AppKit
@preconcurrency import ApplicationServices
import OSLog

/// Shows a hidden item for a moment when its title or value changes, for the items the
/// user marked "Show When It Changes" (THAW-12).
///
/// `AXObserver`s for the processes that own marked items listen for
/// `kAXTitleChangedNotification` and `kAXValueChangedNotification` on those items'
/// elements only; they are registered off the main thread and their run-loop sources run
/// on the main run loop. The observers follow the item list (they are set up again when it
/// changes) and nothing runs while no item is marked. Each notification passes ``ChangeReveal``'s debounce and rate limit; a due item
/// is shown for 5 seconds (`MenuBarManager.revealBriefly(itemKey:)`). No timer and no
/// polling: one bounded wait per batch of changes, and a few bounded retries for a marked
/// item whose app did not answer yet.
///
/// An item whose app only swaps its picture may post nothing, and is then never shown.
@MainActor
final class ItemChangeWatcher {
    /// The watcher the observers' callback reports to.
    fileprivate static weak var current: ItemChangeWatcher?

    /// The identity keys of the marked items, as stored.
    private var keys = Set<String>()

    /// The shared app state.
    private weak var appState: AppState?

    /// Follows the item list.
    private var cacheObserver: ObservationLoop?

    /// The observers of the registrations that were applied.
    private var observers = [AXObserver]()

    /// The observed elements with their items' keys, by process identifier.
    private var watched = [pid_t: [(element: AXUIElement, key: String)]]()

    /// The marked items in the menu bar, the observed ones among them, and which
    /// registration is current.
    private var watchList = ItemChangeWatchList()

    /// The one wait before the items that were not observed are tried again; a changed
    /// list cancels it.
    private var retryTask: Task<Void, Never>?

    /// The debounce and rate limit.
    private var changeReveal = ChangeReveal()

    /// The one wait until the next change is due.
    private var dueTask: Task<Void, Never>?

    private nonisolated static let logger = Logger(category: "ItemChangeWatcher")

    /// Starts following the marked items.
    func performSetup(with appState: AppState) {
        self.appState = appState
        Self.current = self
        keys = Set(Defaults.stringArray(forKey: .revealOnChangeItems) ?? [])
        let itemManager = appState.itemManager
        cacheObserver = ObservationLoop.observe { itemManager.itemCache } onChange: { [weak self] _ in
            self?.updateObservers()
        }
        updateObservers()
    }

    // MARK: Marked Items

    /// Whether the item is marked "Show When It Changes".
    func isRevealedOnChange(_ item: MenuBarItem) -> Bool {
        guard let itemManager = appState?.itemManager else {
            return false
        }
        let key = itemManager.identityKey(for: item)
        return keys.contains { itemManager.storedIdentityKey($0) == key }
    }

    /// Marks or unmarks the item.
    func setRevealedOnChange(_ isOn: Bool, for item: MenuBarItem) {
        guard let itemManager = appState?.itemManager else {
            return
        }
        let key = itemManager.identityKey(for: item)
        keys = keys.filter { itemManager.storedIdentityKey($0) != key }
        if isOn {
            keys.insert(key)
        }
        Defaults.set(keys.sorted(), forKey: .revealOnChangeItems)
        appState?.settingsSync.settingsDidChange()
        updateObservers()
    }

    // MARK: Observers

    /// Observes exactly the marked items that are in the menu bar now.
    ///
    /// The lookups and registrations ask the items' apps, and a busy app would hold the
    /// main thread, and on macOS 27 the click tap and every click on the Mac with it, so they
    /// run on ``registrationQueue``. The result is applied here, unless the list changed
    /// meanwhile.
    ///
    /// - Parameter retrying: Whether only the items not observed yet are tried again, for
    ///   an unchanged list.
    private func updateObservers(retrying: Bool = false) {
        guard let appState else {
            return
        }
        let itemManager = appState.itemManager
        let wanted = Set(keys.map { itemManager.storedIdentityKey($0) })
        let items = itemManager.itemCache.managedItems.filter { item in
            !item.isControlItem && wanted.contains(itemManager.identityKey(for: item))
        }
        let targets = items.map { item in
            Target(
                key: itemManager.identityKey(for: item),
                windowID: item.windowID,
                pid: item.sourcePID ?? item.ownerPID,
                bounds: item.bounds
            )
        }
        let windows = Dictionary(targets.map { ($0.key, $0.windowID) }, uniquingKeysWith: { first, _ in first })
        let update = watchList.update(windows: windows, retrying: retrying)
        if update.removesObservers {
            removeAll()
        } else if !retrying {
            return
        }
        retryTask?.cancel()
        retryTask = nil
        guard let registration = update.registration else {
            return
        }
        // Observed items are not looked up again.
        let pending = targets.filter { registration.keys.contains($0.key) }
        Task { [weak self] in
            let batch = await Self.register(pending)
            self?.apply(batch, of: registration)
        }
    }

    /// Adds the observers of a finished registration, or drops them when the list changed
    /// meanwhile.
    private func apply(_ batch: Batch, of registration: ItemChangeWatchList.Registration) {
        guard watchList.finish(registration, observed: Set(batch.watched.map(\.key))) else {
            return
        }
        for observer in batch.observers {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers += batch.observers
        for entry in batch.watched {
            watched[entry.pid, default: []].append((element: entry.element, key: entry.key))
        }
        scheduleRetryIfNeeded()
    }

    /// Tries the marked items that were not observed again once 2 s later, at most three
    /// times for one list: their app may not answer Accessibility yet, and the list may not
    /// change again.
    private func scheduleRetryIfNeeded() {
        guard watchList.takeRetry() else {
            return
        }
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            self?.updateObservers(retrying: true)
        }
    }

    private func removeAll() {
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        watched.removeAll()
    }

    // MARK: Registration

    /// The queue the lookups and registrations run on, one batch at a time. It is not
    /// `MenuBarItemProvider27`'s queue: clicks and the item cache wait for that one.
    private nonisolated static let registrationQueue = DispatchQueue(
        label: "com.holzcloud.holzBar.ItemChangeWatcher",
        qos: .utility
    )

    /// A marked item to observe.
    private nonisolated struct Target: Sendable {
        let key: String
        let windowID: CGWindowID
        let pid: pid_t
        let bounds: CGRect
    }

    /// The result of a registration: the observers that observe at least one element, and
    /// the observed elements. Observers and elements are references that any thread may
    /// use; these are not used again on the registration queue once they are handed over.
    private nonisolated struct Batch: @unchecked Sendable {
        var observers = [AXObserver]()
        var watched = [(pid: pid_t, element: AXUIElement, key: String)]()
    }

    private nonisolated static func register(_ targets: [Target]) async -> Batch {
        await withCheckedContinuation { continuation in
            registrationQueue.async {
                continuation.resume(returning: batch(for: targets))
            }
        }
    }

    /// Looks up the items' elements and observes them, one new observer per process; runs
    /// on the registration queue.
    private nonisolated static func batch(for targets: [Target]) -> Batch {
        var batch = Batch()
        var observers = [pid_t: AXObserver]()
        for target in targets {
            guard let element = element(for: target) else {
                continue
            }
            let observer: AXObserver
            if let existing = observers[target.pid] {
                observer = existing
            } else {
                var created: AXObserver?
                guard AXObserverCreate(target.pid, itemChangeWatcherCallback, &created) == .success, let created else {
                    continue
                }
                observers[target.pid] = created
                observer = created
            }
            // The process identifier travels as the context pointer (it is never 0 here).
            let context = UnsafeMutableRawPointer(bitPattern: Int(target.pid))
            let added = [kAXTitleChangedNotification, kAXValueChangedNotification].filter { notification in
                AXObserverAddNotification(observer, element, notification as CFString, context) == .success
            }
            guard !added.isEmpty else {
                logger.debug("A marked item posts no change notifications")
                continue
            }
            batch.watched.append((pid: target.pid, element: element, key: target.key))
        }
        let observedPIDs = Set(batch.watched.map(\.pid))
        batch.observers = observers.filter { observedPIDs.contains($0.key) }.map(\.value)
        return batch
    }

    /// The Accessibility element of the item. On macOS 27 it is the one the item list was
    /// read from; the calls to it keep the default messaging timeout, which
    /// `ItemClicker27`'s presses on the same element need, so they may wait for a busy app
    /// for seconds, though never on the main thread. Before macOS 27 it is the child of its
    /// app's extras menu bar at the item's place, and every call to the app waits 0.25 s at
    /// most.
    private nonisolated static func element(for target: Target) -> AXUIElement? {
        if #available(macOS 27.0, *) {
            return MenuBarItemProvider27.element(forWindowID: target.windowID)
        }
        let application = AXUIElementCreateApplication(target.pid)
        AXHelpers.setMessagingTimeout(0.25, for: application)
        guard let extrasMenuBar = AXHelpers.extrasMenuBar(for: application) else {
            return nil
        }
        AXHelpers.setMessagingTimeout(0.25, for: extrasMenuBar)
        return AXHelpers.children(for: extrasMenuBar).first { child in
            AXHelpers.setMessagingTimeout(0.25, for: child)
            guard let frame = AXHelpers.frame(for: child) else {
                return false
            }
            return abs(frame.minX - target.bounds.minX) < 2 && abs(frame.width - target.bounds.width) < 2
        }
    }

    // MARK: Changes

    /// Handles a change notification of the element with the given hash.
    fileprivate func elementChanged(hash: CFHashCode, pid: pid_t) {
        guard
            let appState,
            let key = watched[pid]?.first(where: { CFHash($0.element) == hash })?.key
        else {
            return
        }
        changeReveal.noteChange(
            key: key,
            isZenActive: !appState.menuBarManager.zenMode.allows(.changeReveal),
            isVisible: isVisible(key, appState: appState),
            at: ProcessInfo.processInfo.systemUptime
        )
        scheduleDueChanges()
    }

    /// Whether the item with the given key can be seen anyway.
    private func isVisible(_ key: String, appState: AppState) -> Bool {
        guard
            let item = appState.itemManager.item(withIdentityKey: key),
            let address = appState.itemManager.itemCache.address(for: item.tag)
        else {
            return true
        }
        guard address.section != .visible else {
            return true
        }
        return appState.menuBarManager.section(withName: address.section)?.isHidden == false
    }

    /// Waits once until the next change is due, shows the due items and waits again while
    /// changes wait.
    private func scheduleDueChanges() {
        guard dueTask == nil, let dueTime = changeReveal.nextDueTime else {
            return
        }
        let delay = max(dueTime - ProcessInfo.processInfo.systemUptime, 0)
        dueTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else {
                return
            }
            dueTask = nil
            for key in changeReveal.due(at: ProcessInfo.processInfo.systemUptime) {
                appState?.menuBarManager.revealBriefly(itemKey: key)
            }
            scheduleDueChanges()
        }
    }
}

/// The observers' callback; it runs on the main run loop. Only the element's hash leaves
/// it, which identifies the element among the observed ones.
nonisolated private func itemChangeWatcherCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    let pid = context.map { pid_t(truncatingIfNeeded: Int(bitPattern: $0)) } ?? 0
    let hash = CFHash(element)
    MainActor.assumeIsolated {
        ItemChangeWatcher.current?.elementChanged(hash: hash, pid: pid)
    }
}
