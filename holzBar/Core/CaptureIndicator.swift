//
//  CaptureIndicator.swift
//  holzBar
//

import Foundation

/// What holzBar's icon shows while another app records.
///
/// On macOS 27 Control Centre's capture indicator is not drawn while any MenuBarAgent
/// assessment assertion is live, whatever the allowlist holds (measured on macOS 27.0,
/// `MenuBarAssessmentAssertion27`), and concealing is holzBar's normal state. holzBar marks its
/// own icon instead, in Control Centre's colours: green for a camera, orange for the microphone
/// only. Screen recording by other apps has no public signal and is not covered.
nonisolated enum CaptureBadge: Equatable, Sendable {
    case microphone
    case camera
    case cameraAndMicrophone

    /// Whether the dot is green (a camera), as Control Centre colours its indicator; orange
    /// otherwise.
    var showsCamera: Bool {
        switch self {
        case .microphone: false
        case .camera, .cameraAndMicrophone: true
        }
    }
}

/// The processes recording from the microphone and the cameras in use, by object ID.
///
/// holzBar's own process appears among CoreAudio's process objects as soon as it reads them,
/// so it is never counted.
nonisolated struct CaptureActivity: Equatable, Sendable {
    /// holzBar's own process identifier.
    private let ownPID: Int32

    /// The CoreAudio process objects whose input is running.
    private(set) var microphones = Set<UInt32>()

    /// The CoreMediaIO devices running somewhere.
    private(set) var cameras = Set<UInt32>()

    init(ownPID: Int32) {
        self.ownPID = ownPID
    }

    /// Whether another process records from a microphone.
    var isMicrophoneInUse: Bool {
        !microphones.isEmpty
    }

    /// Whether a camera is in use.
    var isCameraInUse: Bool {
        !cameras.isEmpty
    }

    /// Records whether a process records from a microphone; holzBar's own is ignored.
    mutating func setInput(of process: UInt32, pid: Int32, isRunning: Bool) {
        if isRunning && pid != ownPID {
            microphones.insert(process)
        } else {
            microphones.remove(process)
        }
    }

    /// Forgets the processes that are gone, which can quit while recording.
    mutating func keepProcesses(_ processes: Set<UInt32>) {
        microphones.formIntersection(processes)
    }

    /// Records whether a camera is in use.
    mutating func setCamera(_ device: UInt32, isRunning: Bool) {
        if isRunning {
            cameras.insert(device)
        } else {
            cameras.remove(device)
        }
    }

    /// Forgets the cameras that are gone, which can be unplugged while running.
    mutating func keepCameras(_ devices: Set<UInt32>) {
        cameras.formIntersection(devices)
    }
}

/// Decides what holzBar's icon shows while another app records.
nonisolated enum CaptureIndicator {
    /// The badge on holzBar's icon, or `nil` for none.
    ///
    /// Never while nothing is concealed: Control Centre draws its own indicator then.
    static func badge(isEnabled: Bool, isConcealing: Bool, isMicrophoneInUse: Bool, isCameraInUse: Bool) -> CaptureBadge? {
        guard isEnabled, isConcealing else {
            return nil
        }
        switch (isCameraInUse, isMicrophoneInUse) {
        case (true, true): return .cameraAndMicrophone
        case (true, false): return .camera
        case (false, true): return .microphone
        case (false, false): return nil
        }
    }

    /// Whether holzBar's icon is on the bar: when the user shows it, and while it carries a
    /// badge.
    static func showsHolzBarIcon(isIconEnabled: Bool, badge: CaptureBadge?) -> Bool {
        isIconEnabled || badge != nil
    }
}
