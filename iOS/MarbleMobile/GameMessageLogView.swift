import SwiftUI
import UIKit

/// Read-only live game log.
///
/// The log never moves or pins VoiceOver focus. Visual scrolling and VoiceOver focus
/// are deliberately independent: new messages may follow the tail only while the user
/// is already at the tail, and manual paging never posts a focus-changing accessibility
/// notification.
struct GameMessageLogView: UIViewRepresentable {
    let messages: [String]

    func makeUIView(context: Context) -> GameMessageLogUIView {
        let view = GameMessageLogUIView()
        view.update(messages: messages)
        return view
    }

    func updateUIView(_ uiView: GameMessageLogUIView, context: Context) {
        uiView.update(messages: messages)
    }
}

private final class MessageLogPagingControl: UIView {
    weak var logView: GameMessageLogUIView?

    override func accessibilityIncrement() {
        // VoiceOver one-finger swipe up: one viewport toward older messages.
        logView?.pageTowardOlderMessages()
    }

    override func accessibilityDecrement() {
        // VoiceOver one-finger swipe down: one viewport toward newer messages.
        logView?.pageTowardNewerMessages()
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        logView?.performAccessibilityScroll(direction) ?? false
    }
}

private final class MessageLogLabel: UILabel {
    weak var logView: GameMessageLogUIView?

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        // Forward VoiceOver's three-finger page gesture to the real scroll view without
        // moving accessibility focus away from the message currently being read.
        logView?.performAccessibilityScroll(direction) ?? super.accessibilityScroll(direction)
    }
}

final class GameMessageLogUIView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let pagingControl = MessageLogPagingControl()
    private var messageLabels: [MessageLogLabel] = []
    private var renderedMessages: [String] = []
    private var shouldFollowTail = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePagingAccessibilityValue()
    }

    func update(messages: [String]) {
        guard messages != renderedMessages else {
            updatePagingAccessibilityValue()
            return
        }

        let wasEmpty = renderedMessages.isEmpty
        let isPureAppend = !renderedMessages.isEmpty
            && messages.count >= renderedMessages.count
            && Array(messages.prefix(renderedMessages.count)) == renderedMessages
        let followTailAfterUpdate = isPureAppend ? (shouldFollowTail || isAtTail) : true

        if isPureAppend {
            for message in messages.dropFirst(renderedMessages.count) {
                appendMessageLabel(message)
            }
        } else {
            rebuildMessageLabels(messages)
        }
        renderedMessages = messages

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutIfNeeded()

            if followTailAfterUpdate {
                // Tail-follow is visual scrolling only. It never chooses a VoiceOver
                // element and never posts layoutChanged/screenChanged.
                self.scrollToLatest(animated: !wasEmpty)
                self.shouldFollowTail = true
            } else {
                // The user is reading older output. Appending new messages must not
                // pull the viewport or VoiceOver focus back to the tail.
                self.updatePagingAccessibilityValue()
            }
        }
    }

    fileprivate func pageTowardOlderMessages() {
        _ = page(by: -visiblePageHeight)
    }

    fileprivate func pageTowardNewerMessages() {
        _ = page(by: visiblePageHeight)
    }

    fileprivate func performAccessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        // UIAccessibilityScrollDirection describes the three-finger swipe direction:
        // swipe up moves the viewport toward newer/bottom content; swipe down moves it
        // toward older/top content. No focus-changing notification is posted.
        switch direction {
        case .up:
            return page(by: visiblePageHeight)
        case .down:
            return page(by: -visiblePageHeight)
        default:
            return false
        }
    }

    private func configure() {
        isAccessibilityElement = false
        clipsToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.delegate = self
        addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 6
        scrollView.addSubview(stackView)

        // This is a real UIKit accessibility view rather than a synthetic container
        // element. It consumes no visible layout space and does not replace the normal
        // UIScrollView accessibility hierarchy used by the message labels.
        pagingControl.translatesAutoresizingMaskIntoConstraints = false
        pagingControl.backgroundColor = .clear
        pagingControl.isAccessibilityElement = true
        pagingControl.accessibilityTraits = [.adjustable]
        pagingControl.logView = self
        addSubview(pagingControl)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -16),

            // Accessibility-only adjustable control: no visible button or reserved row.
            pagingControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            pagingControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            pagingControl.widthAnchor.constraint(equalToConstant: 1),
            pagingControl.heightAnchor.constraint(equalToConstant: 1),
        ])

        rebuildMessageLabels([])
        updatePagingAccessibilityValue()
    }

    private func rebuildMessageLabels(_ messages: [String]) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        messageLabels.removeAll(keepingCapacity: true)

        if messages.isEmpty {
            let placeholder = makeLabel("게임 메시지가 없습니다.", secondary: true)
            messageLabels.append(placeholder)
            stackView.addArrangedSubview(placeholder)
            return
        }

        for message in messages {
            let label = makeLabel(message, secondary: false)
            messageLabels.append(label)
            stackView.addArrangedSubview(label)
        }
    }

    private func appendMessageLabel(_ message: String) {
        if renderedMessages.isEmpty,
           messageLabels.count == 1,
           messageLabels[0].text == "게임 메시지가 없습니다." {
            let placeholder = messageLabels.removeFirst()
            stackView.removeArrangedSubview(placeholder)
            placeholder.removeFromSuperview()
        }

        let label = makeLabel(message, secondary: false)
        messageLabels.append(label)
        stackView.addArrangedSubview(label)
    }

    private func makeLabel(_ text: String, secondary: Bool) -> MessageLogLabel {
        let label = MessageLogLabel()
        label.logView = self
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = secondary ? .secondaryLabel : .label
        label.text = text
        label.isAccessibilityElement = true
        label.accessibilityTraits = [.staticText]
        return label
    }

    private var minimumOffsetY: CGFloat {
        -scrollView.adjustedContentInset.top
    }

    private var maximumOffsetY: CGFloat {
        max(
            minimumOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
    }

    private var visiblePageHeight: CGFloat {
        max(1, scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom)
    }

    private var isAtTail: Bool {
        maximumOffsetY - scrollView.contentOffset.y <= 1
    }

    private func scrollToLatest(animated: Bool) {
        layoutIfNeeded()
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maximumOffsetY),
            animated: animated
        )
        updatePagingAccessibilityValue()
    }

    @discardableResult
    private func page(by delta: CGFloat) -> Bool {
        layoutIfNeeded()
        let current = scrollView.contentOffset.y
        let target = min(maximumOffsetY, max(minimumOffsetY, current + delta))
        guard abs(target - current) > 0.5 else {
            updatePagingAccessibilityValue()
            return false
        }

        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: target),
            animated: false
        )
        shouldFollowTail = target >= maximumOffsetY - 1
        updatePagingAccessibilityValue()
        return true
    }

    private func updatePagingAccessibilityValue() {
        let pageHeight = visiblePageHeight
        let range = max(0, maximumOffsetY - minimumOffsetY)
        let totalPages = max(1, Int(ceil(range / pageHeight)) + 1)
        let offset = min(maximumOffsetY, max(minimumOffsetY, scrollView.contentOffset.y))

        let currentPage: Int
        if totalPages == 1 {
            currentPage = 1
        } else if offset >= maximumOffsetY - 0.5 {
            currentPage = totalPages
        } else {
            currentPage = min(
                totalPages,
                max(1, Int(floor((offset - minimumOffsetY) / pageHeight)) + 1)
            )
        }

        pagingControl.accessibilityValue = "\(currentPage)페이지 중 \(totalPages)페이지"
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        shouldFollowTail = isAtTail
        updatePagingAccessibilityValue()
    }
}
