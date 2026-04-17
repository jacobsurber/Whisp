import Foundation

private actor HuggingFaceEnvironmentLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
            return
        }

        isLocked = false
    }
}

internal enum HuggingFaceEnvironment {
    private static let offlineKeys = ["HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE"]
    private static let managedKeys = offlineKeys + ["HF_HUB_DISABLE_IMPLICIT_TOKEN"]
    private static let offlineEnvironmentLock = HuggingFaceEnvironmentLock()

    static func downloadProcessEnvironment(base: [String: String], cacheDirectory: URL) -> [String: String] {
        var environment = base
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HOME"] = cacheDirectory.path
        environment["HF_HUB_CACHE"] = HuggingFaceCache.hubDirectory(rootDirectory: cacheDirectory).path
        environment["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"

        for key in offlineKeys {
            environment.removeValue(forKey: key)
        }

        return environment
    }

    static func withOfflineModelLoadingEnvironment<T>(_ operation: () async throws -> T) async throws -> T {
        await offlineEnvironmentLock.acquire()

        let overrides = [
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_HUB_DISABLE_IMPLICIT_TOKEN": "1",
        ]
        let previousValues = snapshot(for: managedKeys)
        let lock = offlineEnvironmentLock

        for (key, value) in overrides {
            setenv(key, value, 1)
        }

        defer {
            restore(previousValues)
            Task {
                await lock.release()
            }
        }

        return try await operation()
    }

    static func currentValue(for key: String) -> String? {
        key.withCString { keyPointer in
            guard let valuePointer = getenv(keyPointer) else {
                return nil
            }

            return String(cString: valuePointer)
        }
    }

    private static func snapshot(for keys: [String]) -> [String: String?] {
        var values: [String: String?] = [:]
        for key in keys {
            values[key] = currentValue(for: key)
        }
        return values
    }

    private static func restore(_ values: [String: String?]) {
        for (key, value) in values {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}
