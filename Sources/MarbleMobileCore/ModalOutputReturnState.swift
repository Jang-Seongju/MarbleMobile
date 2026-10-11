import Foundation

/// UI-only lifecycle. Server completion revokes input before the physical modal
/// disappears; its output boundary belongs after the causal result presentation.
public struct ModalOutputReturnState: Equatable, Sendable {
    public enum Boundary: Equatable, Sendable {
        case aiSelection(requestID: String)
        case interaction(flowID: String)
    }

    public enum Phase: Equatable, Sendable {
        case awaitingResult
        case dismissing
        case awaitingFocus
    }

    public struct Pending: Equatable, Sendable {
        public let token: UUID
        public let boundary: Boundary
        public fileprivate(set) var returnScheduled = false
        public fileprivate(set) var phase: Phase = .awaitingResult
    }

    public private(set) var pending: Pending?

    public init() {}

    public var canReturnEarly: Bool {
        pending?.returnScheduled == true && pending?.phase == .awaitingResult
    }

    public mutating func begin(_ boundary: Boundary) {
        if pending?.boundary == boundary { return }
        pending = Pending(token: UUID(), boundary: boundary)
    }

    /// Schedule exactly once, at the wire boundary after the result was enqueued.
    public mutating func scheduleReturn(after boundary: Boundary) -> UUID? {
        guard var item = pending, item.boundary == boundary,
              item.phase == .awaitingResult, !item.returnScheduled else { return nil }
        item.returnScheduled = true
        pending = item
        return item.token
    }

    /// Both automatic completion and intentional early navigation use this path.
    public mutating func beginDismissal(token: UUID) -> Bool {
        guard var item = pending, item.token == token,
              item.returnScheduled, item.phase == .awaitingResult else { return false }
        item.phase = .dismissing
        pending = item
        return true
    }

    public mutating func didDismiss(_ boundary: Boundary) -> UUID? {
        guard var item = pending, item.boundary == boundary,
              item.phase == .dismissing else { return nil }
        item.phase = .awaitingFocus
        pending = item
        return item.token
    }

    public mutating func finishFocusReturn(token: UUID) -> Bool {
        guard pending?.token == token, pending?.phase == .awaitingFocus else { return false }
        pending = nil
        return true
    }

    public mutating func cancel() {
        pending = nil
    }
}
