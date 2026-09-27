import Foundation
import SwiftUI
import UIKit

/// Temporary in-memory diagnostics for the game-message text view.
///
/// Nothing is written to the app's visible message stream. The user can copy the
/// accumulated text from the game-room menu and paste it into ChatGPT for analysis.
final class GameMessageDiagnosticLog {
    static let shared = GameMessageDiagnosticLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let maximumLineCount = 1_200
    private weak var currentTextView: UITextView?

    private init() {}

    func attach(_ textView: UITextView) {
        currentTextView = textView
        record("ATTACH view=\(ObjectIdentifier(textView))")
    }

    func snapshotCurrent(_ label: String) {
        guard let currentTextView else {
            record("SNAP \(label) currentTextView=nil")
            return
        }
        snapshot(currentTextView, label: label)
    }

    func reset() {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        lock.unlock()
        record("RESET build=textview-textkit2-diagnostic1")
    }

    func record(_ message: String) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let line = String(format: "%.3f %@", uptime, message)

        lock.lock()
        lines.append(line)
        if lines.count > maximumLineCount {
            lines.removeFirst(lines.count - maximumLineCount)
        }
        lock.unlock()
    }

    func exportText() -> String {
        lock.lock()
        let snapshot = lines
        lock.unlock()

        let header = [
            "MarbleMobile message diagnostics",
            "build=textview-textkit2-diagnostic1",
            "lines=\(snapshot.count)",
            "---"
        ]
        return (header + snapshot).joined(separator: "\n")
    }

    func snapshot(_ textView: UITextView, label: String) {
        let text = textView.text ?? ""
        let textUTF16Length = (text as NSString).length
        let storageLength = textView.textStorage.length
        let layoutManagerPresent = textView.textLayoutManager != nil
        let contentManager = textView.textLayoutManager?.textContentManager
        let contentStorage = contentManager as? NSTextContentStorage
        let backing = contentStorage?.attributedString
        let backingLength = backing?.length ?? -1
        let sameBacking: Bool
        if let backing {
            sameBacking = (backing as AnyObject) === textView.textStorage
        } else {
            sameBacking = false
        }

        let suffix = String(text.suffix(120))
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        record(
            "SNAP \(label) "
            + "view=\(ObjectIdentifier(textView)) "
            + "window=\(textView.window != nil) voiceOver=\(UIAccessibility.isVoiceOverRunning) "
            + "editable=\(textView.isEditable) selectable=\(textView.isSelectable) scrollEnabled=\(textView.isScrollEnabled) "
            + "tk2=\(layoutManagerPresent) contentManager=\(contentManager.map { String(describing: type(of: $0)) } ?? "nil") "
            + "backing=\(backing.map { String(describing: type(of: $0)) } ?? "nil") sameBacking=\(sameBacking) "
            + "textUTF16=\(textUTF16Length) storage=\(storageLength) backing=\(backingLength) "
            + "selected={\(textView.selectedRange.location),\(textView.selectedRange.length)} "
            + String(format: "offset={%.1f,%.1f} content={%.1f,%.1f} bounds={%.1f,%.1f} inset={%.1f,%.1f,%.1f,%.1f}",
                     textView.contentOffset.x,
                     textView.contentOffset.y,
                     textView.contentSize.width,
                     textView.contentSize.height,
                     textView.bounds.width,
                     textView.bounds.height,
                     textView.adjustedContentInset.top,
                     textView.adjustedContentInset.left,
                     textView.adjustedContentInset.bottom,
                     textView.adjustedContentInset.right)
            + " suffix=\"\(suffix)\""
        )
    }
}

private final class GameMessageTextView: UITextView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        GameMessageDiagnosticLog.shared.snapshot(self, label: "didMoveToWindow")
    }

    override func accessibilityElementDidBecomeFocused() {
        super.accessibilityElementDidBecomeFocused()
        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityFocus=became")
    }

    override func accessibilityElementDidLoseFocus() {
        super.accessibilityElementDidLoseFocus()
        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityFocus=lost")
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let name: String
        switch direction {
        case .up: name = "up"
        case .down: name = "down"
        case .left: name = "left"
        case .right: name = "right"
        case .next: name = "next"
        case .previous: name = "previous"
        @unknown default: name = "unknown"
        }

        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll BEFORE direction=\(name)")
        let result = super.accessibilityScroll(direction)
        GameMessageDiagnosticLog.shared.record("ACCESSIBILITY_SCROLL direction=\(name) superResult=\(result)")
        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll AFTER direction=\(name)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll NEXT_RUNLOOP direction=\(name)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll +250ms direction=\(name)")
        }
        return result
    }
}

/// Read-only continuous game-message document.
///
/// The TextKit 2 backing document is kept stable. Normal message growth appends
/// only the new attributed suffix inside an NSTextContentStorage edit transaction;
/// the existing document is not rebuilt.
struct GameMessageLogView: UIViewRepresentable {
    let messages: [GameRoomMessage]

    final class Coordinator: NSObject {
        var renderedMessages: [GameRoomMessage] = []
        var contentOffsetObservation: NSKeyValueObservation?
        var contentSizeObservation: NSKeyValueObservation?
        private var lastOffsetLogUptime: TimeInterval = 0

        deinit {
            contentOffsetObservation?.invalidate()
            contentSizeObservation?.invalidate()
        }

        func observe(_ textView: UITextView) {
            contentOffsetObservation = textView.observe(
                \.contentOffset,
                options: [.old, .new]
            ) { [weak self] view, change in
                guard let self,
                      let old = change.oldValue,
                      let new = change.newValue,
                      old != new
                else { return }

                let now = ProcessInfo.processInfo.systemUptime
                let dy = abs(new.y - old.y)
                if now - self.lastOffsetLogUptime >= 0.05 || dy >= 40 {
                    self.lastOffsetLogUptime = now
                    GameMessageDiagnosticLog.shared.record(
                        String(
                            format: "KVO contentOffset view=%@ old={%.1f,%.1f} new={%.1f,%.1f} deltaY=%.1f",
                            String(describing: ObjectIdentifier(view)),
                            old.x,
                            old.y,
                            new.x,
                            new.y,
                            new.y - old.y
                        )
                    )
                }
            }

            contentSizeObservation = textView.observe(
                \.contentSize,
                options: [.old, .new]
            ) { view, change in
                guard let old = change.oldValue,
                      let new = change.newValue,
                      old != new
                else { return }
                GameMessageDiagnosticLog.shared.record(
                    String(
                        format: "KVO contentSize view=%@ old={%.1f,%.1f} new={%.1f,%.1f}",
                        String(describing: ObjectIdentifier(view)),
                        old.width,
                        old.height,
                        new.width,
                        new.height
                    )
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        // Explicitly request TextKit 2 so this diagnostic build has no ambiguity
        // about which text engine owns the backing document.
        let textView = GameMessageTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = false
        textView.showsVerticalScrollIndicator = true

        context.coordinator.observe(textView)
        GameMessageDiagnosticLog.shared.attach(textView)
        GameMessageDiagnosticLog.shared.record(
            "MAKE view=\(ObjectIdentifier(textView)) incoming=\(messages.count) tk2=\(textView.textLayoutManager != nil)"
        )

        if replaceWholeDocument(in: textView, with: messages, reason: "initial") {
            context.coordinator.renderedMessages = messages
        }
        schedulePostMutationSnapshots(textView, label: "initial")
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let previous = context.coordinator.renderedMessages
        guard previous != messages else { return }

        GameMessageDiagnosticLog.shared.record(
            "UPDATE view=\(ObjectIdentifier(textView)) rendered=\(previous.count) incoming=\(messages.count) "
            + "isPrefix=\(messages.count >= previous.count && messages.starts(with: previous))"
        )
        GameMessageDiagnosticLog.shared.snapshot(textView, label: "update BEFORE")

        // A normal game/chat update grows the existing document. Placeholder
        // transitions, room reset, or any non-prefix replacement are true document
        // replacements and intentionally take the rare full-rebuild path.
        if !previous.isEmpty,
           !messages.isEmpty,
           messages.count >= previous.count,
           messages.starts(with: previous) {
            let newMessages = Array(messages.dropFirst(previous.count))
            guard !newMessages.isEmpty else { return }
            if append(newMessages, to: textView, existingMessageCount: previous.count) {
                context.coordinator.renderedMessages = messages
            }
            schedulePostMutationSnapshots(textView, label: "append new=\(newMessages.count)")
            return
        }

        if replaceWholeDocument(in: textView, with: messages, reason: "reset-or-placeholder-transition") {
            context.coordinator.renderedMessages = messages
        }
        schedulePostMutationSnapshots(textView, label: "fullReplace")
    }

    private func append(
        _ newMessages: [GameRoomMessage],
        to textView: UITextView,
        existingMessageCount: Int
    ) -> Bool {
        guard let contentStorage = textView.textLayoutManager?.textContentManager as? NSTextContentStorage,
              let backingStore = contentStorage.attributedString as? NSMutableAttributedString
        else {
            GameMessageDiagnosticLog.shared.record(
                "APPEND FAIL missing mutable NSTextContentStorage backing view=\(ObjectIdentifier(textView))"
            )
            return false
        }

        let suffix = attributedDocument(
            for: newMessages,
            includeLeadingSeparator: existingMessageCount > 0
        )
        let beforeBackingLength = backingStore.length
        let beforeTextStorageLength = textView.textStorage.length
        let sameBacking = (backingStore as AnyObject) === textView.textStorage

        GameMessageDiagnosticLog.shared.record(
            "APPEND BEGIN view=\(ObjectIdentifier(textView)) new=\(newMessages.count) "
            + "suffix=\(suffix.length) backingBefore=\(beforeBackingLength) storageBefore=\(beforeTextStorageLength) "
            + "sameBacking=\(sameBacking) transactionBefore=\(contentStorage.hasEditingTransaction)"
        )

        contentStorage.performEditingTransaction {
            GameMessageDiagnosticLog.shared.record(
                "APPEND TRANSACTION view=\(ObjectIdentifier(textView)) active=\(contentStorage.hasEditingTransaction)"
            )
            backingStore.append(suffix)
        }

        let expectedLength = beforeBackingLength + suffix.length
        let backingLength = backingStore.length
        let textStorageLength = textView.textStorage.length
        let textLength = ((textView.text ?? "") as NSString).length
        let suffixMatches = backingStore.string.hasSuffix(suffix.string)
        let success = backingLength == expectedLength && suffixMatches

        GameMessageDiagnosticLog.shared.record(
            "APPEND END view=\(ObjectIdentifier(textView)) expected=\(expectedLength) "
            + "backing=\(backingLength) storage=\(textStorageLength) text=\(textLength) "
            + "suffixMatches=\(suffixMatches) transactionAfter=\(contentStorage.hasEditingTransaction) success=\(success)"
        )
        GameMessageDiagnosticLog.shared.snapshot(textView, label: "append IMMEDIATE")
        return success
    }

    private func replaceWholeDocument(
        in textView: UITextView,
        with messages: [GameRoomMessage],
        reason: String
    ) -> Bool {
        guard let contentStorage = textView.textLayoutManager?.textContentManager as? NSTextContentStorage,
              let backingStore = contentStorage.attributedString as? NSMutableAttributedString
        else {
            GameMessageDiagnosticLog.shared.record(
                "REPLACE FAIL reason=\(reason) missing mutable NSTextContentStorage backing view=\(ObjectIdentifier(textView))"
            )
            return false
        }

        let document: NSAttributedString
        if messages.isEmpty {
            document = NSAttributedString(
                string: "게임 메시지가 없습니다.",
                attributes: placeholderAttributes
            )
        } else {
            document = attributedDocument(for: messages, includeLeadingSeparator: false)
        }

        GameMessageDiagnosticLog.shared.record(
            "REPLACE BEGIN view=\(ObjectIdentifier(textView)) reason=\(reason) messages=\(messages.count) "
            + "old=\(backingStore.length) new=\(document.length) sameBacking=\((backingStore as AnyObject) === textView.textStorage)"
        )

        contentStorage.performEditingTransaction {
            backingStore.setAttributedString(document)
        }

        let success = backingStore.length == document.length && backingStore.string == document.string
        GameMessageDiagnosticLog.shared.record(
            "REPLACE END view=\(ObjectIdentifier(textView)) reason=\(reason) "
            + "backing=\(backingStore.length) storage=\(textView.textStorage.length) text=\(((textView.text ?? "") as NSString).length) success=\(success)"
        )
        GameMessageDiagnosticLog.shared.snapshot(textView, label: "replace IMMEDIATE reason=\(reason)")
        return success
    }

    private func attributedDocument(
        for messages: [GameRoomMessage],
        includeLeadingSeparator: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var needsSeparator = includeLeadingSeparator

        for message in messages {
            if needsSeparator {
                result.append(NSAttributedString(string: "\n", attributes: standardAttributes))
            }
            result.append(
                NSAttributedString(
                    string: message.text,
                    attributes: attributes(for: message.kind)
                )
            )
            needsSeparator = true
        }
        return result
    }

    private var standardAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label
        ]
    }

    private var placeholderAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.secondaryLabel
        ]
    }

    private func attributes(for kind: GameRoomMessage.Kind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .standard:
            return standardAttributes
        case .chat:
            return [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.systemYellow
            ]
        }
    }

    private func schedulePostMutationSnapshots(_ textView: UITextView, label: String) {
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            GameMessageDiagnosticLog.shared.snapshot(textView, label: "\(label) NEXT_RUNLOOP")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak textView] in
            guard let textView else { return }
            GameMessageDiagnosticLog.shared.snapshot(textView, label: "\(label) +250ms")
        }
    }
}
