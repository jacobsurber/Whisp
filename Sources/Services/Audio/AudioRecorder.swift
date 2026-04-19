import AVFoundation
import Combine
import Foundation
import os.log

@MainActor
internal class AudioRecorder: NSObject, ObservableObject {
    private enum StopRecordingResult {
        case finishedSuccessfully
        case finishedWithFailure
    }

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var levelUpdateTimer: Timer?
    private let volumeManager: MicrophoneVolumeManager
    private let recorderFactory: (URL, [String: Any]) throws -> AVAudioRecorder
    private let dateProvider: () -> Date
    private let authorizationStatusProvider: () -> AVAuthorizationStatus
    private let permissionRequester: (@escaping @Sendable (Bool) -> Void) -> Void
    private var stopRecordingContinuation: CheckedContinuation<StopRecordingResult, Never>?
    private var stopRecordingTask: Task<URL?, Never>?
    private var stoppingRecorderIdentifier: ObjectIdentifier?
    private var cancelledRecorderIdentifier: ObjectIdentifier?
    private(set) var currentSessionStart: Date?
    private(set) var lastRecordingDuration: TimeInterval?

    // Debouncing to prevent rapid recording starts
    private var lastRecordingAttempt: Date?
    private let debounceInterval: TimeInterval = 0.2  // 200ms debounce window

    override init() {
        self.volumeManager = MicrophoneVolumeManager.shared
        self.recorderFactory = { url, settings in try AVAudioRecorder(url: url, settings: settings) }
        self.dateProvider = { Date() }
        self.authorizationStatusProvider = { AVCaptureDevice.authorizationStatus(for: .audio) }
        self.permissionRequester = { completion in
            guard !AppEnvironment.isRunningTests else {
                completion(false)
                return
            }

            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
        super.init()
        setupRecorder()
        checkMicrophonePermission()
    }

    init(
        volumeManager: MicrophoneVolumeManager = .shared,
        recorderFactory: @escaping (URL, [String: Any]) throws -> AVAudioRecorder,
        dateProvider: @escaping () -> Date = { Date() },
        authorizationStatusProvider: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        permissionRequester: @escaping (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
            guard !AppEnvironment.isRunningTests else {
                completion(false)
                return
            }

            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
    ) {
        self.volumeManager = volumeManager
        self.recorderFactory = recorderFactory
        self.dateProvider = dateProvider
        self.authorizationStatusProvider = authorizationStatusProvider
        self.permissionRequester = permissionRequester
        super.init()
        setupRecorder()
        checkMicrophonePermission()
    }

    private func setupRecorder() {
        // AVAudioSession is not needed on macOS
    }

    func checkMicrophonePermission() {
        let permissionStatus = authorizationStatusProvider()

        switch permissionStatus {
        case .authorized:
            self.hasPermission = true
        case .denied, .restricted, .notDetermined:
            self.hasPermission = false
        @unknown default:
            self.hasPermission = false
        }
    }

    func requestMicrophonePermission() {
        permissionRequester { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasPermission = granted
            }
        }
    }

    func startRecording() async -> Bool {
        // Debounce rapid recording attempts
        let now = dateProvider()
        if let last = lastRecordingAttempt, now.timeIntervalSince(last) < debounceInterval {
            Logger.audioRecorder.debug("Recording attempt debounced (too soon after last attempt)")
            return false
        }
        lastRecordingAttempt = now

        // Check permission on demand instead of prompting during app launch.
        guard await ensureMicrophonePermission() else {
            return false
        }

        // Prevent re-entrancy - if already recording, return false
        guard audioRecorder == nil else {
            return false
        }

        // Boost microphone volume if enabled (await to ensure it completes before recording)
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            _ = await volumeManager.boostMicrophoneVolume()
        }

        let tempPath = FileManager.default.temporaryDirectory
        let timestamp = dateProvider().timeIntervalSince1970
        let audioFilename = tempPath.appendingPathComponent("recording_\(timestamp).m4a")

        recordingURL = audioFilename

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        // Note: On macOS, microphone selection is handled at the system level
        // The AVAudioRecorder will use the system's default input device
        // Users can change this in System Preferences > Sound > Input

        do {
            audioRecorder = try recorderFactory(audioFilename, settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            guard audioRecorder?.record() == true else {
                Logger.audioRecorder.error("AVAudioRecorder failed to start recording")
                audioRecorder = nil
                recordingURL = nil

                if UserDefaults.standard.autoBoostMicrophoneVolume {
                    _ = await volumeManager.restoreMicrophoneVolume()
                }

                checkMicrophonePermission()
                return false
            }

            currentSessionStart = dateProvider()
            lastRecordingDuration = nil

            self.isRecording = true
            self.startLevelMonitoring()
            return true
        } catch {
            Logger.audioRecorder.error("Failed to start recording: \(error.localizedDescription)")
            audioRecorder = nil
            recordingURL = nil
            // Restore volume if recording failed and we boosted it
            if UserDefaults.standard.autoBoostMicrophoneVolume {
                _ = await volumeManager.restoreMicrophoneVolume()
            }
            // Recheck permissions if recording failed
            checkMicrophonePermission()
            return false
        }
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch authorizationStatusProvider() {
        case .authorized:
            hasPermission = true
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                permissionRequester { granted in
                    continuation.resume(returning: granted)
                }
            }
            hasPermission = granted
            return granted
        case .denied, .restricted:
            hasPermission = false
            return false
        @unknown default:
            hasPermission = false
            return false
        }
    }

    func stopRecording() async -> URL? {
        if let stopRecordingTask {
            return await stopRecordingTask.value
        }

        guard let recorder = audioRecorder else {
            return recordingURL
        }

        let stopTask = Task { @MainActor [weak self] () -> URL? in
            guard let self else { return nil }

            defer {
                stopRecordingTask = nil
            }

            let now = dateProvider()
            let sessionDuration = currentSessionStart.map { now.timeIntervalSince($0) }
            lastRecordingDuration = sessionDuration
            currentSessionStart = nil
            let finalRecordingURL = recordingURL

            let stopResult = await waitForRecordingToFinish(recorder)
            if stopResult == .finishedWithFailure {
                Logger.audioRecorder.error("Recording failed during finalization")
            }

            audioRecorder = nil

            if UserDefaults.standard.autoBoostMicrophoneVolume {
                _ = await volumeManager.restoreMicrophoneVolume()
            }

            isRecording = false
            stopLevelMonitoring()

            if stopResult == .finishedWithFailure {
                if let finalRecordingURL {
                    try? FileManager.default.removeItem(at: finalRecordingURL)
                }
                recordingURL = nil
                return nil
            }

            return finalRecordingURL
        }

        stopRecordingTask = stopTask
        return await stopTask.value
    }

    private func waitForRecordingToFinish(_ recorder: AVAudioRecorder) async -> StopRecordingResult {
        if !recorder.isRecording {
            return .finishedSuccessfully
        }

        let recorderIdentifier = ObjectIdentifier(recorder)

        return await withCheckedContinuation { continuation in
            stoppingRecorderIdentifier = recorderIdentifier
            stopRecordingContinuation = continuation
            recorder.stop()
        }
    }

    private func resolveStopRecordingContinuation(
        result: StopRecordingResult,
        expectedRecorderIdentifier: ObjectIdentifier
    ) {
        guard stoppingRecorderIdentifier == expectedRecorderIdentifier else { return }
        guard let continuation = stopRecordingContinuation else { return }

        stoppingRecorderIdentifier = nil
        stopRecordingContinuation = nil
        continuation.resume(returning: result)
    }

    func cleanupRecording() {
        guard let url = recordingURL else { return }

        // Restore microphone volume if it was boosted (in case of cancellation/cleanup)
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }

        currentSessionStart = nil
        lastRecordingDuration = nil

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.audioRecorder.error("Failed to cleanup recording file: \(error.localizedDescription)")
        }

        recordingURL = nil
    }

    func cancelRecording() {
        let recorderToCancel = audioRecorder
        if let recorderToCancel {
            cancelledRecorderIdentifier = ObjectIdentifier(recorderToCancel)
            recorderToCancel.stop()
        }

        audioRecorder = nil
        currentSessionStart = nil
        lastRecordingDuration = nil

        // Restore microphone volume if it was boosted
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }

        // Update @Published properties on main thread
        self.isRecording = false
        self.stopLevelMonitoring()

        if recorderToCancel == nil {
            cleanupRecording()
        }
    }

    private func startLevelMonitoring() {
        // Use a more efficient approach for macOS
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let recorder = self.audioRecorder else { return }

                recorder.updateMeters()
                let normalizedLevel = self.normalizeLevel(recorder.averagePower(forChannel: 0))

                self.audioLevel = normalizedLevel
            }
        }
    }

    private func stopLevelMonitoring() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        audioLevel = 0.0
    }

    private func normalizeLevel(_ level: Float) -> Float {
        // Convert dB to linear scale (0.0 to 1.0)
        let minDb: Float = -60.0
        let maxDb: Float = 0.0

        let clampedLevel = max(minDb, min(maxDb, level))
        return (clampedLevel - minDb) / (maxDb - minDb)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Logger.audioRecorder.error("Recording finished unsuccessfully")
        }

        Task { @MainActor [weak self] in
            let recorderIdentifier = ObjectIdentifier(recorder)

            if self?.cancelledRecorderIdentifier == recorderIdentifier {
                self?.cancelledRecorderIdentifier = nil
                self?.cleanupRecording()
                self?.resolveStopRecordingContinuation(
                    result: .finishedWithFailure,
                    expectedRecorderIdentifier: recorderIdentifier
                )
                return
            }

            self?.resolveStopRecordingContinuation(
                result: flag ? .finishedSuccessfully : .finishedWithFailure,
                expectedRecorderIdentifier: recorderIdentifier
            )
        }
    }
}
