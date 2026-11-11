import Foundation

/// Whether a path is on disk.
enum Presence: Sendable {
    case present
    case missing
    /// The path can't be examined, for example inside a folder that macOS protects.
    case unknown

    static func onDisk(_ path: String) -> Presence {
        var info = stat()
        if lstat(path, &info) == 0 { return .present }
        return errno == ENOENT || errno == ENOTDIR ? .missing : .unknown
    }
}

/// Picks out the registrations that probably should not exist.
struct Analyzer: Sendable {
    var home = NSHomeDirectory()
    var presence: @Sendable (String) -> Presence = Presence.onDisk

    enum Location: Equatable {
        case trash
        case temporary
        case buildOutput
        /// Where apps are normally installed.
        case standard
        case volume
        case other
    }

    /// The apps to list, sorted by issue and then by name.
    func staleApps(from registrations: [Registration]) -> [StaleApp] {
        // A bundle and the helper apps inside it are one item.
        var groups: [String: [Registration]] = [:]
        for registration in registrations {
            groups[Self.outermostApp(of: registration.path), default: []].append(registration)
        }

        var copies: [String: Int] = [:]
        for (root, members) in groups {
            if let identifier = Self.identifier(ofAppAt: root, in: members) { copies[identifier, default: 0] += 1 }
        }

        let apps = groups.compactMap { root, members -> StaleApp? in
            let identifier = Self.identifier(ofAppAt: root, in: members)
            let isDuplicate = identifier.map { copies[$0, default: 0] > 1 } ?? false
            let presence = presence(root)
            guard let issue = issue(location: location(of: root), presence: presence, isDuplicate: isDuplicate) else {
                return nil
            }
            let main = members.first { $0.path == root }
            return StaleApp(
                path: root,
                registeredPaths: Set(members.map(\.path)).sorted(),
                name: main?.name ?? ((root as NSString).lastPathComponent as NSString).deletingPathExtension,
                identifier: identifier,
                version: main?.version,
                registered: main?.registered ?? members.compactMap(\.registered).max(),
                issue: issue,
                mayExist: presence != .missing
            )
        }
        let order = Issue.allCases
        return apps.sorted { a, b in
            if a.issue != b.issue { return order.firstIndex(of: a.issue)! < order.firstIndex(of: b.issue)! }
            let names = a.name.localizedStandardCompare(b.name)
            return names == .orderedSame ? a.path < b.path : names == .orderedAscending
        }
    }

    /// The installed apps that share a bundle identifier with one of `apps`.
    ///
    /// The app launcher keeps one app per bundle identifier. When that one was a stale copy, the launcher
    /// does not fall back to the installed app after the copy is unregistered; registering the installed
    /// app again makes it show up.
    func installedCopies(of apps: [StaleApp], in registrations: [Registration]) -> [String] {
        let identifiers = Set(apps.compactMap(\.identifier))
        let stale = Set(apps.map(\.path))
        return registrations
            .filter { registration in
                guard let identifier = registration.identifier, identifiers.contains(identifier) else { return false }
                return !stale.contains(registration.path)
                    && Self.outermostApp(of: registration.path) == registration.path
                    && location(of: registration.path) == .standard
                    && presence(registration.path) == .present
            }
            .map(\.path)
            .sorted()
    }

    private func issue(location: Location, presence: Presence, isDuplicate: Bool) -> Issue? {
        if presence == .missing { return .missing }
        switch location {
        case .trash: return .trash
        case .temporary: return .temporary
        case .buildOutput: return .buildOutput
        case .volume: return .volume
        case .standard: return nil
        case .other: return isDuplicate ? .duplicate : nil
        }
    }

    /// The kind of place a path is in, judged from the path alone. The order of the checks matters.
    func location(of path: String) -> Location {
        let components = (path as NSString).pathComponents
        if components.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) { return .trash }
        let temporary = ["/private/var/folders/", "/var/folders/", "/private/tmp/", "/tmp/"]
        if temporary.contains(where: path.hasPrefix) || components.contains("AppTranslocation") { return .temporary }
        // Xcode's DerivedData is inside ~/Library, so it is checked before the standard locations.
        if components.contains("DerivedData") { return .buildOutput }
        let standard = [
            "/Applications/", "/System/", "/Library/", "/usr/", "/opt/", "/bin/", "/sbin/", "/private/", "/nix/",
            home + "/Applications/", home + "/Library/",
        ]
        if standard.contains(where: path.hasPrefix) { return .standard }
        if path.hasPrefix("/Volumes/") { return .volume }
        let buildFolders: Set = ["build", ".build", "dist", "target"]
        if components.contains(where: { buildFolders.contains($0.lowercased()) }) { return .buildOutput }
        return .other
    }

    /// `/Applications/Foo.app/Contents/Helpers/Bar.app` → `/Applications/Foo.app`
    static func outermostApp(of path: String) -> String {
        guard let end = path.range(of: ".app/") else { return path }
        return String(path[..<end.upperBound].dropLast())
    }

    /// The bundle identifier of the app itself, not of its helpers. Unexpanded build settings don't count.
    private static func identifier(ofAppAt root: String, in members: [Registration]) -> String? {
        members.first { $0.path == root }?.identifier.flatMap { $0.contains("$(") ? nil : $0 }
    }
}
