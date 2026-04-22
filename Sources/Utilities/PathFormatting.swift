import Foundation

internal enum PathFormatting {
    static func displayHomeRelativePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        if path == home {
            return "~"
        }

        guard path.hasPrefix(home + "/") else {
            return path
        }

        return "~" + path.dropFirst(home.count)
    }
}
