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
        record("RESET build=textview-vo-focus-sync2-adjustable-reentry1")
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
            "build=textview-vo-focus-sync2-adjustable-reentry1",
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

    private struct NativeAccessibilityCandidate {
        let source: String
        let index: Int
        let element: UIAccessibilityElement
        let frame: CGRect
        let visibleHeightRatio: CGFloat
        let midpointInsideViewport: Bool
    }

    private enum ExternalEntryEdge: String {
        case top
        case bottom
    }

    private var messageRevision: Int = 0
    private var isMessageAccessibilityFocused = false
    private var savedViewportOffsetY: CGFloat?
    private var revisionWhenFocusLeft: Int?
    private var messagesAddedWhileOutside = false
    private var lastExternalFocusFrame: CGRect?
    private var pendingEntryOffsetY: CGFloat?
    private var pendingEntryEdge: ExternalEntryEdge?
    private var isExternalAdjustableFocusActive = false
    private var externallyAdjustedViewportOffsetY: CGFloat?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        GameMessageDiagnosticLog.shared.snapshot(self, label: "didMoveToWindow")
    }

    override func accessibilityElementDidBecomeFocused() {
        super.accessibilityElementDidBecomeFocused()
        isMessageAccessibilityFocused = true

        let adjustedViewportOffsetY = externallyAdjustedViewportOffsetY
        if !messagesAddedWhileOutside, let adjustedViewportOffsetY {
            // VoiceOver's system scroll-position control can move the UITextView
            // while message text itself is not focused. Treat that user-adjusted
            // viewport as authoritative instead of restoring the older offset
            // captured when focus originally left the message document.
            pendingEntryOffsetY = nil
            pendingEntryEdge = nil
            restoreViewport(offsetY: adjustedViewportOffsetY, edge: .top)
            externallyAdjustedViewportOffsetY = nil
            isExternalAdjustableFocusActive = false
            GameMessageDiagnosticLog.shared.record(
                String(
                    format: "FOCUS_REENTRY adjustedViewport=true targetY=%.1f savedY=%@ outsideAppend=false revision=%d leftRevision=%@",
                    adjustedViewportOffsetY,
                    savedViewportOffsetY.map { String(format: "%.1f", $0) } ?? "nil",
                    messageRevision,
                    revisionWhenFocusLeft.map(String.init) ?? "nil"
                )
            )
            messagesAddedWhileOutside = false
            revisionWhenFocusLeft = nil
            scheduleVoiceOverFocus(
                directionName: "adjustable-reentry",
                reason: "preserve-adjusted-viewport"
            )
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityFocus=became adjusted-viewport")
            return
        }

        externallyAdjustedViewportOffsetY = nil
        isExternalAdjustableFocusActive = false

        guard let targetOffsetY = reentryTargetOffsetY() else {
            pendingEntryOffsetY = nil
            pendingEntryEdge = nil
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityFocus=became native-entry")
            return
        }

        pendingEntryOffsetY = targetOffsetY
        pendingEntryEdge = inferredExternalEntryEdge()
        restoreViewportOffsetOnly(targetOffsetY)
        GameMessageDiagnosticLog.shared.record(
            String(
                format: "FOCUS_REENTRY edge=%@ targetY=%.1f savedY=%@ outsideAppend=%@ revision=%d leftRevision=%@",
                pendingEntryEdge?.rawValue ?? "pending-point",
                targetOffsetY,
                savedViewportOffsetY.map { String(format: "%.1f", $0) } ?? "nil",
                messagesAddedWhileOutside.description,
                messageRevision,
                revisionWhenFocusLeft.map(String.init) ?? "nil"
            )
        )
        messagesAddedWhileOutside = false
        revisionWhenFocusLeft = nil
        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityFocus=became restored")
    }

    override func accessibilityElementDidLoseFocus() {
        super.accessibilityElementDidLoseFocus()
        savedViewportOffsetY = contentOffset.y
        revisionWhenFocusLeft = messageRevision
        messagesAddedWhileOutside = false
        pendingEntryOffsetY = nil
        pendingEntryEdge = nil
        isMessageAccessibilityFocused = false
        GameMessageDiagnosticLog.shared.record(
            String(
                format: "FOCUS_LEFT savedY=%.1f revision=%d",
                contentOffset.y,
                messageRevision
            )
        )
        GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityFocus=lost")
    }

    fileprivate func recordAccessibilityFocusNotification(
        sequence: Int,
        focused: Any?,
        unfocused: Any?,
        assistiveTechnology: Any?
    ) {
        GameMessageDiagnosticLog.shared.record(
            "FOCUS_NOTIFICATION seq=\(sequence) tech=\(diagnosticScalar(assistiveTechnology)) "
            + "focused=[\(diagnosticAccessibilityObject(focused))] "
            + "unfocused=[\(diagnosticAccessibilityObject(unfocused))]"
        )
    }

    fileprivate func recordCurrentVoiceOverFocus(label: String, sequence: Int? = nil) {
        let current = UIAccessibility.focusedElement(using: .notificationVoiceOver)
        let seq = sequence.map(String.init) ?? "-"
        GameMessageDiagnosticLog.shared.record(
            "FOCUS_CURRENT_VO label=\(label) seq=\(seq) current=[\(diagnosticAccessibilityObject(current))] "
            + String(format: "offsetY=%.1f", contentOffset.y)
        )
    }

    private func diagnosticAccessibilityObject(_ element: Any?) -> String {
        guard let element else { return "nil" }
        let object = element as AnyObject
        var parts: [String] = [
            "type=\(String(reflecting: type(of: object)))",
            "id=\(String(describing: ObjectIdentifier(object)))"
        ]

        if object === self {
            parts.append("relation=self")
        }

        if let view = element as? UIView {
            let frame = UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)
            parts.append("kind=UIView")
            parts.append("relation=\(diagnosticViewRelation(view))")
            parts.append("frame=\(diagnosticRect(frame))")
            parts.append("isAX=\(view.isAccessibilityElement)")
            parts.append("windowSame=\(view.window === window)")
            if let label = diagnosticText(view.accessibilityLabel) {
                parts.append("label=\(label)")
            }
            if let value = diagnosticText(view.accessibilityValue) {
                parts.append("value=\(value)")
            }
        } else if let accessibilityElement = element as? UIAccessibilityElement {
            parts.append("kind=UIAccessibilityElement")
            parts.append("frame=\(diagnosticRect(accessibilityElement.accessibilityFrame))")
            parts.append("isAX=\(accessibilityElement.isAccessibilityElement)")
            if let label = diagnosticText(accessibilityElement.accessibilityLabel) {
                parts.append("label=\(label)")
            }
            if let value = diagnosticText(accessibilityElement.accessibilityValue) {
                parts.append("value=\(value)")
            }
            if let container = accessibilityElement.accessibilityContainer {
                let containerObject = container as AnyObject
                parts.append("containerType=\(String(reflecting: type(of: containerObject)))")
                parts.append("containerId=\(String(describing: ObjectIdentifier(containerObject)))")
                if containerObject === self {
                    parts.append("containerRelation=self")
                } else if let containerView = container as? UIView {
                    parts.append("containerRelation=\(diagnosticViewRelation(containerView))")
                }
            } else {
                parts.append("container=nil")
            }
        } else {
            parts.append("kind=other")
        }

        return parts.joined(separator: ",")
    }

    private func diagnosticViewRelation(_ view: UIView) -> String {
        if view === self { return "self" }
        if view.isDescendant(of: self) { return "descendant-of-textview" }
        if self.isDescendant(of: view) { return "ancestor-of-textview" }
        return "outside-textview"
    }

    private func diagnosticRect(_ rect: CGRect) -> String {
        if rect.isNull { return "null" }
        if rect.isInfinite { return "infinite" }
        return String(format: "{%.1f,%.1f,%.1f,%.1f}", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    private func diagnosticText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let compact = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return String(compact.prefix(120))
    }

    private func diagnosticScalar(_ value: Any?) -> String {
        guard let value else { return "nil" }
        return diagnosticText(String(describing: value)) ?? "empty"
    }

    /// Uses only the public UIAccessibilityContainer surface to discover UIKit's
    /// native text accessibility elements. The implementation intentionally does
    /// not depend on UIKit's private paragraph-element class name.
    private func visibleNativeAccessibilityFocusTarget(directionName: String) -> UIAccessibilityElement? {
        let methodCount = accessibilityElementCount()
        let explicitElements = accessibilityElements
        let explicitCount = explicitElements?.count
        let messageFrame = UIAccessibility.convertToScreenCoordinates(bounds, in: self)

        var visibleCandidates: [NativeAccessibilityCandidate] = []
        var seen = Set<ObjectIdentifier>()

        func consider(_ candidate: Any, source: String, index: Int) {
            guard let element = candidate as? UIAccessibilityElement else { return }
            let identity = ObjectIdentifier(element)
            guard seen.insert(identity).inserted else { return }
            guard element.isAccessibilityElement else { return }
            guard let container = element.accessibilityContainer,
                  (container as AnyObject) === self
            else { return }

            let frame = element.accessibilityFrame
            guard !frame.isNull, !frame.isInfinite, frame.height > 0, frame.intersects(messageFrame) else { return }

            let intersection = frame.intersection(messageFrame)
            let visibleHeightRatio = max(0, min(1, intersection.height / frame.height))
            let midpointInsideViewport = frame.midY >= messageFrame.minY && frame.midY <= messageFrame.maxY
            visibleCandidates.append(
                NativeAccessibilityCandidate(
                    source: source,
                    index: index,
                    element: element,
                    frame: frame,
                    visibleHeightRatio: visibleHeightRatio,
                    midpointInsideViewport: midpointInsideViewport
                )
            )
        }

        // NSObject/UIAccessibilityContainer can report NSNotFound-like sentinel
        // values on unsupported paths. Bound the diagnostic scan defensively.
        if methodCount > 0, methodCount <= 4_096 {
            for index in 0..<methodCount {
                if let element = accessibilityElement(at: index) {
                    consider(element, source: "method", index: index)
                }
            }
        }

        if let explicitElements {
            for (index, element) in explicitElements.enumerated() {
                consider(element, source: "array", index: index)
            }
        }

        visibleCandidates.sort { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) > 0.5 {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }

        GameMessageDiagnosticLog.shared.record(
            "AX_CONTAINER_ENUM direction=\(directionName) methodCount=\(methodCount) "
            + "arrayCount=\(explicitCount.map(String.init) ?? "nil") "
            + "visibleNative=\(visibleCandidates.count) messageFrame=\(diagnosticRect(messageFrame))"
        )

        for candidate in visibleCandidates.prefix(8) {
            let roundTripIndex = index(ofAccessibilityElement: candidate.element)
            GameMessageDiagnosticLog.shared.record(
                "AX_CONTAINER_VISIBLE direction=\(directionName) source=\(candidate.source) "
                + "index=\(candidate.index) roundTripIndex=\(roundTripIndex) "
                + String(
                    format: "visibleHeightRatio=%.3f midpointInside=%@ ",
                    candidate.visibleHeightRatio,
                    candidate.midpointInsideViewport.description
                )
                + "element=[\(diagnosticAccessibilityObject(candidate.element))]"
            )
        }

        // Prefer the first paragraph whose vertical midpoint is truly inside the
        // viewport. A paragraph with only a tiny clipped sliver at the top should
        // not become the new page's VoiceOver entry point. If no midpoint is in
        // the viewport (for example an unusually tall paragraph), fall back to
        // the element with the greatest visible-height ratio.
        let midpointTarget = visibleCandidates.first { $0.midpointInsideViewport }
        let fallbackTarget = visibleCandidates.sorted { lhs, rhs in
            if abs(lhs.visibleHeightRatio - rhs.visibleHeightRatio) > 0.001 {
                return lhs.visibleHeightRatio > rhs.visibleHeightRatio
            }
            if abs(lhs.frame.minY - rhs.frame.minY) > 0.5 {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }.first

        guard let target = midpointTarget ?? fallbackTarget else {
            GameMessageDiagnosticLog.shared.record(
                "AX_FOCUS_TARGET direction=\(directionName) result=none"
            )
            return nil
        }

        GameMessageDiagnosticLog.shared.record(
            "AX_FOCUS_TARGET direction=\(directionName) result=found "
            + "selection=\(midpointTarget != nil ? "midpoint" : "fallback-ratio") "
            + "source=\(target.source) index=\(target.index) "
            + "roundTripIndex=\(index(ofAccessibilityElement: target.element)) "
            + String(
                format: "visibleHeightRatio=%.3f midpointInside=%@ ",
                target.visibleHeightRatio,
                target.midpointInsideViewport.description
            )
            + "element=[\(diagnosticAccessibilityObject(target.element))]"
        )
        return target.element
    }

    private func currentVoiceOverNativeElementInMessage() -> UIAccessibilityElement? {
        guard let element = UIAccessibility.focusedElement(using: .notificationVoiceOver) as? UIAccessibilityElement,
              element.isAccessibilityElement,
              let container = element.accessibilityContainer,
              (container as AnyObject) === self
        else {
            return nil
        }

        let frame = element.accessibilityFrame
        let messageFrame = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
        guard !frame.isNull, !frame.isInfinite, frame.intersects(messageFrame) else { return nil }
        return element
    }

    private func scheduleVoiceOverFocus(
        directionName: String,
        reason: String,
        preferredTarget: UIAccessibilityElement? = nil
    ) {
        guard UIAccessibility.isVoiceOverRunning else {
            GameMessageDiagnosticLog.shared.record(
                "AX_FOCUS_REQUEST direction=\(directionName) reason=\(reason) posted=false voiceOver=false"
            )
            return
        }

        guard let target = preferredTarget ?? visibleNativeAccessibilityFocusTarget(directionName: directionName) else {
            GameMessageDiagnosticLog.shared.record(
                "AX_FOCUS_REQUEST direction=\(directionName) reason=\(reason) posted=false reasonDetail=no-visible-native-element"
            )
            return
        }

        recordCurrentVoiceOverFocus(label: "focus-request-before-schedule-\(directionName)-\(reason)")
        GameMessageDiagnosticLog.shared.record(
            "AX_FOCUS_REQUEST direction=\(directionName) reason=\(reason) scheduled=true "
            + "target=[\(diagnosticAccessibilityObject(target))]"
        )

        // Let the pageScrolled notification and the scroll return complete first.
        // No arbitrary delay is used: the focus hand-off is deferred by exactly
        // one main-runloop turn so VoiceOver does not race the page-scroll event.
        DispatchQueue.main.async { [weak self, target] in
            guard let self, self.window != nil else { return }
            UIAccessibility.post(notification: .layoutChanged, argument: target)
            GameMessageDiagnosticLog.shared.record(
                "AX_FOCUS_REQUEST direction=\(directionName) reason=\(reason) posted=true phase=next-runloop "
                + "target=[\(self.diagnosticAccessibilityObject(target))]"
            )
            self.recordCurrentVoiceOverFocus(label: "focus-request-after-post-\(directionName)-\(reason)")
        }
    }

    func noteAccessibilityFocusTransition(_ focused: Any?) {
        // Focus notifications and accessibilityElementDidLoseFocus() do not have
        // a documented relative ordering. Recognize an adjustable control first
        // so the capture works regardless of which callback VoiceOver delivers
        // first while moving away from a message paragraph.
        if accessibilityTraits(of: focused).contains(.adjustable) {
            if !isExternalAdjustableFocusActive {
                externallyAdjustedViewportOffsetY = nil
            }
            isExternalAdjustableFocusActive = true
            GameMessageDiagnosticLog.shared.record(
                "ADJUSTABLE_FOCUS active=true focused=[\(diagnosticAccessibilityObject(focused))]"
            )
            return
        }

        if isMessageAccessibilityFocused {
            isExternalAdjustableFocusActive = false
            return
        }

        if !isMessageAccessibilityObject(focused) {
            isExternalAdjustableFocusActive = false
            externallyAdjustedViewportOffsetY = nil
        }
    }

    func noteObservedContentOffsetChange(from oldOffset: CGPoint, to newOffset: CGPoint) {
        guard isExternalAdjustableFocusActive,
              abs(newOffset.y - oldOffset.y) > 0.5
        else { return }

        externallyAdjustedViewportOffsetY = clampedViewportOffsetY(newOffset.y)
        GameMessageDiagnosticLog.shared.record(
            String(
                format: "ADJUSTABLE_VIEWPORT_CAPTURE oldY=%.1f newY=%.1f capturedY=%.1f",
                oldOffset.y,
                newOffset.y,
                externallyAdjustedViewportOffsetY ?? newOffset.y
            )
        )
    }

    private func accessibilityTraits(of element: Any?) -> UIAccessibilityTraits {
        if let view = element as? UIView {
            return view.accessibilityTraits
        }
        if let accessibilityElement = element as? UIAccessibilityElement {
            return accessibilityElement.accessibilityTraits
        }
        return []
    }

    private func isMessageAccessibilityObject(_ element: Any?) -> Bool {
        guard let element else { return false }
        if (element as AnyObject) === self { return true }
        if let view = element as? UIView {
            return view === self || view.isDescendant(of: self)
        }
        if let accessibilityElement = element as? UIAccessibilityElement,
           let container = accessibilityElement.accessibilityContainer
        {
            return (container as AnyObject) === self
        }
        return false
    }

    private func clampedViewportOffsetY(_ proposedOffsetY: CGFloat) -> CGFloat {
        let minimumY = -adjustedContentInset.top
        let maximumY = max(
            minimumY,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
        return min(maximumY, max(minimumY, proposedOffsetY))
    }

    func noteExternalAccessibilityFocus(_ element: Any?) {
        let frame: CGRect?
        if let view = element as? UIView {
            frame = UIAccessibility.convertToScreenCoordinates(view.bounds, in: view)
        } else if let accessibilityElement = element as? UIAccessibilityElement {
            frame = accessibilityElement.accessibilityFrame
        } else {
            frame = nil
        }

        guard let frame, !frame.isNull, !frame.isInfinite else { return }
        let messageFrame = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
        guard !frame.intersects(messageFrame) else { return }
        lastExternalFocusFrame = frame
    }

    func noteMessageRevision(_ revision: Int) {
        guard revision != messageRevision else { return }
        let oldRevision = messageRevision
        messageRevision = revision

        if !isMessageAccessibilityFocused,
           let revisionWhenFocusLeft,
           revision > revisionWhenFocusLeft {
            messagesAddedWhileOutside = true
        }

        GameMessageDiagnosticLog.shared.record(
            "MESSAGE_REVISION old=\(oldRevision) new=\(revision) focused=\(isMessageAccessibilityFocused) "
            + "leftRevision=\(revisionWhenFocusLeft.map(String.init) ?? "nil") outsideAppend=\(messagesAddedWhileOutside)"
        )
    }

    // MARK: - UIAccessibilityReadingContent

    func accessibilityLineNumber(for point: CGPoint) -> Int {
        let lines = readingLines()
        guard !lines.isEmpty else { return NSNotFound }

        if let targetOffsetY = pendingEntryOffsetY {
            let entryEdge = pendingEntryEdge ?? inferredEntryEdge(fromScreenPoint: point)
            restoreViewport(offsetY: targetOffsetY, edge: entryEdge)
            if let entryLineNumber = visibleBoundaryLineNumber(in: lines, edge: entryEdge) {
                pendingEntryOffsetY = nil
                pendingEntryEdge = nil
                GameMessageDiagnosticLog.shared.record(
                    "FOCUS_REENTRY_LINE edge=\(entryEdge.rawValue) line=\(entryLineNumber) content=\(lines[entryLineNumber].content)"
                )
                return entryLineNumber
            }
            pendingEntryOffsetY = nil
            pendingEntryEdge = nil
        }

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

    private func reentryTargetOffsetY() -> CGFloat? {
        guard savedViewportOffsetY != nil || messagesAddedWhileOutside else { return nil }

        let topInset = adjustedContentInset.top
        let bottomInset = adjustedContentInset.bottom
        let minimumY = -topInset
        let maximumY = max(minimumY, contentSize.height - bounds.height + bottomInset)

        if messagesAddedWhileOutside {
            return maximumY
        }
        guard let savedViewportOffsetY else { return nil }
        return min(maximumY, max(minimumY, savedViewportOffsetY))
    }

    private func inferredExternalEntryEdge() -> ExternalEntryEdge? {
        guard let lastExternalFocusFrame else { return nil }
        let messageFrame = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
        return lastExternalFocusFrame.midY < messageFrame.midY ? .top : .bottom
    }

    private func inferredEntryEdge(fromScreenPoint point: CGPoint) -> ExternalEntryEdge {
        let messageFrame = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
        return point.y < messageFrame.midY ? .top : .bottom
    }

    private func restoreViewportOffsetOnly(_ offsetY: CGFloat) {
        UIView.performWithoutAnimation {
            setContentOffset(CGPoint(x: contentOffset.x, y: offsetY), animated: false)
            layoutIfNeeded()
        }
    }

    private func restoreViewport(offsetY: CGFloat, edge: ExternalEntryEdge) {
        UIView.performWithoutAnimation {
            setContentOffset(CGPoint(x: contentOffset.x, y: offsetY), animated: false)
            switch edge {
            case .top:
                anchorSelectionToVisiblePageStart()
            case .bottom:
                anchorSelectionToVisiblePageEnd()
            }
            setContentOffset(CGPoint(x: contentOffset.x, y: offsetY), animated: false)
            layoutIfNeeded()
        }
    }

    private func visibleBoundaryLineNumber(
        in lines: [ReadingLine],
        edge: ExternalEntryEdge
    ) -> Int? {
        let visibleRect = CGRect(origin: contentOffset, size: bounds.size)
        let visibleIndices = lines.indices.filter {
            lines[$0].frameInContentCoordinates.intersects(visibleRect)
        }
        guard let first = visibleIndices.first, let last = visibleIndices.last else { return nil }
        return edge == .top ? first : last
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
            let retainedTarget = currentVoiceOverNativeElementInMessage()
                ?? visibleNativeAccessibilityFocusTarget(directionName: "\(name)-boundary")

            // Consume vertical page gestures at the document boundary instead of
            // handing them back to VoiceOver, which previously allowed focus to
            // escape to the board and caused UITextView to reveal a stale paragraph.
            // Repeating the current page status gives VoiceOver boundary feedback,
            // then the current/visible native paragraph is retained on next runloop.
            UIAccessibility.post(notification: .pageScrolled, argument: status)
            scheduleVoiceOverFocus(
                directionName: name,
                reason: "boundary-retain",
                preferredTarget: retainedTarget
            )
            GameMessageDiagnosticLog.shared.record(
                String(
                    format: "AX_BOUNDARY_RETAIN direction=%@ handled=true offsetY=%.1f minY=%.1f maxY=%.1f pageHeight=%.1f status=%@ target=%@",
                    name,
                    contentOffset.y,
                    minimumY,
                    maximumY,
                    pageHeight,
                    status,
                    retainedTarget == nil ? "fallback-none" : "current-or-visible-native"
                )
            )
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll BOUNDARY direction=\(name)")
            recordCurrentVoiceOverFocus(label: "accessibilityScroll-boundary-\(name)")
            return true
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

        // The viewport has already moved. pageScrolled is posted first; the
        // layoutChanged focus hand-off is intentionally deferred by one main
        // runloop so the two accessibility notifications do not race each other.
        scheduleVoiceOverFocus(directionName: name, reason: "page-move")

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
        recordCurrentVoiceOverFocus(label: "accessibilityScroll-after-\(name)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll NEXT_RUNLOOP direction=\(name)")
            self.recordCurrentVoiceOverFocus(label: "accessibilityScroll-next-runloop-\(name)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll +250ms direction=\(name)")
            self.recordCurrentVoiceOverFocus(label: "accessibilityScroll-250ms-\(name)")
        }
        for (delay, label) in [(1.0, "1s"), (2.0, "2s"), (4.0, "4s")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                GameMessageDiagnosticLog.shared.snapshot(self, label: "accessibilityScroll +\(label) direction=\(name)")
                self.recordCurrentVoiceOverFocus(label: "accessibilityScroll-\(label)-\(name)")
            }
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

    private func anchorSelectionToVisiblePageEnd() {
        let probe = CGPoint(
            x: bounds.minX + textContainerInset.left + 1,
            y: max(bounds.minY + textContainerInset.top + 1, bounds.maxY - textContainerInset.bottom - 1)
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
        var accessibilityFocusObservation: NSObjectProtocol?
        private var accessibilityFocusSequence: Int = 0
        private var lastOffsetLogUptime: TimeInterval = 0

        deinit {
            contentOffsetObservation?.invalidate()
            contentSizeObservation?.invalidate()
            if let accessibilityFocusObservation {
                NotificationCenter.default.removeObserver(accessibilityFocusObservation)
            }
        }

        fileprivate func observe(_ textView: GameMessageTextView) {
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
                view.noteObservedContentOffsetChange(from: old, to: new)

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


            accessibilityFocusObservation = NotificationCenter.default.addObserver(
                forName: UIAccessibility.elementFocusedNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak textView] notification in
                guard let self, let textView else { return }
                self.accessibilityFocusSequence += 1
                let sequence = self.accessibilityFocusSequence
                let focused = notification.userInfo?[UIAccessibility.focusedElementUserInfoKey]
                let unfocused = notification.userInfo?[UIAccessibility.unfocusedElementUserInfoKey]
                let assistiveTechnology = notification.userInfo?[UIAccessibility.assistiveTechnologyUserInfoKey]
                textView.recordAccessibilityFocusNotification(
                    sequence: sequence,
                    focused: focused,
                    unfocused: unfocused,
                    assistiveTechnology: assistiveTechnology
                )
                DispatchQueue.main.async { [weak textView] in
                    textView?.recordCurrentVoiceOverFocus(label: "notification-next-runloop", sequence: sequence)
                }
                textView.noteAccessibilityFocusTransition(focused)
                if let focused, (focused as AnyObject) === textView {
                    return
                }
                textView.noteExternalAccessibilityFocus(focused)
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
            textView.noteMessageRevision(messages.count)
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

        // Controlled public-setter refresh test: keep true incremental TextKit 2
        // backing-store append for normal prefix growth, then pass that exact final
        // attributed document through UITextView.attributedText once.
        if !previous.isEmpty,
           !messages.isEmpty,
           messages.count >= previous.count,
           messages.starts(with: previous) {
            let newMessages = Array(messages.dropFirst(previous.count))
            guard !newMessages.isEmpty else { return }
            if append(newMessages, to: textView, existingMessageCount: previous.count) {
                context.coordinator.renderedMessages = messages
                (textView as? GameMessageTextView)?.noteMessageRevision(messages.count)
            }
            schedulePostMutationSnapshots(textView, label: "append new=\(newMessages.count)")
            return
        }

        if replaceWholeDocument(in: textView, with: messages, reason: "reset-or-placeholder-transition") {
            context.coordinator.renderedMessages = messages
            (textView as? GameMessageTextView)?.noteMessageRevision(messages.count)
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

        if success {
            let publicSetterDocument = NSAttributedString(attributedString: backingStore)
            GameMessageDiagnosticLog.shared.record(
                "PUBLIC_SETTER_REFRESH BEGIN view=\(ObjectIdentifier(textView)) length=\(publicSetterDocument.length)"
            )
            textView.attributedText = publicSetterDocument
            let refreshedLength = textView.attributedText.length
            let refreshedMatches = textView.attributedText.string == publicSetterDocument.string
            GameMessageDiagnosticLog.shared.record(
                "PUBLIC_SETTER_REFRESH END view=\(ObjectIdentifier(textView)) length=\(refreshedLength) "
                + "matches=\(refreshedMatches) selected={\(textView.selectedRange.location),\(textView.selectedRange.length)}"
            )
        }

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
