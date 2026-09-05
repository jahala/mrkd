import AppKit
import CoreText

enum FontRegistrar {

    static func registerBundledFonts() {
        // The same list the Mermaid renderer loads into resvg's font
        // database. One home for it: a document set in Literata whose
        // diagrams come out in Helvetica is what two lists would look like.
        for fontFile in BundledFonts.urls {
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
