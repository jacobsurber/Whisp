import XCTest

@testable import Whisp

@MainActor
final class FloatingMicrophoneDockViewModelTests: XCTestCase {
    func testReadyStateStartsCollapsedAndExpandsOnHover() {
        let viewModel = FloatingMicrophoneDockViewModel(successResetDelay: .milliseconds(10))

        XCTAssertEqual(viewModel.visualStyle, .collapsedIdle)

        viewModel.setHovering(true)

        XCTAssertEqual(viewModel.visualStyle, .expandedIdle)
    }

    func testHoldShortcutUsesBarsOnlyPresentation() {
        let viewModel = FloatingMicrophoneDockViewModel(successResetDelay: .milliseconds(10))

        viewModel.prepareForShortcutActivation(mode: .hold)

        XCTAssertEqual(viewModel.visualStyle, .shortcutListening)

        viewModel.applyRecorderState(isRecording: true, audioLevel: 0.5, hasPermission: true)

        XCTAssertEqual(viewModel.visualStyle, .shortcutListening)
    }

    func testToggleShortcutUsesInteractiveRecordingControls() {
        let viewModel = FloatingMicrophoneDockViewModel(successResetDelay: .milliseconds(10))

        viewModel.prepareForShortcutActivation(mode: .toggle)

        XCTAssertEqual(viewModel.visualStyle, .recordingControls)

        viewModel.applyRecorderState(isRecording: true, audioLevel: 0.5, hasPermission: true)

        XCTAssertEqual(viewModel.visualStyle, .recordingControls)
    }

    func testPermissionRequiredWhenRecorderCannotAccessMicrophone() {
        let viewModel = FloatingMicrophoneDockViewModel(successResetDelay: .milliseconds(10))

        viewModel.applyRecorderState(isRecording: false, audioLevel: 0, hasPermission: false)

        XCTAssertEqual(viewModel.status, .permissionRequired)
    }

    func testProcessingStatePersistsAfterRecorderStopsUntilCompletionNotification() {
        let viewModel = FloatingMicrophoneDockViewModel(successResetDelay: .milliseconds(10))

        viewModel.applyRecorderState(isRecording: true, audioLevel: 0.6, hasPermission: true)
        viewModel.handleTranscriptionStarted()
        viewModel.applyRecorderState(isRecording: false, audioLevel: 0, hasPermission: true)

        XCTAssertEqual(viewModel.status, .processing("Transcribing..."))
    }

    func testCompletionShowsSuccessThenReturnsToReady() async {
        let viewModel = FloatingMicrophoneDockViewModel(successResetDelay: .milliseconds(10))

        viewModel.applyRecorderState(isRecording: false, audioLevel: 0, hasPermission: true)
        viewModel.handleTranscriptionStarted()
        viewModel.handleTranscriptionCompleted()

        XCTAssertEqual(viewModel.status, .success)

        // Wait generously — CI runners have high Task scheduling latency
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(viewModel.status, .ready)
    }
}
