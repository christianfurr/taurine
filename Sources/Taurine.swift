import AppKit
import Darwin

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptString(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

private struct TaurineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class PowerConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var directory: String?

    func send(_ byte: UInt8) {
        lock.lock(); defer { lock.unlock() }
        guard socketFD >= 0 else { return }
        var value = byte
        _ = Darwin.send(socketFD, &value, 1, 0)
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        if socketFD >= 0 {
            shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
            socketFD = -1
        }
        if let directory {
            try? FileManager.default.removeItem(atPath: directory)
            self.directory = nil
        }
    }

    func start() throws -> Int32 {
        let folder = "/tmp/taurine.\(getuid()).\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        directory = folder
        let path = folder + "/control.sock"
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw TaurineError(message: "Could not create the local power session.") }
        defer { Darwin.close(listener) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.copyBytes(from: path.utf8CString.map { UInt8(bitPattern: $0) })
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 1) == 0 else {
            throw TaurineError(message: "Could not start the local power session.")
        }
        guard let helper = Bundle.main.path(forAuxiliaryExecutable: "TaurinePower") else {
            throw TaurineError(message: "The power helper is missing. Rebuild or reinstall Taurine.")
        }
        let command = shellQuote(helper) + " " + shellQuote(path) + " " + String(getuid())
        let script = "do shell script " + appleScriptString(command) +
            " with administrator privileges with prompt " +
            appleScriptString("Taurine needs permission to keep your Mac awake with the lid closed.")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if detail.contains("-128") { throw TaurineError(message: "Authorization canceled. Sleep settings were not changed.") }
            throw TaurineError(message: "macOS could not authorize the power helper. \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        var waiting = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard poll(&waiting, 1, 8_000) > 0 else {
            throw TaurineError(message: "The power helper did not connect. Sleep settings were not changed.")
        }
        let connection = accept(listener, nil, nil)
        guard connection >= 0 else { throw TaurineError(message: "Could not connect to the power helper.") }
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(connection, &peerUID, &peerGID) == 0, peerUID == 0 else {
            Darwin.close(connection)
            throw TaurineError(message: "The power helper's identity could not be verified.")
        }
        var noSignal: Int32 = 1
        _ = setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        lock.lock(); socketFD = connection; lock.unlock()
        return connection
    }

    deinit { close() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var toggleItem: NSMenuItem!
    private var sessionItem: NSMenuItem!
    private var connection: PowerConnection?
    private var timer: Timer?
    private var enabledAt: Date?
    private var busy = false
    private var quitting = false
    private var lastMessage = "Normal sleep is allowed"
    private var instanceLock: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch must not create a second menu item or power session.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.christianfurr.Taurine")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        instanceLock = open(support.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard instanceLock >= 0, flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        let title = NSMenuItem(title: "Taurine", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: "Taurine", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        menu.addItem(title)
        sessionItem = NSMenuItem(title: lastMessage, action: nil, keyEquivalent: "")
        menu.addItem(sessionItem)
        menu.addItem(.separator())
        toggleItem = NSMenuItem(title: "Turn Taurine On", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem(title: "Keeps your Mac awake with the lid closed", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Display can still turn off", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Auto-off at 10% battery", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Turn off before putting your Mac in a bag", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Taurine", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.autoenablesItems = false
        for item in menu.items where item.action == nil { item.isEnabled = false }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.connection?.send(72) // H: lease heartbeat, even while awaiting pmset.
            self.refresh()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        refresh()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(enableFromAutomation(_:)),
            name: NSNotification.Name("com.christianfurr.Taurine.enable"), object: nil)
        if ProcessInfo.processInfo.arguments.contains("--enable") {
            DispatchQueue.main.async { self.enableFromAutomation(nil) }
        }
    }

    @objc private func enableFromAutomation(_ notification: Notification?) {
        guard enabledAt == nil, !busy else { return }
        toggle()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        guard statusItem != nil else { return }
        let enabled = enabledAt != nil
        let symbol = enabled ? "bolt.fill" : "bolt"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: enabled ? "Taurine on" : "Taurine off")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.title = enabled ? " On" : ""
        statusItem.button?.toolTip = busy ? "Taurine — updating sleep settings…" :
            (enabled ? "Taurine is on — keeping this Mac awake, including with the lid closed" : "Taurine is off — click to keep this Mac awake")
        statusItem.button?.setAccessibilityLabel(enabled ? "Taurine on" : "Taurine off")
        toggleItem.title = busy ? "Updating sleep settings…" : (enabled ? "Turn Taurine Off" : "Turn Taurine On")
        toggleItem.isEnabled = !busy
        toggleItem.state = enabled ? .on : .off
        if let enabledAt {
            let elapsed = Int(Date().timeIntervalSince(enabledAt))
            sessionItem.title = String(format: "Awake for %d:%02d:%02d", elapsed / 3600, elapsed / 60 % 60, elapsed % 60)
        } else {
            sessionItem.title = busy ? "Waiting for macOS…" : lastMessage
        }
    }

    @objc private func toggle() {
        guard !busy else { return }
        busy = true
        refresh()
        if let connection {
            connection.send(68) // D: restore and acknowledge before showing off.
            return
        }
        lastMessage = "Normal sleep is allowed"
        let newConnection = PowerConnection()
        connection = newConnection
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let fd = try newConnection.start()
                var code: UInt8 = 0
                var acknowledgedEnd = false
                while recv(fd, &code, 1, 0) == 1 {
                    if code == 82 { newConnection.send(69); continue } // R -> E
                    let received = code
                    DispatchQueue.main.async { self?.received(received) }
                    if code != 49 { acknowledgedEnd = true; break }
                }
                let unexpected = !acknowledgedEnd
                DispatchQueue.main.async { self?.ended(unexpected: unexpected) }
            } catch {
                newConnection.close()
                DispatchQueue.main.async {
                    self?.connection = nil
                    self?.busy = false
                    self?.lastMessage = "Taurine is off"
                    self?.refresh()
                    self?.showError(error.localizedDescription)
                    if self?.quitting == true { NSApp.reply(toApplicationShouldTerminate: true) }
                }
            }
        }
    }

    private func received(_ code: UInt8) {
        switch code {
        case 49: // 1: confirmed on
            enabledAt = Date(); busy = false
            if quitting { busy = true; connection?.send(68) }
        case 48: // 0: prior setting restored
            lastMessage = "Previous sleep setting restored"
        case 66:
            lastMessage = "Stopped: battery at or below 10%"
        case 76:
            showError("Another Taurine session is already active. Turn that session off first.")
        case 88:
            showError("Taurine could not restore the previous sleep setting. In Terminal, run: sudo pmset -a disablesleep 0")
        default:
            showError("Taurine could not enable system sleep prevention. The helper attempted to restore the previous setting.")
        }
        refresh()
    }

    private func ended(unexpected: Bool) {
        let wasEnabled = enabledAt != nil
        connection?.close(); connection = nil
        enabledAt = nil; busy = false
        if wasEnabled && lastMessage == "Normal sleep is allowed" {
            lastMessage = "Power session ended — check sleep settings"
        }
        refresh()
        if unexpected {
            showError("The power helper disconnected unexpectedly. Check the sleep setting with pmset -g. To restore normal sleep, run: sudo pmset -a disablesleep 0")
        }
        if quitting { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Taurine"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard connection != nil else { return .terminateNow }
        quitting = true
        busy = true
        connection?.send(68)
        refresh()
        // Wait for the watchdog to confirm restoration before a normal quit.
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        connection?.close()
        if instanceLock >= 0 { Darwin.close(instanceLock) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
