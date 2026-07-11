import Foundation

/// Identifiers shared between the app and the widget extension.
///
/// Both targets must enable the **App Groups** capability with the identifier
/// below. The App Group is used for two things:
///
///  1. A shared `UserDefaults` suite that stores the connected-provider list and
///     the most recent usage snapshots.
///  2. A keychain access group (an App Group identifier is a valid keychain
///     access group), so API keys can be shared without hardcoding a Team ID.
enum AppGroup {
    /// Must match the App Group configured on both targets' entitlements.
    static let identifier = "group.fyi.jono.UsageAI"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
