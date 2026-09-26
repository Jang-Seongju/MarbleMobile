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
    let messages: [String]

    func makeUIView(context: Context) -> UITextView {
        let view = GameMessageTextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.textContainer.lineFragmentPadding = 0
        apply(messages: messages, to: view)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        apply(messages: messages, to: uiView)
    }

    private func apply(messages: [String], to view: UITextView) {
        let displayedText = messages.isEmpty
            ? "게임 메시지가 없습니다."
            : messages.joined(separator: "\n")

        view.textColor = messages.isEmpty ? .secondaryLabel : .label
        guard view.text != displayedText else { return }
        view.text = displayedText
    }
}
