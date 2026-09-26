import SwiftUI
import UIKit

/// Temporary on-device diagnostics for the VoiceOver message paging issue.
///
/// This intentionally records observations only. It does not participate in
/// focus management, message layout, or ordinary VoiceOver navigation.
enum GameMessageScrollDiagnostics {
    private static let lock = NSLock()
    private static var entries: [String] = []
    private static var sequence = 0
    private static let maximumEntries = 400

    static func reset() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        sequence = 0
        lock.unlock()
        record("RESET")
    }

    static func record(_ message: String) {
        let uptime = ProcessInfo.processInfo.systemUptime
        lock.lock()
        sequence += 1
        entries.append(String(format: "%03d +%.3f %@", sequence, uptime, message))
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        lock.unlock()
    }

    static func snapshot() -> String {
        lock.lock()
        let body = entries.joined(separator: "\n")
        lock.unlock()
        return "MarbleMobile message-scroll diagnostic 1\n\(body)"
    }

    static func describe(_ view: UITextView) -> String {
        let inset = view.adjustedContentInset
        let selection = view.selectedRange
        return String(
            format: "offset=(%.1f,%.1f) content=(%.1f,%.1f) bounds=(%.1f,%.1f) inset=(%.1f,%.1f,%.1f,%.1f) scrollEnabled=%@ tracking=%@ dragging=%@ decelerating=%@ selected=(%ld,%ld) textLength=%ld window=%@ VO=%@",
            view.contentOffset.x,
            view.contentOffset.y,
            view.contentSize.width,
            view.contentSize.height,
            view.bounds.width,
            view.bounds.height,
            inset.top,
            inset.left,
            inset.bottom,
            inset.right,
            String(view.isScrollEnabled),
            String(view.isTracking),
            String(view.isDragging),
            String(view.isDecelerating),
            selection.location,
            selection.length,
            view.text.utf16.count,
            String(view.window != nil),
            String(UIAccessibility.isVoiceOverRunning)
        )
    }

    static func directionName(_ direction: UIAccessibilityScrollDirection) -> String {
        switch direction {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .next: return "next"
        case .previous: return "previous"
        @unknown default: return "unknown(\(direction.rawValue))"
        }
    }
}

/// Read-only live game log backed by UIKit's text view.
///
/// This is the exact paging behavior from b84560a plus diagnostic recording.
/// The diagnostic build must first establish whether VoiceOver actually calls
/// this UITextView's accessibilityScroll(_:) and what UIKit scroll metrics are
/// at that moment.
private final class GameMessageTextView: UITextView {
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let directionName = GameMessageScrollDiagnostics.directionName(direction)
        GameMessageScrollDiagnostics.record(
            "ACCESSIBILITY_SCROLL BEGIN direction=\(directionName) \(GameMessageScrollDiagnostics.describe(self))"
        )

        let minimumY = -adjustedContentInset.top
        let maximumY = max(
            minimumY,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
        guard maximumY > minimumY + 1 else {
            GameMessageScrollDiagnostics.record(
                String(format: "ACCESSIBILITY_SCROLL RETURN_FALSE not-scrollable direction=%@ minY=%.1f maxY=%.1f %@", directionName, minimumY, maximumY, GameMessageScrollDiagnostics.describe(self))
            )
            return false
        }

        let visibleHeight = max(1, bounds.height - adjustedContentInset.top - adjustedContentInset.bottom)
        let pageStep = max(44, visibleHeight * 0.85)

        let targetY: CGFloat
        switch direction {
        case .up, .next:
            targetY = min(maximumY, contentOffset.y + pageStep)
        case .down, .previous:
            targetY = max(minimumY, contentOffset.y - pageStep)
        default:
            let result = super.accessibilityScroll(direction)
            GameMessageScrollDiagnostics.record(
                "ACCESSIBILITY_SCROLL SUPER direction=\(directionName) result=\(result) \(GameMessageScrollDiagnostics.describe(self))"
            )
            return result
        }

        guard abs(targetY - contentOffset.y) > 1 else {
            GameMessageScrollDiagnostics.record(
                String(format: "ACCESSIBILITY_SCROLL RETURN_FALSE boundary direction=%@ targetY=%.1f minY=%.1f maxY=%.1f %@", directionName, targetY, minimumY, maximumY, GameMessageScrollDiagnostics.describe(self))
            )
            return false
        }

        GameMessageScrollDiagnostics.record(
            String(format: "ACCESSIBILITY_SCROLL SET_OFFSET direction=%@ targetY=%.1f pageStep=%.1f minY=%.1f maxY=%.1f", directionName, targetY, pageStep, minimumY, maximumY)
        )
        setContentOffset(CGPoint(x: contentOffset.x, y: targetY), animated: false)
        GameMessageScrollDiagnostics.record(
            "ACCESSIBILITY_SCROLL AFTER_SET direction=\(directionName) \(GameMessageScrollDiagnostics.describe(self))"
        )
        UIAccessibility.post(notification: .pageScrolled, argument: nil)
        GameMessageScrollDiagnostics.record("ACCESSIBILITY_SCROLL POSTED pageScrolled direction=\(directionName)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GameMessageScrollDiagnostics.record(
                "ACCESSIBILITY_SCROLL NEXT_RUNLOOP direction=\(directionName) \(GameMessageScrollDiagnostics.describe(self))"
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            guard let self else { return }
            GameMessageScrollDiagnostics.record(
                "ACCESSIBILITY_SCROLL AFTER_200MS direction=\(directionName) \(GameMessageScrollDiagnostics.describe(self))"
            )
        }
        return true
    }
}

struct GameMessageLogView: UIViewRepresentable {
    let messages: [String]

    final class Coordinator {
        private var contentOffsetObservation: NSKeyValueObservation?
        private var contentSizeObservation: NSKeyValueObservation?
        private(set) var renderedMessages: [String] = []
        private(set) var hasRenderedInitialState = false

        func install(on view: UITextView) {
            contentOffsetObservation = view.observe(\.contentOffset, options: [.old, .new]) { _, change in
                guard let old = change.oldValue, let new = change.newValue,
                      abs(old.x - new.x) > 0.5 || abs(old.y - new.y) > 0.5
                else { return }
                GameMessageScrollDiagnostics.record(
                    String(format: "KVO contentOffset (%.1f,%.1f) -> (%.1f,%.1f)", old.x, old.y, new.x, new.y)
                )
            }
            contentSizeObservation = view.observe(\.contentSize, options: [.old, .new]) { _, change in
                guard let old = change.oldValue, let new = change.newValue,
                      abs(old.width - new.width) > 0.5 || abs(old.height - new.height) > 0.5
                else { return }
                GameMessageScrollDiagnostics.record(
                    String(format: "KVO contentSize (%.1f,%.1f) -> (%.1f,%.1f)", old.width, old.height, new.width, new.height)
                )
            }
        }

        func markRendered(messages: [String]) {
            renderedMessages = messages
            hasRenderedInitialState = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let view = GameMessageTextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.textContainer.lineFragmentPadding = 0
        context.coordinator.install(on: view)
        GameMessageScrollDiagnostics.record("MAKE_UIVIEW \(GameMessageScrollDiagnostics.describe(view))")
        apply(messages: messages, to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        apply(messages: messages, to: uiView, coordinator: context.coordinator)
    }

    private func apply(messages: [String], to view: UITextView, coordinator: Coordinator) {
        view.textColor = messages.isEmpty ? .secondaryLabel : .label

        guard coordinator.hasRenderedInitialState else {
            replaceAll(messages: messages, in: view, coordinator: coordinator, reason: "initial")
            return
        }

        let previous = coordinator.renderedMessages
        guard previous != messages else { return }

        if !previous.isEmpty,
           messages.count > previous.count,
           Array(messages.prefix(previous.count)) == previous {
            append(
                newMessages: Array(messages.dropFirst(previous.count)),
                allMessages: messages,
                to: view,
                coordinator: coordinator
            )
            return
        }

        // A transition to/from the empty placeholder, room reset, truncation, or
        // replacement of an existing message is not an append. Only those real
        // replacement cases rebuild the text storage.
        replaceAll(messages: messages, in: view, coordinator: coordinator, reason: "reset-or-replacement")
    }

    private func append(
        newMessages: [String],
        allMessages: [String],
        to view: UITextView,
        coordinator: Coordinator
    ) {
        guard !newMessages.isEmpty else { return }

        let suffix = "\n" + newMessages.joined(separator: "\n")
        let insertionLocation = view.textStorage.length
        let insertedLength = (suffix as NSString).length

        GameMessageScrollDiagnostics.record(
            "TEXT_APPEND BEGIN addedMessages=\(newMessages.count) oldCount=\(coordinator.renderedMessages.count) newCount=\(allMessages.count) \(GameMessageScrollDiagnostics.describe(view))"
        )

        view.textStorage.beginEditing()
        view.textStorage.replaceCharacters(
            in: NSRange(location: insertionLocation, length: 0),
            with: suffix
        )
        if insertedLength > 0 {
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.label
            ]
            if let font = view.font {
                attributes[.font] = font
            }
            view.textStorage.addAttributes(
                attributes,
                range: NSRange(location: insertionLocation, length: insertedLength)
            )
        }
        view.textStorage.endEditing()
        coordinator.markRendered(messages: allMessages)

        GameMessageScrollDiagnostics.record(
            "TEXT_APPEND END \(GameMessageScrollDiagnostics.describe(view))"
        )
    }

    private func replaceAll(
        messages: [String],
        in view: UITextView,
        coordinator: Coordinator,
        reason: String
    ) {
        let displayedText = messages.isEmpty
            ? "게임 메시지가 없습니다."
            : messages.joined(separator: "\n")

        guard view.text != displayedText || coordinator.renderedMessages != messages else {
            coordinator.markRendered(messages: messages)
            return
        }

        GameMessageScrollDiagnostics.record(
            "TEXT_REPLACE_ALL BEGIN reason=\(reason) oldLength=\(view.text.utf16.count) newLength=\(displayedText.utf16.count) messageCount=\(messages.count) \(GameMessageScrollDiagnostics.describe(view))"
        )
        view.text = displayedText
        coordinator.markRendered(messages: messages)
        GameMessageScrollDiagnostics.record(
            "TEXT_REPLACE_ALL END reason=\(reason) \(GameMessageScrollDiagnostics.describe(view))"
        )
    }
}
