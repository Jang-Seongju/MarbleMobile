import SwiftUI
import UIKit

/// Read-only live game log backed by UIKit's text view.
///
/// UITextView and VoiceOver own selection, focus, and ordinary navigation. The
/// only app accessibility override is one-page vertical scrolling, because the
/// standard VoiceOver page gesture was verified on-device to make negligible
/// progress through this long live log.
private final class GameMessageTextView: UITextView {
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let minimumY = -adjustedContentInset.top
        let maximumY = max(
            minimumY,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
        guard maximumY > minimumY + 1 else { return false }

        let visibleHeight = max(1, bounds.height - adjustedContentInset.top - adjustedContentInset.bottom)
        let pageStep = max(44, visibleHeight * 0.85)

        let targetY: CGFloat
        switch direction {
        case .up, .next:
            targetY = min(maximumY, contentOffset.y + pageStep)
        case .down, .previous:
            targetY = max(minimumY, contentOffset.y - pageStep)
        default:
            return super.accessibilityScroll(direction)
        }

        guard abs(targetY - contentOffset.y) > 1 else { return false }
        setContentOffset(CGPoint(x: contentOffset.x, y: targetY), animated: false)
        UIAccessibility.post(notification: .pageScrolled, argument: nil)
        return true
    }
}

struct GameMessageLogView: UIViewRepresentable {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let messages: [GameRoomMessage]

    final class Coordinator {
        var renderedMessages: [GameRoomMessage] = []
        var renderedDynamicTypeSize: DynamicTypeSize?
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

        replaceAll(messages: messages, in: view)
        context.coordinator.renderedMessages = messages
        context.coordinator.renderedDynamicTypeSize = dynamicTypeSize
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator

        // Dynamic Type changes are rare document-wide presentation changes.
        // Rebuilding here is intentional so already-rendered standard/chat rows
        // receive their new preferred fonts. Normal message arrival never uses
        // this path.
        if coordinator.renderedDynamicTypeSize != dynamicTypeSize {
            replaceAll(messages: messages, in: uiView)
            coordinator.renderedMessages = messages
            coordinator.renderedDynamicTypeSize = dynamicTypeSize
            return
        }

        guard messages != coordinator.renderedMessages else { return }

        // Empty <-> non-empty transitions replace the placeholder/document once.
        if messages.isEmpty || coordinator.renderedMessages.isEmpty {
            replaceAll(messages: messages, in: uiView)
            coordinator.renderedMessages = messages
            return
        }

        // Normal live-log growth: preserve the existing UITextView document and
        // insert only the newly-arrived suffix through UITextInput. This avoids
        // both whole-document assignment and direct NSTextStorage mutation.
        if messages.count >= coordinator.renderedMessages.count,
           messages.starts(with: coordinator.renderedMessages) {
            let newMessages = messages.dropFirst(coordinator.renderedMessages.count)
            for message in newMessages {
                guard append(message, to: uiView) else { return }
                coordinator.renderedMessages.append(message)
            }
            return
        }

        // A non-prefix change means the room log itself was replaced/corrected,
        // not appended. A full document replacement is appropriate in that case.
        replaceAll(messages: messages, in: uiView)
        coordinator.renderedMessages = messages
    }

    private func replaceAll(messages: [GameRoomMessage], in view: UITextView) {
        guard !messages.isEmpty else {
            view.attributedText = NSAttributedString(
                string: "게임 메시지가 없습니다.",
                attributes: placeholderAttributes()
            )
            return
        }

        let document = NSMutableAttributedString(string: "")
        for (index, message) in messages.enumerated() {
            if index > 0 {
                document.append(NSAttributedString(string: "\n", attributes: attributes(for: message.kind)))
            }
            document.append(NSAttributedString(string: message.text, attributes: attributes(for: message.kind)))
        }
        view.attributedText = document
    }

    /// Appends new rows through UITextView's UITextInput document API.
    ///
    /// Do not replace this with direct textStorage mutation: that bypasses the
    /// UITextView layer that tracks text positions, selection, and input-system
    /// changes used by accessibility.
    private func append(_ message: GameRoomMessage, to view: UITextView) -> Bool {
        let suffix = "\n" + message.text
        let previousTypingAttributes = view.typingAttributes
        view.typingAttributes = attributes(for: message.kind)
        defer { view.typingAttributes = previousTypingAttributes }

        let end = view.endOfDocument
        guard let insertionRange = view.textRange(from: end, to: end) else {
            return false
        }

        let oldUTF16Length = view.text.utf16.count
        view.replace(insertionRange, withText: suffix)

        // Only advance the rendered-message cursor after UITextView confirms
        // that its own document changed. This prevents a failed insertion
        // from silently marking a message as already rendered.
        return view.text.utf16.count == oldUTF16Length + suffix.utf16.count
            && view.text.hasSuffix(suffix)
    }

    private func attributes(for kind: GameRoomMessage.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .standard:
            return [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]

        case .chat:
            // Chat is intentionally conspicuous for low-vision users. The text
            // itself is unchanged, so VoiceOver/TTS semantics remain identical.
            return [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.systemYellow
            ]
        }
    }

    private func placeholderAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.secondaryLabel
        ]
    }
}
