import Foundation

struct VersionInfo {
    static let version = "2.2.0"
    static let gitHash = "3fbe7f42c96412f11fe32a34202660b93ba60de1"
    static let buildDate = "2026-04-18"

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
