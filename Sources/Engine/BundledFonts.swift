import Foundation

/// The typefaces mrkd ships inside its own bundle.
///
/// Two things read this list and they must not disagree. CoreText registers
/// the files so a document can be *set* in Inter or Literata; the Mermaid
/// renderer loads the same files into resvg's font database so a *diagram* in
/// that document can be set in them too. resvg resolves fonts through
/// `fontdb`, which scans the system font directories and nothing else — an
/// app bundle's own fonts are invisible to it unless they are handed over by
/// path, which is what this list is for.
enum BundledFonts {

    /// The font files in the running bundle, or nothing if it carries none.
    ///
    /// Empty is a real answer rather than a failure: a build with no bundled
    /// fonts renders in the system's, which is worse-looking but not broken.
    static var urls: [URL] {
        guard let fonts = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else {
            return []
        }
        return fontFiles(in: fonts)
    }

    /// The TrueType files directly inside `directory`, in a stable order.
    ///
    /// Sorted because the renderer caches its font database against this list
    /// and rebuilding it costs a few hundred milliseconds: a directory
    /// enumeration that came back in a different order would throw that away
    /// on the first diagram of every launch.
    static func fontFiles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        return contents
            .filter { $0.pathExtension.lowercased() == "ttf" }
            .sorted { $0.path < $1.path }
    }
}
