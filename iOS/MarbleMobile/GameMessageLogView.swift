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
        record("RESET build=textview-public-attributedtext-compare1")
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
            "build=textview-public-attributedtext-compare1",
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

private final class GameMessageTextView: UITextView, UIAccessibilityReadingContent {
    private struct ReadingLine {
        let content: String
        let frameInContentCoordinates: CGRect
    }

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

    // MARK: - UIAccessibilityReadingContent

    func accessibilityLineNumber(for point: CGPoint) -> Int {
        let lines = readingLines()
        guard !lines.isEmpty else { return NSNotFound }

        for (index, line) in lines.enumerated() {
            let screenFrame = UIAccessibility.convertToScreenCoordinates(
                line.frameInContentCoordinates.insetBy(dx: -2, dy: -1),
                in: self
            )
            if screenFrame.contains(point) {
                return index
            }
        }

        // VoiceOver may ask with a point that is horizontally outside the
        // typographic rect but vertically aligned with a readable line. Use the
        // nearest line on the same page instead of collapsing back to line 0.
        let nearest = lines.enumerated().min { lhs, rhs in
            let lhsFrame = UIAccessibility.convertToScreenCoordinates(lhs.element.frameInContentCoordinates, in: self)
            let rhsFrame = UIAccessibility.convertToScreenCoordinates(rhs.element.frameInContentCoordinates, in: self)
            return abs(lhsFrame.midY - point.y) < abs(rhsFrame.midY - point.y)
        }
        return nearest?.offset ?? NSNotFound
    }

    func accessibilityContent(forLineNumber lineNumber: Int) -> String? {
        let lines = readingLines()
        guard lines.indices.contains(lineNumber) else { return nil }
        return lines[lineNumber].content
    }

    func accessibilityFrame(forLineNumber lineNumber: Int) -> CGRect {
        let lines = readingLines()
        guard lines.indices.contains(lineNumber) else { return .zero }
        return UIAccessibility.convertToScreenCoordinates(
            lines[lineNumber].frameInContentCoordinates,
            in: self
        )
    }

    func accessibilityPageContent() -> String? {
        let lines = readingLines()
        guard !lines.isEmpty else { return text }

        let visibleRect = CGRect(origin: contentOffset, size: bounds.size)
        let visibleLines = lines.filter { $0.frameInContentCoordinates.intersects(visibleRect) }
        let pageLines = visibleLines.isEmpty ? lines : visibleLines
        return pageLines.map(\.content).joined(separator: "\n")
    }

    // MARK: - VoiceOver page scrolling

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let name = accessibilityScrollDirectionName(direction)
        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll BEFORE direction=\(name)")

        let deltaSign: CGFloat
        switch direction {
        case .down, .next:
            deltaSign = 1
        case .up, .previous:
            deltaSign = -1
        default:
            GameMessageDiagnosticLog.shared.record(
                "ACCESSIBILITY_SCROLL direction=\(name) handled=false unsupported=true"
            )
            return false
        }

        let topInset = adjustedContentInset.top
        let bottomInset = adjustedContentInset.bottom
        let minimumY = -topInset
        let maximumY = max(minimumY, contentSize.height - bounds.height + bottomInset)
        let pageHeight = max(1, bounds.height - topInset - bottomInset)
        let proposedY = contentOffset.y + (pageHeight * deltaSign)
        let targetY = min(maximumY, max(minimumY, proposedY))

        guard abs(targetY - contentOffset.y) > 0.5 else {
            let status = pageStatusString(offsetY: contentOffset.y, pageHeight: pageHeight, minimumY: minimumY)
            UIAccessibility.post(notification: .pageScrolled, argument: status)
            GameMessageDiagnosticLog.shared.record(
                String(
                    format: "ACCESSIBILITY_SCROLL direction=%@ handled=false boundary=true offsetY=%.1f minY=%.1f maxY=%.1f pageHeight=%.1f status=%@",
                    name,
                    contentOffset.y,
                    minimumY,
                    maximumY,
                    pageHeight,
                    status
                )
            )
            return false
        }

        // Do not delegate to UIScrollView's VoiceOver implementation here.
        // The diagnostic builds proved that the native path can move the
        // viewport and then restore it to the stale selection at document
        // offset 0. Move exactly one viewport ourselves and anchor the text
        // selection inside the new visible page before notifying VoiceOver.
        UIView.performWithoutAnimation {
            setContentOffset(CGPoint(x: contentOffset.x, y: targetY), animated: false)
            anchorSelectionToVisiblePageStart()
            // selectedRange changes can ask UITextView to reveal the caret.
            // Reassert the exact page offset so selection anchoring never turns
            // into an app-owned auto-scroll.
            setContentOffset(CGPoint(x: contentOffset.x, y: targetY), animated: false)
            layoutIfNeeded()
        }

        let status = pageStatusString(offsetY: targetY, pageHeight: pageHeight, minimumY: minimumY)
        UIAccessibility.post(notification: .pageScrolled, argument: status)

        GameMessageDiagnosticLog.shared.record(
            String(
                format: "ACCESSIBILITY_SCROLL direction=%@ handled=true targetY=%.1f minY=%.1f maxY=%.1f pageHeight=%.1f selected={%d,%d} status=%@",
                name,
                targetY,
                minimumY,
                maximumY,
                pageHeight,
                selectedRange.location,
                selectedRange.length,
                status
            )
        )
        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll AFTER direction=\(name)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll NEXT_RUNLOOP direction=\(name)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll +250ms direction=\(name)")
        }
        return true
    }

    private func readingLines() -> [ReadingLine] {
        guard let textLayoutManager else { return fallbackReadingLines() }

        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
        var lines: [ReadingLine] = []

        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { [weak self] layoutFragment in
            guard let self else { return false }
            let fragmentOrigin = layoutFragment.layoutFragmentFrame.origin

            for lineFragment in layoutFragment.textLineFragments {
                let source = lineFragment.attributedString.string as NSString
                let sourceRange = lineFragment.characterRange
                let rawContent: String
                if sourceRange.location != NSNotFound, NSMaxRange(sourceRange) <= source.length {
                    rawContent = source.substring(with: sourceRange)
                } else {
                    rawContent = lineFragment.attributedString.string
                }
                let content = rawContent.trimmingCharacters(in: .newlines)
                guard !content.isEmpty else { continue }

                let frame = lineFragment.typographicBounds.offsetBy(
                    dx: fragmentOrigin.x + textContainerInset.left,
                    dy: fragmentOrigin.y + textContainerInset.top
                )
                lines.append(
                    ReadingLine(
                        content: content,
                        frameInContentCoordinates: frame
                    )
                )
            }
            return true
        }

        return lines.isEmpty ? fallbackReadingLines() : lines
    }

    private func fallbackReadingLines() -> [ReadingLine] {
        let rawLines = (text ?? "").split(separator: "\n", omittingEmptySubsequences: false)
        let lineHeight = max(font?.lineHeight ?? 22, 1)
        return rawLines.enumerated().map { index, rawLine in
            ReadingLine(
                content: String(rawLine),
                frameInContentCoordinates: CGRect(
                    x: textContainerInset.left,
                    y: textContainerInset.top + (CGFloat(index) * lineHeight),
                    width: max(1, bounds.width - textContainerInset.left - textContainerInset.right),
                    height: lineHeight
                )
            )
        }
    }

    private func anchorSelectionToVisiblePageStart() {
        let probe = CGPoint(
            x: bounds.minX + textContainerInset.left + 1,
            y: bounds.minY + textContainerInset.top + 1
        )
        guard let position = closestPosition(to: probe) else { return }

        let characterOffset = offset(from: beginningOfDocument, to: position)
        guard characterOffset >= 0 else { return }
        let boundedOffset = min(characterOffset, textStorage.length)
        selectedRange = NSRange(location: boundedOffset, length: 0)
    }

    private func pageStatusString(offsetY: CGFloat, pageHeight: CGFloat, minimumY: CGFloat) -> String {
        let totalHeight = max(bounds.height, contentSize.height + adjustedContentInset.top + adjustedContentInset.bottom)
        let pageCount = max(1, Int(ceil(totalHeight / pageHeight)))
        let normalizedOffset = max(0, offsetY - minimumY)
        let pageIndex = min(pageCount, max(1, Int(round(normalizedOffset / pageHeight)) + 1))
        return "전체 \(pageCount)페이지 중 \(pageIndex)페이지"
    }

    private func accessibilityScrollDirectionName(_ direction: UIAccessibilityScrollDirection) -> String {
        switch direction {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .next: return "next"
        case .previous: return "previous"
        @unknown default: return "unknown"
        }
    }
}
/// Read-only continuous game-message document.
///
/// Normal growth uses the TextKit 2 backing store incrementally. VoiceOver
/// receives explicit reading-content geometry plus deterministic one-viewport
/// page scrolling so UIKit cannot snap the message document back to line 0.
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
        textView.accessibilityTraits.insert(.causesPageTurn)

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

        // A/B comparison against the incremental TextKit 2 backing-store path.
        // Keep the same UITextView, TextKit 2 configuration, styling, reading-content
        // implementation, page scrolling, and diagnostics, but route normal prefix
        // growth through UITextView's public attributedText setter. This tests whether
        // UIKit refreshes VoiceOver's internal text-accessibility state only when the
        // public UITextView API is used.
        if !previous.isEmpty,
           !messages.isEmpty,
           messages.count >= previous.count,
           messages.starts(with: previous) {
            let newMessageCount = messages.count - previous.count
            guard newMessageCount > 0 else { return }
            if replaceViaPublicAttributedText(
                in: textView,
                with: messages,
                reason: "prefix-public-attributedText new=\(newMessageCount)"
            ) {
                context.coordinator.renderedMessages = messages
            }
            schedulePostMutationSnapshots(
                textView,
                label: "publicAttributedText new=\(newMessageCount)"
            )
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

    private func replaceViaPublicAttributedText(
        in textView: UITextView,
        with messages: [GameRoomMessage],
        reason: String
    ) -> Bool {
        let document: NSAttributedString
        if messages.isEmpty {
            document = NSAttributedString(
                string: "게임 메시지가 없습니다.",
                attributes: placeholderAttributes
            )
        } else {
            document = attributedDocument(for: messages, includeLeadingSeparator: false)
        }

        let beforeContentManager = textView.textLayoutManager?.textContentManager
        let beforeContentStorage = beforeContentManager as? NSTextContentStorage
        let beforeBacking = beforeContentStorage?.attributedString
        let beforeSameBacking = beforeBacking.map { ($0 as AnyObject) === textView.textStorage } ?? false

        GameMessageDiagnosticLog.shared.record(
            "PUBLIC_ATTRIBUTEDTEXT BEGIN view=\(ObjectIdentifier(textView)) reason=\(reason) messages=\(messages.count) "
            + "oldText=\(((textView.text ?? "") as NSString).length) new=\(document.length) "
            + "tk2=\(textView.textLayoutManager != nil) sameBackingBefore=\(beforeSameBacking)"
        )

        // Deliberately use the UITextView public API here. Do not mutate the TextKit
        // backing store directly in this comparison path.
        textView.attributedText = document

        let afterContentManager = textView.textLayoutManager?.textContentManager
        let afterContentStorage = afterContentManager as? NSTextContentStorage
        let afterBacking = afterContentStorage?.attributedString
        let afterSameBacking = afterBacking.map { ($0 as AnyObject) === textView.textStorage } ?? false
        let textLength = ((textView.text ?? "") as NSString).length
        let storageLength = textView.textStorage.length
        let backingLength = afterBacking?.length ?? -1
        let success = textLength == document.length
            && storageLength == document.length
            && textView.attributedText.string == document.string

        GameMessageDiagnosticLog.shared.record(
            "PUBLIC_ATTRIBUTEDTEXT END view=\(ObjectIdentifier(textView)) reason=\(reason) "
            + "text=\(textLength) storage=\(storageLength) backing=\(backingLength) "
            + "tk2=\(textView.textLayoutManager != nil) sameBackingAfter=\(afterSameBacking) success=\(success)"
        )
        GameMessageDiagnosticLog.shared.snapshot(
            textView,
            label: "publicAttributedText IMMEDIATE reason=\(reason)"
        )
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
