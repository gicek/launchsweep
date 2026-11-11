import Foundation

/// Why a registration is listed.
enum Issue: CaseIterable, Sendable {
    case missing
    case trash
    case temporary
    case buildOutput
    case volume
    case duplicate

    var title: String {
        switch self {
        case .missing: String(localized: "No Longer on Disk")
        case .trash: String(localized: "In the Trash")
        case .temporary: String(localized: "Temporary Locations")
        case .buildOutput: String(localized: "Build Output")
        case .volume: String(localized: "Mounted Volumes")
        case .duplicate: String(localized: "Duplicate Copies")
        }
    }

    var explanation: String {
        switch self {
        case .missing:
            String(localized: "These apps were deleted or moved, or were on a disk image that is no longer mounted.")
        case .trash:
            String(localized: "These apps are in the Trash but still registered.")
        case .temporary:
            String(localized: "Copies in temporary folders, such as apps that macOS ran from a randomized location.")
        case .buildOutput:
            String(localized: """
                Copies produced by builds. macOS registers them again the next time it sees them, \
                for example after another build.
                """)
        case .volume:
            String(localized: """
                Apps on disk images or external drives that are mounted now. \
                Ejecting a disk image does not remove its registration.
                """)
        case .duplicate:
            String(localized: """
                Copies outside the usual app folders that share a bundle identifier \
                with another registered app.
                """)
        }
    }

    /// Whether unregistering is almost certainly what the user wants, so the app starts out selected.
    var isSelectedByDefault: Bool {
        switch self {
        case .missing, .trash, .temporary, .buildOutput: true
        case .volume, .duplicate: false
        }
    }
}

/// A registered app that probably should not be registered, together with the helper apps inside it.
struct StaleApp: Identifiable, Equatable, Sendable {
    /// The outermost app bundle.
    var path: String
    /// Every registered path in the bundle: the app itself if it is registered, and the apps nested in it.
    var registeredPaths: [String]
    var name: String
    var identifier: String?
    var version: String?
    var registered: Date?
    var issue: Issue
    /// False when the app is known to be gone; true when it exists or that can't be checked.
    var mayExist: Bool

    var id: String { path }
    var helperCount: Int { registeredPaths.count { $0 != path } }
}
