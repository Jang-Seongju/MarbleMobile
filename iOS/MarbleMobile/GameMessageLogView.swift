import SwiftUI
import UIKit

/// Read-only live game log backed by UIKit's standard text view.
///
/// The app only supplies the current text. UITextView and VoiceOver own focus,
/// selection, scrolling, paging, and accessibility behavior.
struct GameMessageLogView: UIViewRepresentable {
    let messages: [String]

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
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
