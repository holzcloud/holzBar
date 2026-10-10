//
//  AutomationCaptureObserver.swift
//  holzBar
//

import Foundation

/// Follows whether another app uses a camera or the microphone, for the automation conditions
/// "camera in use" and "microphone in use".
///
/// It uses the same listeners as the capture dot of macOS 27 (``CaptureWatcher27``): nothing
/// polls, no audio or video is opened and no permission is needed. It exists only while an
/// enabled rule has one of the two conditions.
@available(macOS 14.2, *)
@MainActor
final class AutomationCaptureObserver {
    /// Called with whether a camera and the microphone are in use, after each change.
    var onChange: ((_ isCameraInUse: Bool, _ isMicrophoneInUse: Bool) -> Void)?

    private var watcher: CaptureWatcher27?
    private var watchTask: Task<Void, Never>?

    func start() {
        guard watcher == nil else {
            return
        }
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureActivity.self, bufferingPolicy: .bufferingNewest(1))
        let watcher = CaptureWatcher27(ownPID: ProcessInfo.processInfo.processIdentifier, report: continuation)
        self.watcher = watcher
        watchTask = Task { [weak self] in
            for await activity in stream {
                // A report already on its way when the observer stopped is dropped.
                guard !Task.isCancelled else {
                    return
                }
                self?.onChange?(activity.isCameraInUse, activity.isMicrophoneInUse)
            }
        }
        Task {
            await watcher.start()
        }
    }

    func stop() {
        guard let watcher else {
            return
        }
        self.watcher = nil
        watchTask?.cancel()
        watchTask = nil
        Task {
            await watcher.stop()
        }
    }
}
