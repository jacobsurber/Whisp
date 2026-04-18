import Foundation
import WhisperKit
import XCTest

@testable import Whisp

private actor DownloadPauseController {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor LoadConfigCapture {
    private var model: String?
    private var modelFolder: String?
    private var downloadEnabled: Bool?

    func record(_ config: WhisperKitConfig) {
        model = config.model
        modelFolder = config.modelFolder
        downloadEnabled = config.download
    }

    func snapshot() -> (model: String?, modelFolder: String?, downloadEnabled: Bool?) {
        (model, modelFolder, downloadEnabled)
    }
}

private actor ProgressCallbackCapture {
    private var callback: ((Progress) -> Void)?

    func store(_ callback: @escaping (Progress) -> Void) {
        self.callback = callback
    }

    func send(fractionCompleted: Double) {
        guard let callback else { return }

        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = Int64(fractionCompleted * 100)
        callback(progress)
    }
}

@MainActor
private final class ModelManagerProbe {
    private weak var manager: ModelManager?

    func attach(_ manager: ModelManager) {
        self.manager = manager
    }

    func snapshot(for model: WhisperModel) -> (stage: DownloadStage?, progress: Double?) {
        guard let manager else {
            return (nil, nil)
        }

        return (manager.getDownloadStage(for: model), manager.downloadProgress[model])
    }
}

final class ModelManagerDownloadProgressTests: XCTestCase {
    private let requiredCoreMLBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    override func setUp() {
        super.setUp()
        unsetenv("WHISP_WHISPERKIT_DOWNLOAD_BASE")
    }

    override func tearDown() {
        unsetenv("WHISP_WHISPERKIT_DOWNLOAD_BASE")
        super.tearDown()
    }

    func testDownloadModelPublishesProgressAndLoadsDownloadedFolder() async throws {
        let model = WhisperModel.base
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadBase = root.appendingPathComponent("huggingface", isDirectory: true)
        let requiredCoreMLBundles = self.requiredCoreMLBundles
        let pauseController = DownloadPauseController()
        let loadConfigCapture = LoadConfigCapture()
        let progressExpectation = XCTestExpectation(description: "Download progress callback reached")

        let installCompleteModel = { (modelDirectory: URL) throws in
            for bundle in requiredCoreMLBundles {
                let bundleDirectory = modelDirectory.appendingPathComponent(bundle, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: bundleDirectory,
                    withIntermediateDirectories: true
                )
                FileManager.default.createFile(
                    atPath: bundleDirectory.appendingPathComponent("coremldata.bin").path,
                    contents: Data([0x1])
                )
            }
        }

        setenv("WHISP_WHISPERKIT_DOWNLOAD_BASE", downloadBase.path, 1)
        defer {
            unsetenv("WHISP_WHISPERKIT_DOWNLOAD_BASE")
            try? FileManager.default.removeItem(at: root)
        }

        let manager = await MainActor.run {
            ModelManager(
                downloadVariantOperation: { variant, resolvedDownloadBase, progressCallback in
                    let progress = Progress(totalUnitCount: 100)
                    progress.completedUnitCount = 35
                    progressCallback(progress)
                    progressExpectation.fulfill()

                    await pauseController.wait()

                    let baseDirectory = resolvedDownloadBase ?? downloadBase
                    let modelDirectory =
                        baseDirectory
                        .appendingPathComponent(
                            "models/argmaxinc/whisperkit-coreml/\(variant)",
                            isDirectory: true
                        )

                    try FileManager.default.createDirectory(
                        at: modelDirectory,
                        withIntermediateDirectories: true
                    )
                    try installCompleteModel(modelDirectory)
                    return modelDirectory
                },
                loadModelOperation: { config in
                    await loadConfigCapture.record(config)
                }
            )
        }

        let downloadTask = Task {
            try await manager.downloadModel(model)
        }

        await fulfillment(of: [progressExpectation], timeout: 1.0)

        let didPublishProgress = await waitUntil {
            await MainActor.run {
                manager.downloadProgress[model] == 0.35
                    && manager.getDownloadStage(for: model) == .downloading
            }
        }

        XCTAssertTrue(didPublishProgress)

        let reportedProgress = await MainActor.run { manager.downloadProgress[model] ?? -1 }
        let reportedStage: DownloadStage? = await MainActor.run {
            manager.getDownloadStage(for: model)
        }

        XCTAssertEqual(reportedProgress, 0.35, accuracy: 0.001)
        XCTAssertEqual(reportedStage, DownloadStage.downloading)

        await pauseController.resume()
        try await downloadTask.value

        let expectedFolder =
            downloadBase
            .appendingPathComponent(
                "models/argmaxinc/whisperkit-coreml/\(model.whisperKitModelName)",
                isDirectory: true
            )
        let capturedConfig = await loadConfigCapture.snapshot()

        XCTAssertEqual(capturedConfig.model, model.whisperKitModelName)
        XCTAssertEqual(capturedConfig.modelFolder, expectedFolder.path)
        XCTAssertEqual(capturedConfig.downloadEnabled, false)
        let finalStage: DownloadStage? = await MainActor.run { manager.getDownloadStage(for: model) }
        let finalProgress = await MainActor.run { manager.downloadProgress[model] }
        XCTAssertEqual(finalStage, DownloadStage.ready)
        XCTAssertNil(finalProgress)
        XCTAssertTrue(WhisperKitStorage.isModelDownloaded(model))
    }

    func testLateProgressCallbackDoesNotOverwriteProcessingStage() async throws {
        let model = WhisperModel.base
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadBase = root.appendingPathComponent("huggingface", isDirectory: true)
        let requiredCoreMLBundles = self.requiredCoreMLBundles
        let loadConfigCapture = LoadConfigCapture()
        let progressCallbackCapture = ProgressCallbackCapture()
        let probe = await MainActor.run { ModelManagerProbe() }
        let processingExpectation = XCTestExpectation(description: "Late callback does not rewind processing")

        let installCompleteModel = { (modelDirectory: URL) throws in
            for bundle in requiredCoreMLBundles {
                let bundleDirectory = modelDirectory.appendingPathComponent(bundle, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: bundleDirectory,
                    withIntermediateDirectories: true
                )
                FileManager.default.createFile(
                    atPath: bundleDirectory.appendingPathComponent("coremldata.bin").path,
                    contents: Data([0x1])
                )
            }
        }

        setenv("WHISP_WHISPERKIT_DOWNLOAD_BASE", downloadBase.path, 1)
        defer {
            unsetenv("WHISP_WHISPERKIT_DOWNLOAD_BASE")
            try? FileManager.default.removeItem(at: root)
        }

        var manager: ModelManager!
        manager = await MainActor.run {
            ModelManager(
                downloadVariantOperation: { variant, resolvedDownloadBase, progressCallback in
                    await progressCallbackCapture.store(progressCallback)
                    await progressCallbackCapture.send(fractionCompleted: 0.25)

                    let baseDirectory = resolvedDownloadBase ?? downloadBase
                    let modelDirectory = baseDirectory
                        .appendingPathComponent(
                            "models/argmaxinc/whisperkit-coreml/\(variant)",
                            isDirectory: true
                        )

                    try FileManager.default.createDirectory(
                        at: modelDirectory,
                        withIntermediateDirectories: true
                    )
                    try installCompleteModel(modelDirectory)
                    return modelDirectory
                },
                loadModelOperation: { config in
                    await loadConfigCapture.record(config)
                    await progressCallbackCapture.send(fractionCompleted: 0.9)
                    await Task.yield()
                    await Task.yield()

                    let stateDuringLoad = probe.snapshot(for: model)

                    XCTAssertEqual(stateDuringLoad.stage, DownloadStage.processing)
                    XCTAssertEqual(stateDuringLoad.progress ?? -1, 1, accuracy: 0.001)
                    processingExpectation.fulfill()
                }
            )
        }

        let resolvedManager = manager!
        await MainActor.run {
            probe.attach(resolvedManager)
        }

        try await resolvedManager.downloadModel(model)
        await fulfillment(of: [processingExpectation], timeout: 1.0)

        let finalStage: DownloadStage? = await MainActor.run { resolvedManager.getDownloadStage(for: model) }
        XCTAssertEqual(finalStage, DownloadStage.ready)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }

            try? await Task.sleep(for: pollInterval)
        }

        return await condition()
    }
}
