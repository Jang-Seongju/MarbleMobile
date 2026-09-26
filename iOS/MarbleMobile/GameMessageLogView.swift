import SwiftUI
import UIKit

/// Read-only live game log backed by UIKit's standard text view.
///
/// VoiceOver focus is never chosen, pinned, or moved by the app. UIKit owns text
/// accessibility and scrolling. The app only follows the visual tail while the user
/// is already at the end of the log.
struct GameMessageLogView: UIViewRepresentable {
    let messages: [String]

    func makeUIView(context: Context) -> GameMessageTextView {
        let view = GameMessageTextView()
        view.update(messages: messages)
        return view
    }

    func updateUIView(_ uiView: GameMessageTextView, context: Context) {
        uiView.update(messages: messages)
    }
}

final class GameMessageTextView: UITextView, UITextViewDelegate {
    private var renderedMessages: [String] = []
    private var shouldFollowTail = true

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func update(messages: [String]) {
        guard messages != renderedMessages else { return }

        let previousOffset = contentOffset
        let wasEmpty = renderedMessages.isEmpty
        let isPureAppend = !renderedMessages.isEmpty
            && messages.count >= renderedMessages.count
            && Array(messages.prefix(renderedMessages.count)) == renderedMessages
        let followTailAfterUpdate = isPureAppend ? (shouldFollowTail || isAtTail) : true

        if isPureAppend {
            let appended = messages.dropFirst(renderedMessages.count)
            if !appended.isEmpty {
                text += "\n" + appended.joined(separator: "\n")
            }
        } else {
            text = messages.isEmpty
                ? "게임 메시지가 없습니다."
                : messages.joined(separator: "\n")
        }

        textColor = messages.isEmpty ? .secondaryLabel : .label
        renderedMessages = messages

        // Make the standard text view resolve its new content geometry before deciding
        // whether to follow the tail or preserve the user's current scroll position.
        layoutManager.ensureLayout(for: textContainer)
        layoutIfNeeded()

        if followTailAfterUpdate {
            scrollToLatest(animated: !wasEmpty)
            shouldFollowTail = true
        } else {
            // The user is reading older output. Appending text must not pull the
            // viewport back to the end, and no accessibility focus notification is sent.
            setContentOffset(clampedOffset(previousOffset), animated: false)
            shouldFollowTail = false
        }
    }

    private func configure() {
        isEditable = false
        isSelectable = true
        isScrollEnabled = true
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = true
        backgroundColor = .clear

        font = UIFont.preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        textColor = .label
        textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textContainer.lineFragmentPadding = 0

        // Leave UIKit/VoiceOver's standard UITextView accessibility behavior intact.
        // In particular, do not add custom adjustable elements, custom page values,
        // accessibilityScroll overrides, or focus-changing notifications.
        delegate = self
    }

    private var minimumOffsetY: CGFloat {
        -adjustedContentInset.top
    }

    private var maximumOffsetY: CGFloat {
        max(
            minimumOffsetY,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
    }

    private var isAtTail: Bool {
        maximumOffsetY - contentOffset.y <= 1
    }

    private func clampedOffset(_ offset: CGPoint) -> CGPoint {
        CGPoint(
            x: offset.x,
            y: min(maximumOffsetY, max(minimumOffsetY, offset.y))
        )
    }

    private func scrollToLatest(animated: Bool) {
        setContentOffset(
            CGPoint(x: contentOffset.x, y: maximumOffsetY),
            animated: animated
        )
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        shouldFollowTail = isAtTail
    }
}
