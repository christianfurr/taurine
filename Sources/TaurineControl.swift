import AppKit
import Foundation

let bundleIDs = ["com.christianfurr.Taurine", "com.christianfurr.Caffeine"]
let arguments = Array(CommandLine.arguments.dropFirst())
let automationApp = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/share/taurine/Taurine.app")

func output(_ value: [String: Any], code: Int32 = 0) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
    exit(code)
}

func apps() -> [NSRunningApplication] {
    bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        .filter { !$0.isTerminated }
}

func sleepDisabled() throws -> Bool {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "TaurineControl", code: 1) }
    let text = String(decoding: data, as: UTF8.self)
    return text.split(separator: "\n").contains { line in
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        return fields.count == 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
    }
}

guard let command = arguments.first else { output(["error": "Expected inspect, enable, or disable."], code: 1) }
switch command {
case "inspect":
    output(["apps": apps().map { ["pid": Int($0.processIdentifier), "path": $0.bundleURL?.path ?? ""] }])
case "disable":
    guard arguments.count == 3, arguments[2] == "--confirm-allow-sleep",
          let pid = Int32(arguments[1]) else {
        output(["error": "Disable requires a target PID and --confirm-allow-sleep."], code: 1)
    }
    // Give the MCP response time to reach the remote caller before lid sleep.
    Thread.sleep(forTimeInterval: 3)
    guard let target = apps().first(where: { $0.processIdentifier == pid }) else {
        output(["error": "The requested Taurine process is no longer running."], code: 1)
    }
    guard target.terminate() else { output(["error": "Taurine did not accept the quit request."], code: 1) }
    output(["quit_requested": true, "pid": Int(pid)])
case "enable":
    do {
        if try sleepDisabled() {
            output(["changed": false, "message": "System sleep is already disabled."])
        }
    } catch { output(["error": "Could not read sleep settings; no action was taken."], code: 1) }
    for app in apps() {
        if app.bundleURL?.standardizedFileURL == automationApp.standardizedFileURL {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.christianfurr.Taurine.enable"), object: nil,
                userInfo: nil, deliverImmediately: true)
            output(["enable_requested": true, "administrator_approval_may_be_required": true])
        }
        // Only replace an idle legacy instance. Never restart an awake session.
        do {
            if try sleepDisabled() { output(["changed": false, "message": "System sleep is already disabled."]) }
        } catch { output(["error": "Could not verify that the legacy app is idle."], code: 1) }
        guard app.terminate() else { output(["error": "The idle legacy Taurine app could not close."], code: 1) }
        let deadline = Date().addingTimeInterval(5)
        while !app.isTerminated && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard app.isTerminated else { output(["error": "The legacy app is still running; it was not force-quit."], code: 1) }
    }
    guard FileManager.default.fileExists(atPath: automationApp.path) else {
        output(["error": "The automation-ready Taurine app is not installed."], code: 1)
    }
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = ["--enable"]
    config.activates = false
    var completed = false
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: automationApp, configuration: config) { _, error in
        launchError = error; completed = true
    }
    let deadline = Date().addingTimeInterval(8)
    while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard completed, launchError == nil else { output(["error": "The Taurine launch request could not be confirmed."], code: 1) }
    output(["enable_requested": true, "administrator_approval_may_be_required": true])
default:
    output(["error": "Unknown command."], code: 1)
}
