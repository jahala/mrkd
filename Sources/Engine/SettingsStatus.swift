import Foundation

/// What a Settings row shows about something mrkd checks: a word or two, a
/// colour for the dot beside it, the one button that acts on it, and a short
/// note under the group when there is something the user must do by hand.
struct SettingsStatus: Equatable {

    enum Tone: Equatable {
        /// Working as it should. A green dot.
        case good
        /// Needs the user. An orange dot.
        case attention
        /// Neither, such as something not installed yet. No dot.
        case neutral
    }

    let text: String
    let tone: Tone
    /// The button's title, or nil when no button can help.
    let action: String?
    let note: String?
}
