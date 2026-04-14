import Foundation

struct VersionInfo {
    static let version = "2.1.0"
    static let gitHash = "c1c8f3af60c6fc43a653156bc1343eaeae6acda7"
    static let buildDate = "2026-04-13"
    
    static var displayVersion: String {
        if gitHash != "dev-build" && gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            return "\(version) (\(shortHash))"
        }
        return version
    }
    
    static var fullVersionInfo: String {
        var info = "VoiceFlow \(version)"
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