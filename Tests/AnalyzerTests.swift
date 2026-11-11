import Foundation
import Testing
@testable import LaunchSweep

struct AnalyzerTests {
    /// An analyzer for a disk on which only `missing` paths are gone and `unknown` paths can't be examined.
    private func analyzer(missing: Set<String> = [], unknown: Set<String> = []) -> Analyzer {
        Analyzer(home: "/Users/me") { path in
            missing.contains(path) ? .missing : unknown.contains(path) ? .unknown : .present
        }
    }

    private func app(
        _ path: String,
        _ identifier: String? = nil,
        name: String? = nil,
        version: String? = nil,
        registered: Date? = nil
    ) -> Registration {
        Registration(path: path, identifier: identifier, name: name, version: version, registered: registered)
    }

    @Test(arguments: [
        ("/Applications/Foo.app", Analyzer.Location.standard),
        ("/System/Applications/Mail.app", .standard),
        ("/Users/me/Applications/Foo.app", .standard),
        ("/Users/me/Library/Application Support/Foo/Updater.app", .standard),
        ("/Users/me/.Trash/Foo.app", .trash),
        ("/Volumes/Disk/.Trashes/501/Foo.app", .trash),
        ("/private/var/folders/5n/x/T/AppTranslocation/ABC/d/Foo.app", .temporary),
        ("/private/tmp/Foo.app", .temporary),
        ("/Users/me/Library/Developer/Xcode/DerivedData/Foo-abc/Build/Products/Debug/Foo.app", .buildOutput),
        ("/Users/me/Developer/Foo/build/debug/Foo.app", .buildOutput),
        ("/Users/me/Developer/Foo/.build/release/Foo.app", .buildOutput),
        ("/Users/me/Developer/Foo/dist/mac-arm64/Foo.app", .buildOutput),
        ("/Volumes/Foo Installer/Foo.app", .volume),
        ("/Users/me/Downloads/Foo.app", .other),
        ("/Users/other/Applications/Foo.app", .other),
        ("/Users/me/Developer/Foo/target/release/Foo.app", .buildOutput),
        ("/opt/homebrew/Caskroom/foo/1.0/Foo.app", .standard),
        ("/Applications/build/Foo.app", .standard),
    ])
    func locatesPaths(path: String, expected: Analyzer.Location) {
        #expect(analyzer().location(of: path) == expected)
    }

    @Test func leavesInstalledAppsAlone() {
        let apps = analyzer().staleApps(from: [
            app("/Applications/Foo.app", "com.example.foo"),
            app("/Applications/Foo.app/Contents/Helpers/Foo Helper.app", "com.example.foo.helper"),
            app("/Users/me/Downloads/Bar.app", "com.example.bar"),
        ])
        #expect(apps.isEmpty)
    }

    @Test func listsMissingAppsWhereverTheyWere() {
        let paths = ["/Applications/Gone.app", "/Volumes/Installer/Gone.app", "/Users/me/.Trash/Gone.app"]
        let apps = analyzer(missing: Set(paths)).staleApps(from: paths.map { app($0) })
        #expect(apps.map(\.issue) == [.missing, .missing, .missing])
        #expect(apps.allSatisfy { !$0.mayExist })
    }

    @Test func listsAppsByLocation() {
        let apps = analyzer().staleApps(from: [
            app("/Users/me/.Trash/A.app"),
            app("/private/var/folders/x/T/AppTranslocation/1/d/B.app"),
            app("/Users/me/Developer/C/build/C.app"),
            app("/Volumes/D/D.app"),
        ])
        #expect(apps.map(\.issue) == [.trash, .temporary, .buildOutput, .volume])
        #expect(apps.allSatisfy { $0.mayExist })
    }

    @Test func listsAppsThatCannotBeExaminedByLocationOnly() {
        let apps = analyzer(unknown: ["/Users/me/.Trash/A.app", "/Users/me/Downloads/B.app"]).staleApps(from: [
            app("/Users/me/.Trash/A.app"),
            app("/Users/me/Downloads/B.app"),
        ])
        #expect(apps.map(\.path) == ["/Users/me/.Trash/A.app"])
        #expect(apps.first?.mayExist == true)
    }

    @Test func listsCopiesOutsideTheUsualFoldersAsDuplicates() {
        let apps = analyzer().staleApps(from: [
            app("/Applications/Foo.app", "com.example.foo"),
            app("/Users/me/Downloads/Foo.app", "com.example.foo"),
            app("/Users/me/Desktop/Bar.app", "com.example.bar"),
            app("/Users/me/Documents/Bar.app", "com.example.bar"),
        ])
        #expect(apps.map(\.path) == [
            "/Users/me/Desktop/Bar.app", "/Users/me/Documents/Bar.app", "/Users/me/Downloads/Foo.app",
        ])
        #expect(apps.allSatisfy { $0.issue == .duplicate })
    }

    @Test func doesNotCountHelpersOrUnexpandedIdentifiersAsDuplicates() {
        let updater = "/Contents/Frameworks/Sparkle.framework/Updater.app"
        let apps = analyzer().staleApps(from: [
            app("/Applications/Foo.app" + updater, "org.sparkle-project.Sparkle.Updater"),
            app("/Users/me/Downloads/Bar.app" + updater, "org.sparkle-project.Sparkle.Updater"),
            app("/Users/me/Desktop/A.app", "$(WRAPPEDPRODUCTBUNDLEIDENTIFIER)"),
            app("/Users/me/Documents/B.app", "$(WRAPPEDPRODUCTBUNDLEIDENTIFIER)"),
        ])
        #expect(apps.isEmpty)
    }

    @Test func groupsHelpersWithTheirApp() throws {
        let root = "/Users/me/Developer/Foo/build/Foo.app"
        let helper = root + "/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
        let apps = analyzer().staleApps(from: [
            app(helper, "org.sparkle-project.Sparkle.Updater", name: "Updater", version: "2.0"),
            app(root, "com.example.foo", name: "Foo", version: "1.2", registered: Date(timeIntervalSince1970: 5)),
        ])
        let app = try #require(apps.first)
        #expect(apps.count == 1)
        #expect(app.path == root)
        #expect(app.registeredPaths == [root, helper])
        #expect(app.helperCount == 1)
        #expect(app.name == "Foo")
        #expect(app.identifier == "com.example.foo")
        #expect(app.version == "1.2")
    }

    @Test func listsAnAppWhoseOnlyRegistrationIsAHelper() throws {
        let helper = "/Applications/Gone.app/Contents/Library/LoginItems/Gone Helper.app"
        let apps = analyzer(missing: ["/Applications/Gone.app"]).staleApps(from: [
            app(helper, "com.example.helper", name: "Gone Helper", version: "1"),
        ])
        let app = try #require(apps.first)
        #expect(app.path == "/Applications/Gone.app")
        #expect(app.name == "Gone")
        #expect(app.identifier == nil)
        #expect(app.registeredPaths == [helper])
        #expect(app.issue == .missing)
    }

    @Test func findsTheInstalledCopiesOfStaleApps() {
        let registrations = [
            app("/Applications/Foo.app", "com.example.foo"),
            app("/Applications/Foo.app/Contents/Helpers/Foo Helper.app", "com.example.foo"),
            app("/Users/me/Applications/Bar.app", "com.example.bar"),
            app("/Applications/Gone.app", "com.example.gone"),
            app("/Applications/Other.app", "com.example.other"),
            app("/Users/me/Developer/Foo/build/Foo.app", "com.example.foo"),
            app("/Users/me/Downloads/Foo.app", "com.example.foo"),
            app("/Users/me/Developer/Bar/build/Bar.app", "com.example.bar"),
            app("/Users/me/Developer/Gone/build/Gone.app", "com.example.gone"),
            app("/Users/me/Developer/Baz/build/Baz.app", "com.example.baz"),
        ]
        let analyzer = analyzer(missing: ["/Applications/Gone.app"])
        let stale = analyzer.staleApps(from: registrations).filter { $0.issue == .buildOutput }
        #expect(stale.count == 4)
        #expect(analyzer.installedCopies(of: stale, in: registrations) == [
            "/Applications/Foo.app", "/Users/me/Applications/Bar.app",
        ])
    }

    @Test func findsNoInstalledCopyOfAStaleAppThatIsItselfInstalled() {
        let registrations = [app("/Applications/Gone.app", "com.example.gone")]
        let analyzer = analyzer(missing: ["/Applications/Gone.app"])
        let stale = analyzer.staleApps(from: registrations)
        #expect(stale.count == 1)
        #expect(analyzer.installedCopies(of: stale, in: registrations).isEmpty)
    }

    @Test func sortsByIssueThenName() {
        let apps = analyzer(missing: ["/Applications/b.app", "/Applications/A.app"]).staleApps(from: [
            app("/Volumes/X/X.app"),
            app("/Applications/b.app"),
            app("/Users/me/.Trash/T.app"),
            app("/Applications/A.app"),
        ])
        #expect(apps.map(\.name) == ["A", "b", "T", "X"])
    }
}
