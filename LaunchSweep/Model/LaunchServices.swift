import Foundation

/// Where registrations are read and changed. The app uses `LaunchServices`; tests use their own.
protocol RegistrationStore: Sendable {
    func registrations() async throws -> [Registration]
    /// Unregisters each path. Whether it worked is not reported; read the registrations again to find out.
    func unregister(_ paths: [String]) async
    /// Registers each path again, even if it is already registered and unchanged.
    func register(_ paths: [String]) async
}

/// Reads and changes the Launch Services database through `lsregister`; there is no public API for either.
struct LaunchServices: RegistrationStore {
    private static let tool = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")

    struct ToolError: LocalizedError {
        var errorDescription: String?
    }

    func registrations() async throws -> [Registration] {
        let dump = try await Self.run(["-dump"])
        let registrations = LaunchServicesDump.registrations(in: dump)
        // Every Mac has registered apps, so an empty result means the dump could not be understood.
        guard !registrations.isEmpty else {
            throw ToolError(errorDescription: String(localized: """
                The Launch Services database could not be read. \
                Its format may have changed in this version of macOS.
                """))
        }
        return registrations
    }

    /// `lsregister` does not report reliably whether it worked.
    func unregister(_ paths: [String]) async {
        for path in paths {
            _ = try? await Self.run(["-u", path])
        }
    }

    func register(_ paths: [String]) async {
        for path in paths {
            _ = try? await Self.run(["-f", path])
        }
    }

    private static func run(_ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = tool
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
