import SwiftUI
import UIKit

/// Read-only live game log.
///
/// The log deliberately owns no document-style reading-position model. New messages
/// append at the tail and the visual viewport follows the tail. VoiceOver can still
/// traverse each message independently. A label-less adjustable accessibility element
/// provides one-screen backward/forward paging without adding visible controls.
struct GameMessageLogView: UIViewRepresentable {
    let messages: [String]
    let focusLatestRequest: Int

    func makeUIView(context: Context) -> GameMessageLogUIView {
        let view = GameMessageLogUIView()
        view.update(messages: messages, focusLatestRequest: focusLatestRequest)
        return view
    }

    func updateUIView(_ uiView: GameMessageLogUIView, context: Context) {
        uiView.update(messages: messages, focusLatestRequest: focusLatestRequest)
    }
}

private final class MessageLogPagingElement: UIAccessibilityElement {
    weak var logView: GameMessageLogUIView?

    override func accessibilityIncrement() {
        // VoiceOver one-finger swipe up: one screen toward older messages.
        logView?.pageTowardOlderMessages()
    }

    override func accessibilityDecrement() {
        // VoiceOver one-finger swipe down: one screen toward newer messages.
        logView?.pageTowardNewerMessages()
    }
}

final class GameMessageLogUIView: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var messageLabels: [UILabel] = []
    private var renderedMessages: [String] = []
    private var lastFocusLatestRequest = 0
    private lazy var pagingElement: MessageLogPagingElement = {
        let element = MessageLogPagingElement(accessibilityContainer: self)
        element.logView = self
        element.isAccessibilityElement = true
        element.accessibilityTraits = [.adjustable]
        // Do not manufacture a label/value. VoiceOver should expose the system role
        // and any native page feedback it can derive from the scroll operation.
        return element
    }()

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
        pagingElement.accessibilityFrameInContainerSpace = bounds
    }

    func update(messages: [String], focusLatestRequest: Int) {
        let wasEmpty = renderedMessages.isEmpty
        let isPureAppend = !renderedMessages.isEmpty
            && messages.count >= renderedMessages.count
            && Array(messages.prefix(renderedMessages.count)) == renderedMessages

        if messages != renderedMessages {
            if isPureAppend {
                for message in messages.dropFirst(renderedMessages.count) {
                    appendMessageLabel(message)
                }
            } else {
                rebuildMessageLabels(messages)
            }
            renderedMessages = messages
            refreshAccessibilityElements()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layoutIfNeeded()
                self.scrollToLatest(animated: !wasEmpty)
            }
        }

        if focusLatestRequest != lastFocusLatestRequest {
            lastFocusLatestRequest = focusLatestRequest
            DispatchQueue.main.async { [weak self] in
                self?.focusLatestMessage()
            }
        }
    }

    fileprivate func pageTowardOlderMessages() {
        page(by: -visiblePageHeight)
    }

    fileprivate func pageTowardNewerMessages() {
        page(by: visiblePageHeight)
    }

    private func configure() {
        isAccessibilityElement = false
        clipsToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.isAccessibilityElement = false
        addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 6
        scrollView.addSubview(stackView)

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
        ])

        rebuildMessageLabels([])
        refreshAccessibilityElements()
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
            appendMessageLabel(message)
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

    private func makeLabel(_ text: String, secondary: Bool) -> UILabel {
        let label = UILabel()
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

    private func refreshAccessibilityElements() {
        // Messages remain ordinary VoiceOver text elements. The paging element is a
        // separate accessibility-only control occupying no visual layout space.
        accessibilityElements = messageLabels.map { $0 as Any } + [pagingElement]
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

    private func scrollToLatest(animated: Bool) {
        layoutIfNeeded()
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maximumOffsetY),
            animated: animated
        )
    }

    private func page(by delta: CGFloat) {
        layoutIfNeeded()
        let current = scrollView.contentOffset.y
        let target = min(maximumOffsetY, max(minimumOffsetY, current + delta))
        guard abs(target - current) > 0.5 else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIAccessibility.post(notification: .pageScrolled, argument: nil)
        }
    }

    private func focusLatestMessage() {
        layoutIfNeeded()
        scrollToLatest(animated: false)
        guard let latest = messageLabels.last else { return }
        UIAccessibility.post(notification: .layoutChanged, argument: latest)
    }
}
