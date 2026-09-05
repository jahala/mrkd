import Foundation

/// `mrkd` with no arguments reopens the last document. The recent list outlives
/// the files in it, so the first entry is not necessarily an answer.
enum RecentDocuments {

    /// The most recent entry that can still be opened, newest first.
    static func mostRecent(from urls: [URL], isOpenable: (URL) -> Bool) -> URL? {
        urls.first(where: isOpenable)
    }

    /// The real test the app applies: a readable regular file, not a folder.
    static func isOpenableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue && FileManager.default.isReadableFile(atPath: url.path)
    }
}
