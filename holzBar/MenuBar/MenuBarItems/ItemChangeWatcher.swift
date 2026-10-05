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
/// One `AXObserver` per process that owns a marked item listens for
/// `kAXTitleChangedNotification` and `kAXValueChangedNotification` on those items'
/// elements only; its run-loop source runs on the main run loop. The observers follow the
/// item list (they are set up again when it changes) and nothing runs while no item is
/// marked. Each notification passes ``ChangeReveal``'s debounce and rate limit; a due item
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

    /// The observers, by process identifier.
    private var observers = [pid_t: AXObserver]()

    /// The observed elements with their items' keys, by process identifier.
    private var watched = [pid_t: [(element: AXUIElement, key: String)]]()

    /// The marked items and their windows the observers were set up for, so an unchanged
    /// list sets nothing up again.
    private var setUpWindows = [String: CGWindowID]()

    /// The observed items and their windows. An item whose element was not found or not
    /// observed is missing here, and is tried again a few times (`retryTask`).
    private var watchedWindows = [String: CGWindowID]()

    /// The one wait before the items that were not observed are tried again; a changed
    /// list cancels it.
    private var retryTask: Task<Void, Never>?

    /// The retries made for the current list.
    private var retryCount = 0

    /// The debounce and rate limit.
    private var changeReveal = ChangeReveal()

    /// The one wait until the next change is due.
    private var dueTask: Task<Void, Never>?

    private let logger = Logger(category: "ItemChangeWatcher")

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
        let windows = Dictionary(
            items.map { (itemManager.identityKey(for: $0), $0.windowID) },
            uniquingKeysWith: { first, _ in first }
        )
        if windows != setUpWindows {
            removeAll()
            watchedWindows.removeAll()
            setUpWindows = windows
            retryCount = 0
        } else if !retrying {
            // A pending retry stays.
            return
        }
        retryTask?.cancel()
        retryTask = nil
        // Each lookup asks the app and waits 0.25 s at most, so observed items are not
        // looked up again.
        for item in items {
            let pid = item.sourcePID ?? item.ownerPID
            let key = itemManager.identityKey(for: item)
            guard
                watchedWindows[key] == nil,
                let element = element(for: item, pid: pid),
                observe(element, key: key, pid: pid)
            else {
                continue
            }
            watchedWindows[key] = item.windowID
        }
        scheduleRetryIfNeeded()
    }

    /// Tries the marked items that were not observed again once 2 s later, at most three
    /// times for one list: their app may not answer Accessibility yet, and the list may not
    /// change again.
    private func scheduleRetryIfNeeded() {
        guard watchedWindows.count < setUpWindows.count, retryCount < 3 else {
            return
        }
        retryCount += 1
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            self?.updateObservers(retrying: true)
        }
    }

    /// The Accessibility element of the item: on macOS 27 the one the item list was read
    /// from; before, the child of its app's extras menu bar at the item's place. Every call
    /// to the app waits 0.25 s at most.
    private func element(for item: MenuBarItem, pid: pid_t) -> AXUIElement? {
        if #available(macOS 27.0, *) {
            return MenuBarItemProvider27.element(forWindowID: item.windowID)
        }
        let application = AXUIElementCreateApplication(pid)
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
            return abs(frame.minX - item.bounds.minX) < 2 && abs(frame.width - item.bounds.width) < 2
        }
    }

    /// Observes the element's changes; returns whether any notification was added.
    private func observe(_ element: AXUIElement, key: String, pid: pid_t) -> Bool {
        let observer: AXObserver
        if let existing = observers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            guard AXObserverCreate(pid, itemChangeWatcherCallback, &created) == .success, let created else {
                return false
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            observers[pid] = created
            observer = created
        }
        // The process identifier travels as the context pointer (it is never 0 here).
        let context = UnsafeMutableRawPointer(bitPattern: Int(pid))
        let added = [kAXTitleChangedNotification, kAXValueChangedNotification].filter { notification in
            AXObserverAddNotification(observer, element, notification as CFString, context) == .success
        }
        guard !added.isEmpty else {
            logger.debug("A marked item posts no change notifications")
            return false
        }
        watched[pid, default: []].append((element: element, key: key))
        return true
    }

    private func removeAll() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        watched.removeAll()
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
