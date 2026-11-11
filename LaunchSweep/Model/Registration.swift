import Foundation

/// One application bundle registered with Launch Services, as printed by `lsregister -dump`.
struct Registration: Equatable, Sendable {
    var path: String
    var identifier: String?
    var name: String?
    var version: String?
    var registered: Date?
}

/// Reads application registrations out of the text that `lsregister -dump` prints.
///
/// The format is undocumented. Records are separated by a line of dashes; an application bundle's record
/// starts with `bundle id:` and lists `key: value` pairs at the start of a line, with nested values (such as
/// the Info.plist) indented below their key.
enum LaunchServicesDump {
    static func registrations(in dump: Data) -> [Registration] {
        var registrations: [Registration] = []
        var record = Record()

        func finishRecord() {
            if let registration = record.registration { registrations.append(registration) }
            record = Record()
        }

        dump.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let base = bytes.baseAddress else { return }
            var start = 0
            while start < bytes.count {
                let newline = memchr(base + start, 0x0A, bytes.count - start)
                let end = newline.map { base.distance(to: UnsafeRawPointer($0)) } ?? bytes.count
                let line = UnsafeRawBufferPointer(rebasing: bytes[start..<end])
                if isSeparator(line) {
                    finishRecord()
                } else {
                    record.read(line)
                }
                start = end + 1
            }
        }
        finishRecord()
        return registrations
    }

    private static func isSeparator(_ line: UnsafeRawBufferPointer) -> Bool {
        line.count >= 20 && line.allSatisfy { $0 == UInt8(ascii: "-") }
    }

    private struct Record {
        private var isBundle = false
        private var values: [String: String] = [:]

        private static let keys = [
            "bundle id", "path", "identifier", "name", "displayName", "displayVersion", "reg date",
        ].map { (name: $0, prefix: Array("\($0):".utf8)) }

        mutating func read(_ line: UnsafeRawBufferPointer) {
            // Keys start in the first column; nested values are indented.
            guard let first = line.first, first != UInt8(ascii: " "), first != UInt8(ascii: "\t") else { return }
            for key in Self.keys where line.starts(with: key.prefix) {
                // A record's own keys come before its nested values, so the first occurrence is the real one.
                guard values[key.name] == nil else { return }
                let value = String(decoding: line.dropFirst(key.prefix.count), as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces)
                values[key.name] = value
                if key.name == "bundle id" { isBundle = true }
                return
            }
        }

        var registration: Registration? {
            guard isBundle, let path = values["path"].map(Self.removingUnitID), path.hasSuffix(".app") else {
                return nil
            }
            func value(_ key: String) -> String? {
                values[key].flatMap { $0.isEmpty ? nil : $0 }
            }
            return Registration(
                path: path,
                identifier: value("identifier"),
                name: value("displayName") ?? value("name"),
                version: value("displayVersion"),
                registered: value("reg date").flatMap(Self.date)
            )
        }

        /// `/Applications/Foo.app (0x64a8)` → `/Applications/Foo.app`
        private static func removingUnitID(_ value: String) -> String {
            guard value.hasSuffix(")"), let open = value.range(of: " (0x", options: .backwards) else { return value }
            let digits = value[open.upperBound...].dropLast()
            guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return value }
            return String(value[..<open.lowerBound])
        }

        /// `2026-11-07 12:44 (POSIX 1794026663, 𝛥 3days 23hr)` → the POSIX time
        private static func date(_ value: String) -> Date? {
            guard let marker = value.range(of: "POSIX ") else { return nil }
            let seconds = value[marker.upperBound...].prefix(while: \.isNumber)
            return TimeInterval(seconds).map(Date.init(timeIntervalSince1970:))
        }
    }
}
