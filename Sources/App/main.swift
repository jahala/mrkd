import AppKit

// Started by the installed `mrkd` launcher? Then this process is a command,
// not an app: resolve it and exit before touching NSApplication.
if CLIEntryPoint.shouldHandle(arguments: CommandLine.arguments) {
    exit(CLIEntryPoint.run(arguments: CommandLine.arguments))
}

// main.swift runs on the main thread — safe to create @MainActor types
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
