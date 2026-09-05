import Foundation

/// Piped Markdown has no file, but LaunchServices only carries URLs. The
/// command line parks the piped bytes in one directory it owns and opens that
/// URL; the app recognises anything from that directory as source without a
/// document, reads it, and deletes it. The directory is the whole protocol —
/// both halves are the same binary, so there is no version to negotiate.
enum StdinCapsule {

    static func directory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("com.mrkd.app")
            .appendingPathComponent("stdin")
    }

    static func fileURL(homeDirectory: URL, identifier: String) -> URL {
        directory(homeDirectory: homeDirectory)
            .appendingPathComponent(identifier)
            .appendingPathExtension("md")
    }

    static func isCapsule(_ url: URL, homeDirectory: URL) -> Bool {
        let parent = url.resolvingSymlinksInPath()
            .standardizedFileURL
            .deletingLastPathComponent()
            .standardizedFileURL
        let capsules = directory(homeDirectory: homeDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return parent.path == capsules.path
    }
}
