import Foundation

/// What a path on the command line turned out to be. Filesystem state is
/// resolved once, by the caller, and handed to the parser as a value.
enum PathKind: Equatable {
    case missing
    case file
    case directory

    /// The real probe the app uses. Kept next to the type so tests can drive
    /// the parser with genuine filesystem answers.
    static func of(_ url: URL, fileManager: FileManager = .default) -> PathKind {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .missing }
        return isDirectory.boolValue ? .directory : .file
    }
}

/// What the shell attached to file descriptor 0.
enum StandardInputKind: Equatable {
    /// A terminal — the user typed `mrkd` and is not feeding us anything.
    case terminal
    /// A pipe, socket or redirected file — there is a document waiting.
    case piped
    /// /dev/null or nothing usable, which is what LaunchServices hands a GUI app.
    case absent

    static func detect(fileDescriptor: Int32) -> StandardInputKind {
        if isatty(fileDescriptor) == 1 { return .terminal }

        var info = stat()
        guard fstat(fileDescriptor, &info) == 0 else { return .absent }

        switch info.st_mode & S_IFMT {
        case S_IFIFO, S_IFREG, S_IFSOCK:
            return .piped
        default:
            return .absent
        }
    }
}

/// A command line mrkd will not act on, and the sentence the user gets.
enum CLIFailure: Equatable {
    case noSuchFile(String)
    case isDirectory(String)
    case tooManyArguments(count: Int)

    var message: String {
        switch self {
        case .noSuchFile(let path):
            return "mrkd: no such file: \(path)"
        case .isDirectory(let path):
            return "mrkd: \(path) is a directory — mrkd opens one Markdown file at a time"
        case .tooManyArguments(let count):
            return "mrkd: expected one file, got \(count)"
        }
    }
}

/// The single decision the command line resolves to. Every branch is a value;
/// nothing here touches the disk, the pasteboard or the app.
enum CLIInvocation: Equatable {
    case openFile(URL)
    case renderStandardInput
    case restoreLastDocument
    case showUsage
    case failed(CLIFailure)
}

enum CLIArgumentParser {

    static let usage = """
        usage: mrkd [FILE]     open FILE, or focus the window already showing it
               mrkd -          render the Markdown arriving on standard input
               mrkd            reopen the most recent document

        Folders are not supported.
        """

    /// - Parameters:
    ///   - arguments: the arguments after the executable name and the CLI sentinel.
    ///   - standardInput: what is attached to file descriptor 0.
    ///   - workingDirectory: the directory relative paths are resolved against.
    ///   - pathKind: resolves a path to what is actually there.
    static func parse(
        arguments: [String],
        standardInput: StandardInputKind,
        workingDirectory: URL,
        pathKind: (URL) -> PathKind
    ) -> CLIInvocation {
        guard arguments.count <= 1 else {
            return .failed(.tooManyArguments(count: arguments.count))
        }

        guard let argument = arguments.first else {
            return standardInput == .piped ? .renderStandardInput : .restoreLastDocument
        }

        switch argument {
        case "-":
            return .renderStandardInput
        case "-h", "--help":
            return .showUsage
        default:
            break
        }

        // isDirectory: true is load-bearing — resolving "plan.md" against a base
        // without a trailing slash drops the base's last component and looks in
        // the parent directory instead.
        let base = URL(fileURLWithPath: workingDirectory.path, isDirectory: true)
        let url = URL(fileURLWithPath: argument, relativeTo: base)
            .absoluteURL
            .standardizedFileURL

        switch pathKind(url) {
        case .file:
            return .openFile(url)
        case .directory:
            return .failed(.isDirectory(argument))
        case .missing:
            return .failed(.noSuchFile(argument))
        }
    }
}
