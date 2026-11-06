import Foundation
import IOKit.pwr_mgt
import Darwin

// The unprivileged guard owns the display assertion and the temporary saver setting.
enum IdleLockGuard {
    private struct Saved: Codable { let idleTime: Int? }
    private static let domain = "com.apple.screensaver" as CFString
    private static let key = "idleTime" as CFString
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.christianfurr.Taurine")
    }
    private static var journal: URL { folder.appendingPathComponent("idle-lock-restore.json") }

    private static func current() -> CFPropertyList? {
        CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    private static func write(_ value: Int?) -> Bool {
        CFPreferencesSetValue(key, value.map { NSNumber(value: $0) }, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else { return false }
        return current() as? Int == value
    }

    private static func recoverLocked() throws {
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: journal))
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        // Leave any newer value the user chose in System Settings alone.
        if current() as? Int == 0 && !write(saved.idleTime) { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.removeItem(at: journal)
    }

    private static func withLock(_ work: () throws -> Void) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(folder.appendingPathComponent("idle-lock.lock").path,
                      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileWriteUnknown) }
        try work()
    }

    static func recover() {
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        try? withLock { try recoverLocked() }
    }

    static func run() -> Int32 {
        guard geteuid() != 0 else { return 1 }
        signal(SIGPIPE, SIG_IGN)
        do {
            try withLock {
                try recoverLocked()
                guard !CFPreferencesAppValueIsForced(key, domain) else { throw CocoaError(.fileWriteNoPermission) }
                let prior = current()
                let original = prior as? Int
                guard prior == nil || original != nil else { throw CocoaError(.fileReadCorruptFile) }

                var assertion: IOPMAssertionID = 0
                let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn), "Taurine: prevent idle lock" as CFString, &assertion)
                guard result == kIOReturnSuccess else { throw CocoaError(.featureUnsupported) }
                defer { IOPMAssertionRelease(assertion) }
                defer { try? recoverLocked() }
                if original != 0 {
                    try JSONEncoder().encode(Saved(idleTime: original)).write(to: journal, options: .atomic)
                    guard write(0) else { throw CocoaError(.fileWriteUnknown) }
                }

                var ready: UInt8 = 82
                guard Darwin.write(STDOUT_FILENO, &ready, 1) == 1 else { return }
                var lastBeat = ProcessInfo.processInfo.systemUptime
                while ProcessInfo.processInfo.systemUptime - lastBeat < 15 {
                    var input = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
                    let result = poll(&input, 1, 1000)
                    if result < 0 && errno == EINTR { continue }
                    if result < 0 { break }
                    if result == 0 { continue }
                    var byte: UInt8 = 0
                    guard read(STDIN_FILENO, &byte, 1) == 1, byte == 72 else { break }
                    lastBeat = ProcessInfo.processInfo.systemUptime
                }
                try recoverLocked()
            }
            return 0
        } catch {
            return 1
        }
    }
}
