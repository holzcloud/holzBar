//
//  CaptureActivitySource.swift
//  holzBar
//

import Foundation

/// Reports whether another app uses a camera or the microphone, for the Live activities module.
///
/// It owns one ``AutomationCaptureObserver``, which listens the way the capture dot of macOS 27
/// does: nothing polls, no audio or video is opened and no permission is needed. The observer
/// exists from ``start(onChange:)`` to ``stop()``, so a module that is off, or a source that is
/// switched off, costs nothing.
@available(macOS 14.2, *)
@MainActor
final class CaptureActivitySource {
    private let observer = AutomationCaptureObserver()

    /// Starts listening. `onChange` is called with whether a camera and the microphone are in
    /// use, after each change.
    func start(onChange: @escaping (_ isCameraInUse: Bool, _ isMicrophoneInUse: Bool) -> Void) {
        observer.onChange = onChange
        observer.start()
    }

    /// Stops listening and lets go of the callback.
    func stop() {
        observer.stop()
        observer.onChange = nil
    }
}
