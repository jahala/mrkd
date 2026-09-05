import AppKit

/// The find shortcut table, as a function of the two values a key event
/// carries.
///
/// The app drives find from its Edit menu. This exists for hosts that have
/// no menu bar — the Quick Look preview extension shares this controller
/// but not the app's menus — and keeping it a function over values means
/// the table is testable without synthesising events.
enum FindKeyEquivalent {

    static func action(
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSTextFinder.Action? {
        // Caps lock and the function/numeric-pad markers ride along on
        // ordinary key presses and say nothing about the shortcut.
        let held = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        guard held.contains(.command) else { return nil }
        guard held.subtracting([.command, .shift]).isEmpty else { return nil }
        let shifted = held.contains(.shift)

        switch characters.lowercased() {
        case "f": return shifted ? nil : .showFindInterface
        case "g": return shifted ? .previousMatch : .nextMatch
        case "e": return shifted ? nil : .setSearchString
        default:  return nil
        }
    }
}
