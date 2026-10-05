//
//  CaptureActivityMonitor27.swift
//  holzBar
//

import CoreAudio
import CoreMediaIO
import Foundation
import Observation
import OSLog

/// Follows whether another app uses the microphone or a camera, so holzBar can mark its own
/// icon on macOS 27.
///
/// While any MenuBarAgent assessment assertion is live, Control Centre's capture indicator is
/// not drawn (measured on macOS 27.0, `MenuBarAssessmentAssertion27`), and concealing is
/// holzBar's normal state. The microphone is followed through CoreAudio's process objects,
/// whose input-running property names the processes that record: the running-somewhere
/// property of an audio device also turns on when a headset only plays sound. Cameras are
/// followed through CoreMediaIO's devices.
///
/// Only listeners: nothing polls, no audio or video is opened, and no permission or
/// entitlement is needed (measured on macOS 26.7.1 on 2026-10-05: coreaudiod only preflights
/// the Microphone, Screen Recording and audio capture status of a new client, with no prompt,
/// and CoreMediaIO reads cause no TCC query). holzBar's own process appears among the process
/// objects as soon as it reads them and is ignored. Nothing runs while the setting is off.
@available(macOS 27.0, *)
@MainActor
@Observable
final class CaptureActivityMonitor27 {
    /// What other processes use now.
    private(set) var activity = CaptureActivity(ownPID: ProcessInfo.processInfo.processIdentifier)

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

    /// Follows the setting.
    @ObservationIgnored private var settingObserver: ObservationLoop?

    /// Follows the badge on holzBar's icon, to make sure the icon is there when a capture starts.
    @ObservationIgnored private var badgeObserver: ObservationLoop?

    /// The badge last seen by ``badgeObserver``.
    @ObservationIgnored private var lastBadge: CaptureBadge?

    /// The check for holzBar's icon after a capture started.
    @ObservationIgnored private var iconCheckTask: Task<Void, Never>?

    /// Whether the listeners are registered.
    @ObservationIgnored private var isRunning = false

    /// The listeners on CoreAudio's system object, with their addresses.
    @ObservationIgnored private var systemListeners = [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)]()

    /// The listener on CoreMediaIO's device list.
    @ObservationIgnored private var deviceListListener: CMIOObjectPropertyListenerBlock?

    /// The process objects of other processes, with their process identifiers and listeners.
    @ObservationIgnored private var processes = [AudioObjectID: (pid: pid_t, listener: AudioObjectPropertyListenerBlock)]()

    /// The process objects of holzBar itself, which get no listener.
    @ObservationIgnored private var ownProcesses = Set<AudioObjectID>()

    /// The camera devices, with their listeners.
    @ObservationIgnored private var cameras = [CMIOObjectID: CMIOObjectPropertyListenerBlock]()

    @ObservationIgnored private let logger = Logger(category: "CaptureActivityMonitor27")

    /// holzBar's own process identifier.
    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Starts following the setting and the badge.
    func performSetup(with appState: AppState) {
        self.appState = appState
        let general = appState.settings.general
        settingObserver = ObservationLoop.observe { general.holzBarIconShowsCaptureDot } onChange: { [weak self] isOn in
            self?.setRunning(isOn && MenuBarAssessmentAssertion27.isAvailable)
        }
        lastBadge = appState.captureBadge27
        badgeObserver = ObservationLoop.observe { appState.captureBadge27 } onChange: { [weak self] badge in
            self?.badgeDidChange(badge)
        }
        setRunning(general.holzBarIconShowsCaptureDot && MenuBarAssessmentAssertion27.isAvailable)
    }

    private func setRunning(_ isOn: Bool) {
        if isOn {
            start()
        } else {
            stop()
        }
    }

    /// Makes sure holzBar's icon is on the bar when a capture starts.
    private func badgeDidChange(_ badge: CaptureBadge?) {
        defer {
            lastBadge = badge
        }
        guard lastBadge == nil, badge != nil, let appState else {
            return
        }
        iconCheckTask?.cancel()
        iconCheckTask = Task {
            await appState.concealer27.checkOwnIconForCapture()
        }
    }

    private func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        let processList = Self.listener { [weak self] in
            self?.processesChanged()
        }
        // The header asks for every listener to be added again after coreaudiod restarts.
        let restarted = Self.listener { [weak self] in
            Task {
                self?.restart()
            }
        }
        for (selector, block) in [
            (kAudioHardwarePropertyProcessObjectList, processList),
            (kAudioHardwarePropertyServiceRestarted, restarted),
        ] {
            var address = Self.address(selector)
            let status = AudioObjectAddPropertyListenerBlock(system, &address, .main, block)
            if status == noErr {
                systemListeners.append((address, block))
            } else {
                logger.debug("Could not listen to CoreAudio: \(status, privacy: .public)")
            }
        }
        let deviceList = Self.cameraListener { [weak self] in
            self?.camerasChanged()
        }
        var deviceListAddress = Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let status = CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &deviceListAddress, .main, deviceList)
        if status == noErr {
            deviceListListener = deviceList
        } else {
            logger.debug("Could not listen to CoreMediaIO: \(status, privacy: .public)")
        }
        processesChanged()
        camerasChanged()
        logger.notice("Watching microphone and camera use")
    }

    private func stop() {
        iconCheckTask?.cancel()
        iconCheckTask = nil
        guard isRunning else {
            return
        }
        isRunning = false
        let system = AudioObjectID(kAudioObjectSystemObject)
        for listener in systemListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener.block)
        }
        systemListeners.removeAll()
        if let deviceListListener {
            var address = Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, .main, deviceListListener)
            self.deviceListListener = nil
        }
        for process in Array(processes.keys) {
            forgetProcess(process)
        }
        ownProcesses.removeAll()
        for camera in Array(cameras.keys) {
            forgetCamera(camera)
        }
        activity = CaptureActivity(ownPID: Self.ownPID)
        logger.notice("Stopped watching microphone and camera use")
    }

    /// Registers every listener again after coreaudiod restarted.
    private func restart() {
        guard isRunning else {
            return
        }
        stop()
        start()
    }

    // MARK: Microphone

    /// Follows the process objects that came and went.
    private func processesChanged() {
        guard isRunning else {
            return
        }
        let listed: [AudioObjectID]
        switch Self.readObjectIDs(of: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyProcessObjectList) {
        case let .success(objectIDs):
            listed = objectIDs
        case let .failure(failure):
            logger.debug("Could not read the audio processes: \(failure.status, privacy: .public)")
            return
        }
        let current = Set(listed)
        for process in processes.keys where !current.contains(process) {
            forgetProcess(process)
        }
        ownProcesses.formIntersection(current)
        var updated = activity
        for process in listed where processes[process] == nil && !ownProcesses.contains(process) {
            guard case let .success(pid) = Self.readUInt32(of: process, selector: kAudioProcessPropertyPID).map({ pid_t(bitPattern: $0) }) else {
                continue
            }
            guard pid != Self.ownPID else {
                ownProcesses.insert(process)
                continue
            }
            let listener = Self.listener { [weak self] in
                self?.inputChanged(of: process)
            }
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectAddPropertyListenerBlock(process, &address, .main, listener) == noErr else {
                continue
            }
            processes[process] = (pid, listener)
            if case let .success(isRunning) = Self.readUInt32(of: process, selector: kAudioProcessPropertyIsRunningInput) {
                updated.setInput(of: process, pid: pid, isRunning: isRunning != 0)
            }
        }
        updated.keepProcesses(Set(processes.keys))
        setActivity(updated)
    }

    /// Reads again whether a process records.
    private func inputChanged(of process: AudioObjectID) {
        guard let pid = processes[process]?.pid else {
            return
        }
        guard case let .success(isRunning) = Self.readUInt32(of: process, selector: kAudioProcessPropertyIsRunningInput) else {
            return
        }
        var updated = activity
        updated.setInput(of: process, pid: pid, isRunning: isRunning != 0)
        setActivity(updated)
    }

    /// Removes the listener of a process object and forgets it.
    private func forgetProcess(_ process: AudioObjectID) {
        guard let entry = processes.removeValue(forKey: process) else {
            return
        }
        var address = Self.address(kAudioProcessPropertyIsRunningInput)
        // The object may be gone already, so the status is not checked.
        AudioObjectRemovePropertyListenerBlock(process, &address, .main, entry.listener)
    }

    // MARK: Cameras

    /// Follows the cameras that came and went.
    private func camerasChanged() {
        guard isRunning else {
            return
        }
        let listed: [CMIOObjectID]
        switch Self.readCameraIDs() {
        case let .success(objectIDs):
            listed = objectIDs
        case let .failure(failure):
            logger.debug("Could not read the cameras: \(failure.status, privacy: .public)")
            return
        }
        let current = Set(listed)
        for camera in cameras.keys where !current.contains(camera) {
            forgetCamera(camera)
        }
        var updated = activity
        for camera in listed where cameras[camera] == nil {
            let listener = Self.cameraListener { [weak self] in
                self?.cameraChanged(camera)
            }
            var address = Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            guard CMIOObjectAddPropertyListenerBlock(camera, &address, .main, listener) == noErr else {
                continue
            }
            cameras[camera] = listener
            if case let .success(isRunning) = Self.readCameraIsRunning(camera) {
                updated.setCamera(camera, isRunning: isRunning)
            }
        }
        updated.keepCameras(Set(cameras.keys))
        setActivity(updated)
    }

    /// Reads again whether a camera is in use.
    private func cameraChanged(_ camera: CMIOObjectID) {
        guard cameras[camera] != nil, case let .success(isRunning) = Self.readCameraIsRunning(camera) else {
            return
        }
        var updated = activity
        updated.setCamera(camera, isRunning: isRunning)
        setActivity(updated)
    }

    /// Removes the listener of a camera and forgets it.
    private func forgetCamera(_ camera: CMIOObjectID) {
        guard let listener = cameras.removeValue(forKey: camera) else {
            return
        }
        var address = Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        // The device may be gone already, so the status is not checked.
        CMIOObjectRemovePropertyListenerBlock(camera, &address, .main, listener)
    }

    /// Stores a changed activity; an unchanged one is not assigned, so nothing observes it.
    private func setActivity(_ updated: CaptureActivity) {
        guard updated != activity else {
            return
        }
        activity = updated
        logger.debug(
            "Microphone in use: \(updated.isMicrophoneInUse, privacy: .public), camera in use: \(updated.isCameraInUse, privacy: .public)"
        )
    }

    // MARK: Reading

    /// A failed read, with its status code.
    private struct ReadError: Error {
        let status: OSStatus
    }

    /// A CoreAudio listener that runs on the main actor; the listeners are added on the main queue.
    private nonisolated static func listener(_ action: @escaping @MainActor @Sendable () -> Void) -> AudioObjectPropertyListenerBlock {
        { _, _ in
            MainActor.assumeIsolated {
                action()
            }
        }
    }

    /// A CoreMediaIO listener that runs on the main actor; the listeners are added on the main queue.
    private nonisolated static func cameraListener(_ action: @escaping @MainActor @Sendable () -> Void) -> CMIOObjectPropertyListenerBlock {
        { _, _ in
            MainActor.assumeIsolated {
                action()
            }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
    }

    private static func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    /// Reads a list of CoreAudio object identifiers.
    private static func readObjectIDs(of object: AudioObjectID, selector: AudioObjectPropertySelector) -> Result<[AudioObjectID], ReadError> {
        var address = address(selector)
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            return .failure(ReadError(status: sizeStatus))
        }
        var objectIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard !objectIDs.isEmpty else {
            return .success([])
        }
        let status = objectIDs.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else {
                return OSStatus(kAudioHardwareBadPropertySizeError)
            }
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, base)
        }
        guard status == noErr else {
            return .failure(ReadError(status: status))
        }
        return .success(Array(objectIDs.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride)))
    }

    /// Reads a 32-bit CoreAudio property.
    private static func readUInt32(of object: AudioObjectID, selector: AudioObjectPropertySelector) -> Result<UInt32, ReadError> {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? .success(value) : .failure(ReadError(status: status))
    }

    /// Reads the CoreMediaIO devices.
    private static func readCameraIDs() -> Result<[CMIOObjectID], ReadError> {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            return .failure(ReadError(status: sizeStatus))
        }
        var objectIDs = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.stride)
        guard !objectIDs.isEmpty else {
            return .success([])
        }
        var used: UInt32 = 0
        let status = objectIDs.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else {
                return OSStatus(kCMIOHardwareBadPropertySizeError)
            }
            return CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, base)
        }
        guard status == noErr else {
            return .failure(ReadError(status: status))
        }
        return .success(Array(objectIDs.prefix(Int(used) / MemoryLayout<CMIOObjectID>.stride)))
    }

    /// Reads whether a CoreMediaIO device runs in any process.
    private static func readCameraIsRunning(_ camera: CMIOObjectID) -> Result<Bool, ReadError> {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return status == noErr ? .success(value != 0) : .failure(ReadError(status: status))
    }
}
