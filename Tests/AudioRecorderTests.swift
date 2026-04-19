import AVFoundation
import XCTest

@testable import Whisp

@MainActor
final class AudioRecorderTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "autoBoostMicrophoneVolume")
        super.tearDown()
    }

    // startRecording() consumes dateProvider() 3 times:
    //   1. debounce check (now)
    //   2. filename timestamp
    //   3. currentSessionStart
    // stopRecording() consumes it 1 time:
    //   4. duration calculation (now)

    func testStartRecordingSetsStateWhenPermissionGranted() async {
        let debounceDate = Date(timeIntervalSince1970: 1_000)
        let timestampDate = Date(timeIntervalSince1970: 1_003)
        let sessionDate = Date(timeIntervalSince1970: 1_005)
        let recorder = makeRecorder(
            dates: [debounceDate, timestampDate, sessionDate],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()

        XCTAssertTrue(didStart)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentSessionStart, sessionDate)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testStartRecordingReturnsFalseWithoutPermission() async {
        var factoryCalled = false
        let recorder = makeRecorder(
            dates: [Date(), Date(), Date()],
            authorizationStatusProvider: { .denied },
            recorderFactory: { _, _ in
                factoryCalled = true
                return MockAVAudioRecorder()
            }
        )
        recorder.hasPermission = false

        let didStart = await recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertFalse(factoryCalled, "Recorder factory should not be used without permission")
        XCTAssertFalse(recorder.isRecording)
    }

    func testInitDoesNotRequestPermissionPromptWhenStatusUndetermined() {
        var requestCount = 0

        let recorder = makeRecorder(
            dates: [],
            authorizationStatusProvider: { .notDetermined },
            permissionRequester: { completion in
                requestCount += 1
                completion(false)
            },
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        XCTAssertFalse(recorder.hasPermission)
        XCTAssertEqual(requestCount, 0)
    }

    func testStartRecordingRequestsPermissionOnFirstUseAndStartsWhenGranted() async {
        let debounceDate = Date(timeIntervalSince1970: 5_000)
        let timestampDate = Date(timeIntervalSince1970: 5_003)
        let sessionDate = Date(timeIntervalSince1970: 5_005)
        var requestCount = 0
        var status: AVAuthorizationStatus = .notDetermined

        let recorder = makeRecorder(
            dates: [debounceDate, timestampDate, sessionDate],
            authorizationStatusProvider: { status },
            permissionRequester: { completion in
                requestCount += 1
                status = .authorized
                completion(true)
            },
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        let didStart = await recorder.startRecording()

        XCTAssertTrue(didStart)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(recorder.hasPermission)
        XCTAssertTrue(recorder.isRecording)
    }

    func testStartRecordingReturnsFalseWhenPermissionRequestIsDenied() async {
        var requestCount = 0
        let recorder = makeRecorder(
            dates: [Date()],
            authorizationStatusProvider: { .notDetermined },
            permissionRequester: { completion in
                requestCount += 1
                completion(false)
            },
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        let didStart = await recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(recorder.hasPermission)
        XCTAssertFalse(recorder.isRecording)
    }

    func testStartRecordingPreventsReentrancy() async {
        let recorder = makeRecorder(
            dates: [
                // First startRecording: debounce, timestamp, sessionStart
                Date(timeIntervalSince1970: 2_000),
                Date(timeIntervalSince1970: 2_001),
                Date(timeIntervalSince1970: 2_002),
                // Second startRecording: debounce (then reentrancy guard fires)
                Date(timeIntervalSince1970: 2_010),
            ],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true

        let firstStart = await recorder.startRecording()
        XCTAssertTrue(firstStart, "First start should succeed")
        XCTAssertTrue(recorder.isRecording)

        let secondStart = await recorder.startRecording()

        XCTAssertFalse(secondStart, "Second start should fail due to reentrancy guard")
        XCTAssertTrue(recorder.isRecording, "Should still be recording after failed reentrancy")
    }

    func testStopRecordingSetsDurationAndResetsState() async {
        let sessionStart = Date(timeIntervalSince1970: 3_005)
        let stopDate = Date(timeIntervalSince1970: 3_010)
        let recorder = makeRecorder(
            dates: [
                // startRecording: debounce, timestamp, sessionStart
                Date(timeIntervalSince1970: 3_000),
                Date(timeIntervalSince1970: 3_002),
                sessionStart,
                // stopRecording: now
                stopDate,
            ],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true
        let started = await recorder.startRecording()
        XCTAssertTrue(started)

        let url = await recorder.stopRecording()

        XCTAssertNotNil(url)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertEqual(
            recorder.lastRecordingDuration ?? -1,
            stopDate.timeIntervalSince(sessionStart),
            accuracy: 0.001
        )
    }

    func testStopRecordingWaitsForFinishCallbackBeforeReturning() async {
        let delayedRecorder = DelayedFinishMockAVAudioRecorder()
        let recorder = makeRecorder(
            dates: [
                Date(timeIntervalSince1970: 7_000),
                Date(timeIntervalSince1970: 7_001),
                Date(timeIntervalSince1970: 7_002),
                Date(timeIntervalSince1970: 7_005),
            ],
            recorderFactory: { _, _ in delayedRecorder }
        )
        recorder.hasPermission = true
        let didStart = await recorder.startRecording()
        XCTAssertTrue(didStart)

        let url = await recorder.stopRecording()

        XCTAssertNotNil(url)
        XCTAssertTrue(delayedRecorder.didDeliverFinishCallback)
    }

    func testStopRecordingReturnsNilWhenFinishCallbackReportsFailure() async {
        let failedRecorder = FailedFinishMockAVAudioRecorder()
        let recorder = makeRecorder(
            dates: [
                Date(timeIntervalSince1970: 7_100),
                Date(timeIntervalSince1970: 7_101),
                Date(timeIntervalSince1970: 7_102),
                Date(timeIntervalSince1970: 7_105),
            ],
            recorderFactory: { _, _ in failedRecorder }
        )
        recorder.hasPermission = true
        let didStart = await recorder.startRecording()
        XCTAssertTrue(didStart)

        let url = await recorder.stopRecording()

        XCTAssertNil(url)
        XCTAssertTrue(failedRecorder.didDeliverFailureCallback)
    }

    func testStopRecordingWhenNotRecordingReturnsNil() async {
        let recorder = makeRecorder(
            dates: [],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )

        let url = await recorder.stopRecording()

        XCTAssertNil(url)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testCancelRecordingResetsState() async {
        let recorder = makeRecorder(
            dates: [
                // startRecording: debounce, timestamp, sessionStart
                Date(timeIntervalSince1970: 4_000),
                Date(timeIntervalSince1970: 4_001),
                Date(timeIntervalSince1970: 4_002),
            ],
            recorderFactory: { _, _ in MockAVAudioRecorder() }
        )
        recorder.hasPermission = true
        let started = await recorder.startRecording()
        XCTAssertTrue(started)

        recorder.cancelRecording()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testCancelRecordingCleansUpAfterFinishCallback() async {
        let debounceDate = Date(timeIntervalSince1970: 4_100)
        let timestampDate = Date(timeIntervalSince1970: 4_101)
        let sessionDate = Date(timeIntervalSince1970: 4_102)
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(timestampDate.timeIntervalSince1970).m4a")
        let delayedRecorder = DelayedFinishMockAVAudioRecorder()

        defer {
            try? FileManager.default.removeItem(at: expectedURL)
        }

        let recorder = makeRecorder(
            dates: [debounceDate, timestampDate, sessionDate],
            recorderFactory: { url, _ in
                XCTAssertEqual(url, expectedURL)
                XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x00])))
                return delayedRecorder
            }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()
        XCTAssertTrue(didStart)

        recorder.cancelRecording()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))

        try? await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertTrue(delayedRecorder.didDeliverFinishCallback)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path))
    }

    func testStartRecordingReturnsFalseWhenRecorderFactoryThrows() async {
        enum TestError: Error { case failed }

        let recorder = makeRecorder(
            dates: [Date(), Date(), Date()],
            recorderFactory: { _, _ in throw TestError.failed }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)

        let stoppedURL = await recorder.stopRecording()
        XCTAssertNil(stoppedURL)
    }

    func testStartRecordingReturnsFalseWhenRecordCallFails() async {
        let recorder = makeRecorder(
            dates: [Date(), Date(), Date()],
            recorderFactory: { _, _ in
                let mock = MockAVAudioRecorder()
                mock.setShouldFailToRecord(true)
                return mock
            }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
    }

    func testConcurrentStopRecordingCallsShareTheSameStopWork() async {
        let delayedRecorder = DelayedFinishMockAVAudioRecorder()
        let recorder = makeRecorder(
            dates: [
                Date(timeIntervalSince1970: 8_000),
                Date(timeIntervalSince1970: 8_001),
                Date(timeIntervalSince1970: 8_002),
                Date(timeIntervalSince1970: 8_005),
            ],
            recorderFactory: { _, _ in delayedRecorder }
        )
        recorder.hasPermission = true
        let didStart = await recorder.startRecording()
        XCTAssertTrue(didStart)

        async let firstURL = recorder.stopRecording()
        async let secondURL = recorder.stopRecording()
        let resolvedFirstURL = await firstURL
        let resolvedSecondURL = await secondURL

        XCTAssertEqual(resolvedFirstURL, resolvedSecondURL)
        XCTAssertTrue(delayedRecorder.didDeliverFinishCallback)
    }

    func testStopRecordingDoesNotDropSlowFinalization() async {
        let delayedRecorder = DelayedFinishMockAVAudioRecorder()
        delayedRecorder.delayNanoseconds = 50_000_000

        let recorder = makeRecorder(
            dates: [
                Date(timeIntervalSince1970: 9_000),
                Date(timeIntervalSince1970: 9_001),
                Date(timeIntervalSince1970: 9_002),
                Date(timeIntervalSince1970: 9_005),
            ],
            recorderFactory: { _, _ in
                delayedRecorder
            }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()
        XCTAssertTrue(didStart)
        let stoppedURL = await recorder.stopRecording()
        XCTAssertNotNil(stoppedURL)
        XCTAssertTrue(delayedRecorder.didDeliverFinishCallback)
    }

    func testCancelDuringStopResolvesPendingStopTask() async {
        let debounceDate = Date(timeIntervalSince1970: 9_200)
        let timestampDate = Date(timeIntervalSince1970: 9_201)
        let sessionDate = Date(timeIntervalSince1970: 9_202)
        let stopDate = Date(timeIntervalSince1970: 9_205)
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(timestampDate.timeIntervalSince1970).m4a")
        let delayedRecorder = DelayedFinishMockAVAudioRecorder()

        defer {
            try? FileManager.default.removeItem(at: expectedURL)
        }

        let recorder = makeRecorder(
            dates: [debounceDate, timestampDate, sessionDate, stopDate],
            recorderFactory: { url, _ in
                XCTAssertEqual(url, expectedURL)
                XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x00])))
                return delayedRecorder
            }
        )
        recorder.hasPermission = true

        let didStart = await recorder.startRecording()
        XCTAssertTrue(didStart)

        async let stoppedURL = recorder.stopRecording()
        try? await Task.sleep(nanoseconds: 50_000_000)
        recorder.cancelRecording()

        let resolvedStoppedURL = await stoppedURL

        XCTAssertNil(resolvedStoppedURL)
        XCTAssertTrue(delayedRecorder.didDeliverFinishCallback)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path))

        let subsequentStopURL = await recorder.stopRecording()
        XCTAssertNil(subsequentStopURL)
    }

    // MARK: - Helpers

    private func makeRecorder(
        dates: [Date],
        authorizationStatusProvider: @escaping () -> AVAuthorizationStatus = { .authorized },
        permissionRequester: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
            completion(true)
        },
        recorderFactory: @escaping (URL, [String: Any]) throws -> AVAudioRecorder
    ) -> AudioRecorder {
        let dateProvider = StubDateProvider(dates: dates)
        return AudioRecorder(
            recorderFactory: recorderFactory,
            dateProvider: { dateProvider.nextDate() },
            authorizationStatusProvider: authorizationStatusProvider,
            permissionRequester: permissionRequester
        )
    }
}

private final class StubDateProvider {
    private var dates: [Date]

    init(dates: [Date]) {
        self.dates = dates
    }

    func nextDate() -> Date {
        guard !dates.isEmpty else {
            return Date()
        }
        return dates.removeFirst()
    }
}

private final class DelayedFinishMockAVAudioRecorder: MockAVAudioRecorder, @unchecked Sendable {
    var delayNanoseconds: UInt64 = 400_000_000
    private(set) var didDeliverFinishCallback = false

    override func stop() {
        setMockRecordingState(false)

        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            didDeliverFinishCallback = true
            delegate?.audioRecorderDidFinishRecording?(self, successfully: true)
        }
    }
}

private final class FailedFinishMockAVAudioRecorder: MockAVAudioRecorder, @unchecked Sendable {
    private(set) var didDeliverFailureCallback = false

    override func stop() {
        setMockRecordingState(false)
        didDeliverFailureCallback = true
        delegate?.audioRecorderDidFinishRecording?(self, successfully: false)
    }
}
