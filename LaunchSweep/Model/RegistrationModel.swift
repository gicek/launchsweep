import Foundation
import Observation

/// The window's state: the stale registrations found by the last scan and which of them are selected.
@MainActor
@Observable
final class RegistrationModel {
    enum Phase: Equatable {
        case scanning
        case loaded
        case failed(String)
    }

    private(set) var phase = Phase.scanning
    private(set) var apps: [StaleApp] = []
    /// Paths of the selected apps.
    var selection: Set<String> = []
    /// What the last action did, shown until the next one.
    private(set) var notice: String?
    /// True while unregistering or moving to the Trash.
    private(set) var isWorking = false

    var isBusy: Bool { isWorking || phase == .scanning }
    var selectedApps: [StaleApp] { apps.filter { selection.contains($0.path) } }

    /// Everything the last scan found, stale or not.
    private var registrations: [Registration] = []

    private let store: any RegistrationStore
    private let analyzer: Analyzer
    private let trash: @Sendable (String) throws -> Void

    /// The defaults are the real system; tests pass their own.
    init(
        store: any RegistrationStore = LaunchServices(),
        analyzer: Analyzer = Analyzer(),
        trash: @escaping @Sendable (String) throws -> Void = RegistrationModel.moveItemToTrash
    ) {
        self.store = store
        self.analyzer = analyzer
        self.trash = trash
    }

    /// Scans and selects the apps that are safe to unregister.
    func scan() async {
        notice = nil
        if await load() {
            selection = Set(apps.filter(\.issue.isSelectedByDefault).map(\.path))
        }
    }

    func unregisterSelected() async {
        let targets = selectedApps
        guard !targets.isEmpty, !isBusy else { return }
        isWorking = true
        defer { isWorking = false }

        await unregister(targets)
        guard let registered = await reload() else { return }
        let remaining = targets.count { !registered.isDisjoint(with: $0.registeredPaths) }
        let removed = targets.count - remaining
        notice = if remaining == 0 {
            String(localized: "Unregistered \(removed) apps.")
        } else if removed == 0 {
            String(localized: "Nothing was unregistered. macOS may have registered the selected apps again.")
        } else {
            String(localized: "Unregistered \(removed) of \(targets.count) apps. The others are still registered.")
        }
    }

    /// Moves the app to the Trash and unregisters it, so that macOS has nothing to register again.
    func moveToTrash(_ app: StaleApp) async {
        guard !isBusy else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            // Off the main actor: moving a large app to another volume's Trash can take a while.
            try await Task.detached { [trash] in try trash(app.path) }.value
        } catch {
            notice = String(localized: "\(app.name) could not be moved to the Trash: \(error.localizedDescription)")
            return
        }
        await unregister([app])
        if await reload() != nil {
            notice = String(localized: "Moved \(app.name) to the Trash and unregistered it.")
        }
    }

    nonisolated static func moveItemToTrash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }

    private func unregister(_ targets: [StaleApp]) async {
        // Helpers first, so nothing is left registered inside an app that Launch Services no longer knows.
        await store.unregister(targets.flatMap { $0.registeredPaths.sorted { $0.count > $1.count } })
        // Then the installed copies of the same apps, so the app launcher shows them instead of nothing.
        let installed = await Task.detached { [analyzer, registrations] in
            analyzer.installedCopies(of: targets, in: registrations)
        }.value
        await store.register(installed)
    }

    /// Scans after an action. Returns every path that is registered now, or nil if the scan failed.
    private func reload() async -> Set<String>? {
        guard await load() else { return nil }
        selection = []
        return Set(registrations.map(\.path))
    }

    private func load() async -> Bool {
        phase = .scanning
        do {
            let registrations = try await store.registrations()
            self.registrations = registrations
            apps = await Task.detached { [analyzer] in analyzer.staleApps(from: registrations) }.value
            phase = .loaded
            return true
        } catch {
            apps = []
            selection = []
            phase = .failed(error.localizedDescription)
            return false
        }
    }
}
