import Foundation
import UIKit

@MainActor
final class VoiceOverAnnouncementQueue {
    private struct Current {
        let id: UUID
        let text: String
        let completion: () -> Void
    }

    private var current: Current?
    private var observer: NSObjectProtocol?
    private var timeoutWorkItem: DispatchWorkItem?
    private var queueNextAnnouncementBehindCurrentSpeech = false

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.announcementFinished(notification) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Results finish before a modal closes. Its first FOLLOWING announcement
    /// can queue behind existing focus speech; this flag does not establish
    /// completion of UIKit's transition or protect the already-finished result.
    func waitForFocusSpeechBeforeNextAnnouncement() {
        queueNextAnnouncementBehindCurrentSpeech = true
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        let queueBehindSpeech = queueNextAnnouncementBehindCurrentSpeech
        queueNextAnnouncementBehindCurrentSpeech = false
        cancelCurrent()
        guard !text.isEmpty else { completion(); return }
        guard UIAccessibility.isVoiceOverRunning else { completion(); return }

        let item = Current(id: UUID(), text: text, completion: completion)
        current = item
        MobileDiagnosticLog.shared.record("TTS_START", "id=\(item.id) queued_after_focus=\(queueBehindSpeech) length=\(text.count)")
        if queueBehindSpeech {
            let announcement = NSAttributedString(
                string: text,
                attributes: [.accessibilitySpeechQueueAnnouncement: true]
            )
            UIAccessibility.post(notification: .announcement, argument: announcement)
        } else {
            UIAccessibility.post(notification: .announcement, argument: text)
        }

        let estimatedTimeout = min(20.0, max(3.0, Double(text.count) * 0.14 + 2.0))
        // The watchdog is only a fail-open path, not the hand-off boundary. A queued
        // announcement also has to allow time for the board's label/value/hint.
        let timeout = queueBehindSpeech ? max(30.0, estimatedTimeout) : estimatedTimeout
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.current?.id == item.id else { return }
                self.finishCurrent(reason: "watchdog")
            }
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func cancelCurrent() {
        queueNextAnnouncementBehindCurrentSpeech = false
        guard let current else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        self.current = nil
        MobileDiagnosticLog.shared.record("TTS_END", "id=\(current.id) reason=app_cancel")
        current.completion()
    }

    private func announcementFinished(_ notification: Notification) {
        guard let current else { return }
        guard let spoken = notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String,
              spoken == current.text else { return }
        let successful = notification.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? Bool
        // User navigation may intentionally interrupt speech. Preserve that behavior,
        // but never report an interruption or a watchdog as successful narration.
        finishCurrent(reason: successful == true ? "spoken" : (successful == false ? "interrupted" : "unknown"))
    }

    private func finishCurrent(reason: String) {
        guard let current else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        self.current = nil
        MobileDiagnosticLog.shared.record("TTS_END", "id=\(current.id) reason=\(reason)")
        current.completion()
    }
}
