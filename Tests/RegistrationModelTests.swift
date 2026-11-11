import Foundation
import os
import Testing
@testable import LaunchSweep

/// A registration database in memory.
private actor FakeStore: RegistrationStore {
    private var registered: [Registration]
    /// Paths that stay registered whatever is done, like copies that macOS registers again at once.
    private let sticky: Set<String>
    private var fails = false
    private(set) var unregistered: [String] = []
    private(set) var reregistered: [String] = []

    init(_ registered: [Registration], sticky: Set<String> = []) {
        self.registered = registered
        self.sticky = sticky
    }

    func failFromNowOn() { fails = true }

    func registrations() throws -> [Registration] {
        if fails { throw LaunchServices.ToolError(errorDescription: "unreadable") }
        return registered
    }

    func unregister(_ paths: [String]) {
        unregistered += paths
        registered.removeAll { paths.contains($0.path) && !sticky.contains($0.path) }
    }

    func register(_ paths: [String]) {
        reregistered += paths
    }
}

@MainActor
struct RegistrationModelTests {
    private let installed = "/Applications/Foo.app"
    private let build = "/Users/me/Developer/Foo/build/Foo.app"
    private let helper = "/Users/me/Developer/Foo/build/Foo.app/Contents/Helpers/Foo Helper.app"
    private let otherBuild = "/Users/me/Developer/Bar/build/Bar.app"
    private let volume = "/Volumes/Installer/Baz.app"

    private var registrations: [Registration] {
        [
            app(installed, "com.example.foo"),
            app(build, "com.example.foo"),
            app(helper, "com.example.foo.helper"),
            app(otherBuild, "com.example.bar"),
            app(volume, "com.example.baz"),
        ]
    }

    private func app(_ path: String, _ identifier: String) -> Registration {
        Registration(path: path, identifier: identifier, name: nil, version: nil, registered: nil)
    }

    /// A model for a disk on which every path exists, and the paths that were moved to the Trash.
    private func model(
        _ store: FakeStore,
        trashFails: Bool = false
    ) -> (model: RegistrationModel, trashed: OSAllocatedUnfairLock<[String]>) {
        let trashed = OSAllocatedUnfairLock(initialState: [String]())
        let model = RegistrationModel(store: store, analyzer: Analyzer(home: "/Users/me") { _ in .present }) { path in
            if trashFails { throw CocoaError(.fileWriteNoPermission) }
            trashed.withLock { $0.append(path) }
        }
        return (model, trashed)
    }

    @Test func scanSelectsWhatIsSafeToUnregister() async {
        let (model, _) = model(FakeStore(registrations))
        #expect(model.phase == .scanning)
        await model.scan()
        #expect(model.phase == .loaded)
        #expect(model.apps.map(\.path) == [otherBuild, build, volume])
        #expect(model.selection == [build, otherBuild])
        #expect(model.notice == nil)
    }

    @Test func scanFailureClearsTheList() async {
        let store = FakeStore(registrations)
        let (model, _) = model(store)
        await model.scan()
        await store.failFromNowOn()
        await model.scan()
        #expect(model.phase == .failed("unreadable"))
        #expect(model.apps.isEmpty)
        #expect(model.selection.isEmpty)
    }

    @Test func unregistersHelpersFirstThenRegistersTheInstalledCopy() async {
        let store = FakeStore(registrations)
        let (model, _) = model(store)
        await model.scan()
        model.selection = [build]
        await model.unregisterSelected()

        #expect(await store.unregistered == [helper, build])
        #expect(await store.reregistered == [installed])
        #expect(model.apps.map(\.path) == [otherBuild, volume])
        #expect(model.selection.isEmpty)
        #expect(model.notice == String(localized: "Unregistered \(1) apps."))
        #expect(!model.isBusy)
    }

    @Test func reportsAppsThatAreStillRegistered() async {
        let store = FakeStore(registrations, sticky: [helper])
        let (model, _) = model(store)
        await model.scan()
        await model.unregisterSelected()

        #expect(model.apps.map(\.path) == [build, volume])
        #expect(model.notice == String(localized: "Unregistered \(1) of \(2) apps. The others are still registered."))
    }

    @Test func reportsWhenNothingWasUnregistered() async {
        let store = FakeStore(registrations, sticky: [build, otherBuild])
        let (model, _) = model(store)
        await model.scan()
        await model.unregisterSelected()

        #expect(model.apps.map(\.path) == [otherBuild, build, volume])
        #expect(model.notice == String(
            localized: "Nothing was unregistered. macOS may have registered the selected apps again."
        ))
    }

    @Test func doesNothingWithoutASelection() async {
        let store = FakeStore(registrations)
        let (model, _) = model(store)
        await model.scan()
        model.selection = []
        await model.unregisterSelected()

        #expect(await store.unregistered.isEmpty)
        #expect(model.notice == nil)
    }

    @Test func movesToTheTrashAndUnregisters() async throws {
        let store = FakeStore(registrations)
        let (model, trashed) = model(store)
        await model.scan()
        let target = try #require(model.apps.first { $0.path == build })
        await model.moveToTrash(target)

        #expect(trashed.withLock { $0 } == [build])
        #expect(await store.unregistered == [helper, build])
        #expect(await store.reregistered == [installed])
        #expect(model.apps.map(\.path) == [otherBuild, volume])
        #expect(model.notice != nil)
    }

    @Test func leavesTheRegistrationWhenMovingToTheTrashFails() async throws {
        let store = FakeStore(registrations)
        let (model, _) = model(store, trashFails: true)
        await model.scan()
        let target = try #require(model.apps.first { $0.path == build })
        await model.moveToTrash(target)

        #expect(await store.unregistered.isEmpty)
        #expect(model.apps.contains(target))
        #expect(model.notice != nil)
        #expect(!model.isBusy)
    }
}
