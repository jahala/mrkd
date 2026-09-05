import Foundation

/// One document, one window. A shell can spell the same file several ways —
/// `./plan.md`, `docs/../plan.md`, through a symlinked folder, `/tmp` versus
/// `/private/tmp` — so windows are matched on a resolved key rather than on the
/// URL as it arrived.
enum DocumentIdentity {
    static func key(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
