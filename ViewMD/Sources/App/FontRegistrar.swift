import AppKit
import CoreText

enum FontRegistrar {

    static func registerBundledFonts() {
        guard let fontsURL = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }

        let fileManager = FileManager.default
        guard let fontFiles = try? fileManager.contentsOfDirectory(
            at: fontsURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for fontFile in fontFiles where fontFile.pathExtension.lowercased() == "ttf" {
            var error: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(fontFile as CFURL, .process, &error)
            if !success, let err = error?.takeRetainedValue() {
                let nsError = err as Error as NSError
                // Silence "already registered" (domain: kCTFontManagerErrorDomain, code 105)
                // which happens because ATSApplicationFontsPath also registers them.
                if nsError.code != 105 {
                    NSLog("Failed to register font %@: %@", fontFile.lastPathComponent, nsError.localizedDescription)
                }
            }
        }
    }
}
