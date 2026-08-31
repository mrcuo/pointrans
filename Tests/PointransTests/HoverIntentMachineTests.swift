import CoreGraphics
import Carbon.HIToolbox
import XCTest

final class HoverIntentMachineTests: XCTestCase {
    func testJitterKeepsOneDwellAndTriggersFixedAnchor() {
        var machine = HoverIntentMachine(configuration: .init(
            anchorRadius: 5,
            rearmRadius: 18,
            maximumVelocity: 90,
            dwellDuration: 0.25
        ))
        let anchor = CGPoint(x: 100, y: 100)

        XCTAssertEqual(machine.modifierPressed(at: anchor, timestamp: 1), [.scheduleDwell(generation: 1, delay: 0.25)])
        XCTAssertEqual(machine.pointerMoved(to: CGPoint(x: 102, y: 101), timestamp: 1.1), [])
        XCTAssertEqual(machine.dwellElapsed(generation: 1), [.extract(anchor: anchor, generation: 1)])
    }

    func testFastMovementRearmsAtNewAnchor() {
        var machine = HoverIntentMachine()
        _ = machine.modifierPressed(at: .zero, timestamp: 1)
        let actions = machine.pointerMoved(to: CGPoint(x: 30, y: 0), timestamp: 1.05)

        XCTAssertEqual(actions, [
            .cancelDwell,
            .scheduleDwell(generation: 2, delay: machine.configuration.dwellDuration)
        ])
        XCTAssertEqual(machine.dwellElapsed(generation: 1), [])
        XCTAssertEqual(machine.dwellElapsed(generation: 2), [.extract(anchor: CGPoint(x: 30, y: 0), generation: 2)])
    }

    func testSlowMovementBeyondAnchorRadiusStartsOneNewDwell() {
        var machine = HoverIntentMachine(configuration: .init(
            anchorRadius: 5,
            rearmRadius: 18,
            maximumVelocity: 90,
            dwellDuration: 0.25
        ))
        _ = machine.modifierPressed(at: CGPoint(x: 100, y: 100), timestamp: 1)

        XCTAssertEqual(machine.pointerMoved(to: CGPoint(x: 103, y: 100), timestamp: 1.2), [])
        let actions = machine.pointerMoved(to: CGPoint(x: 106, y: 100), timestamp: 1.8)

        XCTAssertEqual(actions, [
            .cancelDwell,
            .scheduleDwell(generation: 2, delay: 0.25)
        ])
        XCTAssertEqual(machine.dwellElapsed(generation: 1), [])
        XCTAssertEqual(machine.dwellElapsed(generation: 2), [
            .extract(anchor: CGPoint(x: 106, y: 100), generation: 2)
        ])
    }

    func testReleaseCancelsExtractionButPinnedSurvives() {
        var machine = HoverIntentMachine()
        _ = machine.modifierPressed(at: .zero, timestamp: 0)
        _ = machine.dwellElapsed(generation: 1)
        XCTAssertEqual(machine.modifierReleased(), [.cancelExtraction])
        XCTAssertEqual(machine.state, .idle)

        _ = machine.modifierPressed(at: .zero, timestamp: 1)
        _ = machine.dwellElapsed(generation: 2)
        let id = UUID()
        machine.extractionSucceeded(sessionID: id, generation: 2)
        machine.pinPreview()
        XCTAssertEqual(machine.modifierReleased(), [])
        XCTAssertEqual(machine.state, .pinned(anchor: .zero, sessionID: id))
    }

    func testFailureSchedulesRetryAtOriginalPoint() {
        var machine = HoverIntentMachine(configuration: .init(dwellDuration: 0.3))
        let anchor = CGPoint(x: -240, y: 900)
        _ = machine.modifierPressed(at: anchor, timestamp: 1)
        _ = machine.dwellElapsed(generation: 1)

        XCTAssertEqual(machine.extractionFailed(generation: 1), [.scheduleDwell(generation: 2, delay: 0.3)])
        XCTAssertEqual(machine.dwellElapsed(generation: 2), [.extract(anchor: anchor, generation: 2)])
        XCTAssertEqual(machine.extractionFailed(generation: 2), [])
        XCTAssertEqual(machine.state, .armed(anchor: anchor, generation: 2))
    }

    func testResetInvalidatesOlderGeneration() {
        var machine = HoverIntentMachine()
        _ = machine.modifierPressed(at: .zero, timestamp: 1)
        machine.reset()

        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.dwellElapsed(generation: 1), [])
        XCTAssertEqual(machine.modifierPressed(at: .zero, timestamp: 2), [
            .scheduleDwell(generation: 3, delay: machine.configuration.dwellDuration)
        ])
    }

    func testIdleMouseMovementIsNotForwardedToMainActor() {
        XCTAssertFalse(EventTapRoutingPolicy.shouldForward(
            type: .mouseMoved,
            modifierIsDown: false,
            tracksPreviewPointer: false
        ))
        XCTAssertTrue(EventTapRoutingPolicy.shouldForward(
            type: .mouseMoved,
            modifierIsDown: true,
            tracksPreviewPointer: false
        ))
        XCTAssertTrue(EventTapRoutingPolicy.shouldForward(
            type: .mouseMoved,
            modifierIsDown: false,
            tracksPreviewPointer: true
        ))
    }

    func testOnlyLeftOptionIsAcceptedAsTheFixedTrigger() {
        XCTAssertTrue(FixedTriggerPolicy.acceptsModifierTransition(
            keyCode: CGKeyCode(kVK_Option)
        ))
        XCTAssertFalse(FixedTriggerPolicy.acceptsModifierTransition(
            keyCode: CGKeyCode(kVK_RightOption)
        ))
        XCTAssertFalse(FixedTriggerPolicy.acceptsModifierTransition(
            keyCode: CGKeyCode(kVK_Command)
        ))
        XCTAssertFalse(FixedTriggerPolicy.acceptsModifierTransition(
            keyCode: CGKeyCode(kVK_Shift)
        ))
    }

    func testOnboardingConfirmsOnlyTheLeftOptionPressTransition() {
        XCTAssertTrue(FixedTriggerPolicy.acceptsOnboardingConfirmation(
            keyCode: CGKeyCode(kVK_Option),
            isPressed: true
        ))
        XCTAssertFalse(FixedTriggerPolicy.acceptsOnboardingConfirmation(
            keyCode: CGKeyCode(kVK_Option),
            isPressed: false
        ))
        XCTAssertFalse(FixedTriggerPolicy.acceptsOnboardingConfirmation(
            keyCode: CGKeyCode(kVK_RightOption),
            isPressed: true
        ))
    }
}
