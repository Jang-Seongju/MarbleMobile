import Foundation
import XCTest
@testable import MarbleMobileCore

final class ModalOutputReturnTests: XCTestCase {
    func testResultMustBeScheduledBeforePhysicalDismissal() throws {
        var state = ModalOutputReturnState()
        let boundary = ModalOutputReturnState.Boundary.interaction(flowID: "build")
        state.begin(boundary)
        let token = try XCTUnwrap(state.pending?.token)
        XCTAssertFalse(state.canReturnEarly)
        XCTAssertFalse(state.beginDismissal(token: token))
        XCTAssertNil(state.didDismiss(boundary))
        XCTAssertFalse(state.finishFocusReturn(token: token))
        XCTAssertEqual(state.scheduleReturn(after: boundary), token)
        XCTAssertTrue(state.canReturnEarly)
        XCTAssertTrue(state.beginDismissal(token: token))
        XCTAssertFalse(state.canReturnEarly)
        XCTAssertEqual(state.didDismiss(boundary), token)
        XCTAssertTrue(state.finishFocusReturn(token: token))
        XCTAssertNil(state.pending)
    }

    func testDuplicateServerCompletionAndDismissCallbacksDoNotRepeatReturn() throws {
        var state = ModalOutputReturnState()
        let boundary = ModalOutputReturnState.Boundary.interaction(flowID: "acquire")
        state.begin(boundary)
        let token = try XCTUnwrap(state.scheduleReturn(after: boundary))
        state.begin(boundary)
        XCTAssertEqual(state.pending?.token, token)
        XCTAssertNil(state.scheduleReturn(after: boundary))
        XCTAssertTrue(state.beginDismissal(token: token))
        XCTAssertFalse(state.beginDismissal(token: token))
        XCTAssertEqual(state.didDismiss(boundary), token)
        XCTAssertNil(state.didDismiss(boundary))
        XCTAssertTrue(state.finishFocusReturn(token: token))
        XCTAssertFalse(state.finishFocusReturn(token: token))
    }

    func testEarlyReturnMakesOldAutomaticBoundaryHarmlessToNextFlow() throws {
        var state = ModalOutputReturnState()
        let first = ModalOutputReturnState.Boundary.interaction(flowID: "first")
        state.begin(first)
        let oldToken = try XCTUnwrap(state.scheduleReturn(after: first))
        XCTAssertTrue(state.beginDismissal(token: oldToken))
        XCTAssertEqual(state.didDismiss(first), oldToken)
        XCTAssertTrue(state.finishFocusReturn(token: oldToken))

        let next = ModalOutputReturnState.Boundary.interaction(flowID: "next")
        state.begin(next)
        let newToken = try XCTUnwrap(state.scheduleReturn(after: next))
        XCTAssertFalse(state.beginDismissal(token: oldToken))
        XCTAssertNil(state.didDismiss(first))
        XCTAssertFalse(state.finishFocusReturn(token: oldToken))
        XCTAssertEqual(state.pending?.token, newToken)
        XCTAssertEqual(state.pending?.phase, .awaitingResult)
    }

    func testAISelectionWaitsForFestivalBoundaryAndSurvivesUnrelatedCallbacks() throws {
        var state = ModalOutputReturnState()
        let ai = ModalOutputReturnState.Boundary.aiSelection(requestID: "ai-request")
        state.begin(ai)
        XCTAssertNil(state.scheduleReturn(after: .interaction(flowID: "old-flow")))
        XCTAssertNil(state.didDismiss(ai))
        let token = try XCTUnwrap(state.scheduleReturn(after: ai))
        XCTAssertTrue(state.beginDismissal(token: token))
        XCTAssertNil(state.didDismiss(.aiSelection(requestID: "old-request")))
        XCTAssertEqual(state.didDismiss(ai), token)
        XCTAssertTrue(state.finishFocusReturn(token: token))
    }

    func testRecoveryOrCancellationInvalidatesQueuedReturn() throws {
        var state = ModalOutputReturnState()
        let boundary = ModalOutputReturnState.Boundary.interaction(flowID: "disconnected")
        state.begin(boundary)
        let token = try XCTUnwrap(state.scheduleReturn(after: boundary))
        state.cancel()
        XCTAssertFalse(state.beginDismissal(token: token))
        XCTAssertNil(state.didDismiss(boundary))
        XCTAssertFalse(state.finishFocusReturn(token: token))
        XCTAssertNil(state.pending)
    }
}
