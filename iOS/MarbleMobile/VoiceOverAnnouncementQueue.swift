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

    func speak(_ text: String, completion: @escaping () -> Void) {
        cancelCurrent()
        guard !text.isEmpty else { completion(); return }
        guard UIAccessibility.isVoiceOverRunning else { completion(); return }

        let item = Current(id: UUID(), text: text, completion: completion)
        current = item
        UIAccessibility.post(notification: .announcement, argument: text)

        let timeout = min(20.0, max(3.0, Double(text.count) * 0.14 + 2.0))
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.current?.id == item.id else { return }
                self.finishCurrent()
            }
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func cancelCurrent() {
        guard let current else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        self.current = nil
        current.completion()
    }

    private func announcementFinished(_ notification: Notification) {
        guard let current else { return }
        if let spoken = notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String,
           spoken != current.text {
            return
        }
        finishCurrent()
    }

    private func finishCurrent() {
        guard let current else { return }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        self.current = nil
        current.completion()
    }
}
