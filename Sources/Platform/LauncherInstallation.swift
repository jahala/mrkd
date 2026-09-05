import Foundation

/// The disk half of installing the `mrkd` command: read what is there, ask the
/// pure decision, and only then write. Nothing here decides policy.
enum LauncherInstallation {

    static func existingEntry(at url: URL, fileManager: FileManager = .default) -> ExistingLauncher {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .none }
        guard !isDirectory.boolValue else { return .opaque }
        guard let data = fileManager.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else { return .opaque }
        return .text(text)
    }

    /// Writes the launcher unless the pure decision says otherwise. Re-running
    /// it with an unchanged script leaves the file untouched; anything at the
    /// path that mrkd did not write is left exactly as it is.
    @discardableResult
    static func install(
        script: String,
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> LauncherInstallDecision {
        let decision = LauncherInstaller.decide(
            existing: existingEntry(at: url, fileManager: fileManager),
            desired: script
        )

        switch decision {
        case .refused:
            return decision
        case .alreadyInstalled:
            try makeExecutable(url, fileManager: fileManager)
            return decision
        case .write:
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try script.write(to: url, atomically: true, encoding: .utf8)
            try makeExecutable(url, fileManager: fileManager)
            return decision
        }
    }

    private static func makeExecutable(_ url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
