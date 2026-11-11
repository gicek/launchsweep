import Foundation
import Testing
@testable import LaunchSweep

struct LaunchServicesDumpTests {
    private let separator = String(repeating: "-", count: 80)

    private func registrations(_ records: String...) -> [Registration] {
        let header = "Checking data integrity...\nPath:                       /var/folders/x/db.csstore\n"
        let dump = header + records.map { separator + "\n" + $0 + "\n" }.joined()
        return LaunchServicesDump.registrations(in: Data(dump.utf8))
    }

    @Test func readsAnAppRecord() {
        let result = registrations("""
            bundle id:                  MaskPad (0x42b0)
            container:                  / (0x4)
            path:                       /Applications/MaskPad.app (0x64a8)
            directory:                  /Applications
            name:                       MaskPad Internal
            displayName:                MaskPad
            identifier:                 com.gicek.maskpad
            version:                    4.0 ({length = 32, bytes = 0x04000000 })
            versionString:              4
            displayVersion:             1.0.3
            reg date:                   2026-11-07 12:44 (POSIX 1794026663, 𝛥 3days 23hr 6min 20sec)
            """)
        #expect(result == [Registration(
            path: "/Applications/MaskPad.app",
            identifier: "com.gicek.maskpad",
            name: "MaskPad",
            version: "1.0.3",
            registered: Date(timeIntervalSince1970: 1_794_026_663)
        )])
    }

    @Test func keepsPathsWithSpacesParenthesesAndNonASCIICharacters() {
        let result = registrations(
            """
            bundle id:                  WeChat (0x1)
            path:                       /Volumes/微信 WeChat/WeChat (2).app (0x1db0)
            """,
            """
            bundle id:                  Helper (0x2)
            path:                       /Applications/A.app/Contents/Helpers/A Helper (Renderer).app (0x1db4)
            """
        )
        #expect(result.map(\.path) == [
            "/Volumes/微信 WeChat/WeChat (2).app",
            "/Applications/A.app/Contents/Helpers/A Helper (Renderer).app",
        ])
    }

    @Test func skipsRecordsThatAreNotApps() {
        let result = registrations(
            """
            plugin id:                  Share (0x10)
            path:                       /Applications/A.app/Contents/PlugIns/Share.appex (0x20)
            """,
            """
            bundle id:                  Share (0x11)
            path:                       /Applications/A.app/Contents/PlugIns/Share.appex (0x21)
            """,
            """
            bundle id:                  Zed (0x12)
            path:                       /Volumes/Zed (0x2524)
            """,
            """
            type id:                    public.item (0x13)
            uti:                        public.item
            """
        )
        #expect(result.isEmpty)
    }

    @Test func ignoresNestedValuesAndRepeatedKeys() {
        let result = registrations("""
            bundle id:                  Foo (0x1)
            path:                       /Applications/Foo.app (0x2)
            identifier:                 com.example.foo
            infoDictionary:             2 values (1 (0x1))
                                        {
                                            CFBundleIdentifier = "com.example.nested";
                                            path = "/Applications/Other.app";
                                        }
            identifier:                 com.example.later
            """)
        #expect(result.map(\.path) == ["/Applications/Foo.app"])
        #expect(result.first?.identifier == "com.example.foo")
    }

    @Test func fallsBackToTheNameAndLeavesMissingValuesEmpty() {
        // The trailing space after "identifier:" is how an empty value is printed.
        let result = registrations([
            "bundle id:                  Foo (0x1)",
            "path:                       /Applications/Foo.app (0x2)",
            "name:                       Foo",
            "identifier:                 ",
        ].joined(separator: "\n"))
        #expect(result == [
            Registration(path: "/Applications/Foo.app", identifier: nil, name: "Foo", version: nil, registered: nil),
        ])
    }

    @Test func readsTheLastRecordWithoutATrailingNewline() {
        let dump = """
            \(separator)
            bundle id:                  Foo (0x1)
            path:                       /Applications/Foo.app (0x2)
            """
        #expect(LaunchServicesDump.registrations(in: Data(dump.utf8)).map(\.path) == ["/Applications/Foo.app"])
    }
}
