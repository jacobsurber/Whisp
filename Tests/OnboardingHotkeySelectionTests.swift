import XCTest
@testable import Whisp

final class OnboardingHotkeySelectionTests: XCTestCase {
    func testGlobeSelectionRequiresConfirmationWhenWarningNotAcknowledged() {
        let decision = OnboardingPressAndHoldKeySelectionResolver.resolveChange(
            from: PressAndHoldKey.rightOption.rawValue,
            to: PressAndHoldKey.globe.rawValue,
            warningAcknowledged: false
        )

        XCTAssertEqual(
            decision,
            .requireConfirmation(
                previousSelection: .rightOption,
                pendingSelection: .globe
            )
        )
    }

    func testGlobeSelectionPersistsImmediatelyWhenWarningAlreadyAcknowledged() {
        let decision = OnboardingPressAndHoldKeySelectionResolver.resolveChange(
            from: PressAndHoldKey.rightOption.rawValue,
            to: PressAndHoldKey.globe.rawValue,
            warningAcknowledged: true
        )

        XCTAssertEqual(decision, .persist(.globe))
    }

    func testNonGlobeSelectionPersistsImmediately() {
        let decision = OnboardingPressAndHoldKeySelectionResolver.resolveChange(
            from: PressAndHoldKey.rightOption.rawValue,
            to: PressAndHoldKey.rightCommand.rawValue,
            warningAcknowledged: false
        )

        XCTAssertEqual(decision, .persist(.rightCommand))
    }

    func testCoordinatorStagesGlobeSelectionUntilConfirmed() {
        var state = makeState()

        let keyIdentifierToPublish = OnboardingPressAndHoldSelectionCoordinator.handlePickerChange(
            state: &state,
            from: PressAndHoldKey.rightOption.rawValue,
            to: PressAndHoldKey.globe.rawValue,
            warningAcknowledged: false
        )

        XCTAssertNil(keyIdentifierToPublish)
        XCTAssertEqual(state.persistedKeyIdentifier, PressAndHoldKey.rightOption.rawValue)
        XCTAssertEqual(state.pickerSelection, PressAndHoldKey.rightOption.rawValue)
        XCTAssertEqual(state.pendingKeyIdentifier, PressAndHoldKey.globe.rawValue)
        XCTAssertTrue(state.showFnWarningConfirmation)
    }

    func testCoordinatorPersistsNonGlobeSelectionAndRequestsPublish() {
        var state = makeState()

        let keyIdentifierToPublish = OnboardingPressAndHoldSelectionCoordinator.handlePickerChange(
            state: &state,
            from: PressAndHoldKey.rightOption.rawValue,
            to: PressAndHoldKey.rightCommand.rawValue,
            warningAcknowledged: false
        )

        XCTAssertEqual(keyIdentifierToPublish, PressAndHoldKey.rightCommand.rawValue)
        XCTAssertEqual(state.persistedKeyIdentifier, PressAndHoldKey.rightCommand.rawValue)
        XCTAssertEqual(state.pickerSelection, PressAndHoldKey.rightCommand.rawValue)
        XCTAssertEqual(state.previousKeyIdentifier, PressAndHoldKey.rightCommand.rawValue)
        XCTAssertNil(state.pendingKeyIdentifier)
        XCTAssertFalse(state.showFnWarningConfirmation)
    }

    func testCoordinatorConfirmPromotesPendingSelectionAndRequestsPublish() {
        var state = makeState(
            persistedKeyIdentifier: PressAndHoldKey.rightOption.rawValue,
            pickerSelection: PressAndHoldKey.rightOption.rawValue,
            previousKeyIdentifier: PressAndHoldKey.rightOption.rawValue,
            pendingKeyIdentifier: PressAndHoldKey.globe.rawValue,
            showFnWarningConfirmation: true
        )

        let keyIdentifierToPublish = OnboardingPressAndHoldSelectionCoordinator.confirmPendingSelection(
            state: &state
        )

        XCTAssertEqual(keyIdentifierToPublish, PressAndHoldKey.globe.rawValue)
        XCTAssertEqual(state.persistedKeyIdentifier, PressAndHoldKey.globe.rawValue)
        XCTAssertEqual(state.pickerSelection, PressAndHoldKey.globe.rawValue)
        XCTAssertEqual(state.previousKeyIdentifier, PressAndHoldKey.globe.rawValue)
        XCTAssertNil(state.pendingKeyIdentifier)
        XCTAssertFalse(state.showFnWarningConfirmation)
    }

    func testCoordinatorCancelRestoresPreviousSelection() {
        var state = makeState(
            persistedKeyIdentifier: PressAndHoldKey.rightOption.rawValue,
            pickerSelection: PressAndHoldKey.rightOption.rawValue,
            previousKeyIdentifier: PressAndHoldKey.rightOption.rawValue,
            pendingKeyIdentifier: PressAndHoldKey.globe.rawValue,
            showFnWarningConfirmation: true
        )

        OnboardingPressAndHoldSelectionCoordinator.cancelPendingSelection(state: &state)

        XCTAssertEqual(state.persistedKeyIdentifier, PressAndHoldKey.rightOption.rawValue)
        XCTAssertEqual(state.pickerSelection, PressAndHoldKey.rightOption.rawValue)
        XCTAssertNil(state.pendingKeyIdentifier)
        XCTAssertFalse(state.showFnWarningConfirmation)
    }

    private func makeState(
        persistedKeyIdentifier: String = PressAndHoldKey.rightOption.rawValue,
        pickerSelection: String = PressAndHoldKey.rightOption.rawValue,
        previousKeyIdentifier: String = PressAndHoldKey.rightOption.rawValue,
        pendingKeyIdentifier: String? = nil,
        showFnWarningConfirmation: Bool = false
    ) -> OnboardingPressAndHoldSelectionState {
        OnboardingPressAndHoldSelectionState(
            persistedKeyIdentifier: persistedKeyIdentifier,
            pickerSelection: pickerSelection,
            previousKeyIdentifier: previousKeyIdentifier,
            pendingKeyIdentifier: pendingKeyIdentifier,
            showFnWarningConfirmation: showFnWarningConfirmation
        )
    }
}