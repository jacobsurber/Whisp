import Foundation

struct VersionInfo {
    static let version = "2.1.0"
    static let gitHash = "fb7a6fd5f0a64115211ba97aab15c135649eb91b"
    static let buildDate = "2026-04-16"

    static var displayVersion: String {
        if gitHash != "dev-build" && gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            return "\(version) (\(shortHash))"
        }
        return version
    }

    static var fullVersionInfo: String {
        var info = "Whisp \(version)"
        if gitHash != "dev-build" && gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            info += " • \(shortHash)"
        }
        if !buildDate.isEmpty {
            info += " • \(buildDate)"
        }
        return info
    }
}
