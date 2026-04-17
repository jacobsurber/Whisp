import XCTest

@testable import Whisp

@MainActor
final class MLXModelManagerTests: XCTestCase {
    private let environmentKeys = [
        "HF_HUB_OFFLINE",
        "TRANSFORMERS_OFFLINE",
        "HF_HUB_DISABLE_IMPLICIT_TOKEN",
    ]
    private var originalEnvironmentValues: [String: String?] = [:]

    override func setUp() {
        super.setUp()

        originalEnvironmentValues = [:]
        for key in environmentKeys {
            originalEnvironmentValues[key] = HuggingFaceEnvironment.currentValue(for: key)
        }
    }

    override func tearDown() {
        for key in environmentKeys {
            let originalValue = originalEnvironmentValues[key] ?? nil
            if let originalValue {
                setenv(key, originalValue, 1)
            } else {
                unsetenv(key)
            }
        }

        originalEnvironmentValues = [:]
        super.tearDown()
    }

    func testRefreshModelListFindsModelsInsideHubCache() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = "mlx-community/Qwen3-1.7B-4bit"
        let modelDirectory = HuggingFaceCache.modelDirectory(for: repo, rootDirectory: cacheRoot)
        let snapshotDirectory = modelDirectory.appendingPathComponent("snapshots/rev123", isDirectory: true)

        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: snapshotDirectory.appendingPathComponent("model.safetensors").path,
            contents: Data(repeating: 0x1, count: 1024)
        )

        let manager = MLXModelManager(cacheDirectory: cacheRoot, refreshOnInit: false)
        await manager.refreshModelList()

        XCTAssertTrue(manager.downloadedModels.contains(repo))
        XCTAssertNotNil(manager.modelSizes[repo])
        XCTAssertGreaterThan(manager.totalCacheSize, 0)
    }

    func testHuggingFaceCacheUsesHubSubdirectory() {
        let cacheRoot = URL(fileURLWithPath: "/tmp/whisp-hf-cache", isDirectory: true)
        let modelDirectory = HuggingFaceCache.modelDirectory(
            for: "mlx-community/parakeet-tdt-0.6b-v3",
            rootDirectory: cacheRoot
        )

        XCTAssertEqual(
            modelDirectory.path,
            "/tmp/whisp-hf-cache/hub/models--mlx-community--parakeet-tdt-0.6b-v3"
        )
    }

    func testHuggingFaceCacheRequiresWeightsFile() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = "mlx-community/parakeet-tdt-0.6b-v3"
        let modelDirectory = HuggingFaceCache.modelDirectory(for: repo, rootDirectory: cacheRoot)
        let refsDirectory = modelDirectory.appendingPathComponent("refs", isDirectory: true)
        let snapshotDirectory = modelDirectory.appendingPathComponent("snapshots/rev123", isDirectory: true)

        try FileManager.default.createDirectory(at: refsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        try "rev123".write(
            to: refsDirectory.appendingPathComponent("main"), atomically: true, encoding: .utf8)

        XCTAssertFalse(HuggingFaceCache.hasUsableModelSnapshot(for: repo, rootDirectory: cacheRoot))
    }

    func testUnusedModelCountExcludesSelectedParakeetRepo() {
        let manager = MLXModelManager(refreshOnInit: false)
        let repo = ParakeetModel.v3Multilingual.rawValue
        let previousRepo = UserDefaults.standard.string(forKey: AppDefaults.Keys.selectedParakeetModel)

        UserDefaults.standard.set(repo, forKey: AppDefaults.Keys.selectedParakeetModel)
        manager.downloadedModels.insert(repo)

        XCTAssertEqual(manager.unusedModelCount, 0)

        if let previousRepo {
            UserDefaults.standard.set(previousRepo, forKey: AppDefaults.Keys.selectedParakeetModel)
        } else {
            UserDefaults.standard.removeObject(forKey: AppDefaults.Keys.selectedParakeetModel)
        }
    }

    func testDownloadProcessEnvironmentClearsOfflineFlags() {
        let cacheRoot = URL(fileURLWithPath: "/tmp/whisp-hf-cache", isDirectory: true)
        let environment = HuggingFaceEnvironment.downloadProcessEnvironment(
            base: [
                "PATH": "/usr/bin",
                "HF_HUB_OFFLINE": "1",
                "TRANSFORMERS_OFFLINE": "1",
            ],
            cacheDirectory: cacheRoot
        )

        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertNil(environment["HF_HUB_OFFLINE"])
        XCTAssertNil(environment["TRANSFORMERS_OFFLINE"])
        XCTAssertEqual(environment["HF_HOME"], cacheRoot.path)
        XCTAssertEqual(environment["HF_HUB_CACHE"], "\(cacheRoot.path)/hub")
    }

    func testOfflineModelLoadingEnvironmentRestoresPreviousValues() async throws {
        setenv("HF_HUB_OFFLINE", "0", 1)
        unsetenv("TRANSFORMERS_OFFLINE")
        unsetenv("HF_HUB_DISABLE_IMPLICIT_TOKEN")

        try await HuggingFaceEnvironment.withOfflineModelLoadingEnvironment {
            XCTAssertEqual(HuggingFaceEnvironment.currentValue(for: "HF_HUB_OFFLINE"), "1")
            XCTAssertEqual(HuggingFaceEnvironment.currentValue(for: "TRANSFORMERS_OFFLINE"), "1")
            XCTAssertEqual(HuggingFaceEnvironment.currentValue(for: "HF_HUB_DISABLE_IMPLICIT_TOKEN"), "1")
        }

        XCTAssertEqual(HuggingFaceEnvironment.currentValue(for: "HF_HUB_OFFLINE"), "0")
        XCTAssertNil(HuggingFaceEnvironment.currentValue(for: "TRANSFORMERS_OFFLINE"))
        XCTAssertNil(HuggingFaceEnvironment.currentValue(for: "HF_HUB_DISABLE_IMPLICIT_TOKEN"))
    }

    func testCurrentValuePreservesEmptyString() {
        setenv("HF_HUB_OFFLINE", "", 1)

        XCTAssertEqual(HuggingFaceEnvironment.currentValue(for: "HF_HUB_OFFLINE"), "")
    }

    func testOfflineModelLoadingEnvironmentSerializesConcurrentOperations() async throws {
        let firstStarted = expectation(description: "first operation started")
        let releaseFirstOperation = TestGate()
        let secondStarted = TestFlag()

        let firstTask = Task {
            try await HuggingFaceEnvironment.withOfflineModelLoadingEnvironment {
                firstStarted.fulfill()
                await releaseFirstOperation.wait()
            }
        }

        await fulfillment(of: [firstStarted], timeout: 1.0)

        let secondTask = Task {
            try await HuggingFaceEnvironment.withOfflineModelLoadingEnvironment {
                await secondStarted.setTrue()
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        let secondStartedBeforeRelease = await secondStarted.currentValue()
        XCTAssertFalse(secondStartedBeforeRelease)

        await releaseFirstOperation.open()
        _ = try await firstTask.value
        _ = try await secondTask.value

        let secondStartedAfterRelease = await secondStarted.currentValue()
        XCTAssertTrue(secondStartedAfterRelease)
    }

    func testTerminalStatusMessagePreservesDetailedErrors() {
        XCTAssertEqual(
            MLXModelManager.terminalStatusMessage(
                existingStatus: "Error: LocalEntryNotFoundError: snapshot missing",
                exitStatus: 1
            ),
            "Error: LocalEntryNotFoundError: snapshot missing"
        )
        XCTAssertEqual(
            MLXModelManager.terminalStatusMessage(
                existingStatus: "Downloading model files...", exitStatus: 2),
            "Error: Download failed (exit code: 2)"
        )
        XCTAssertNil(MLXModelManager.terminalStatusMessage(existingStatus: nil, exitStatus: 0))
    }
}

private actor TestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private actor TestFlag {
    private(set) var value = false

    func setTrue() {
        value = true
    }

    func currentValue() -> Bool {
        value
    }
}
