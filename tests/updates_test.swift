import Foundation

@main
struct UpdateTests {
    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            let release = try await ReleaseUpdate.latest()
            print("PASS live GitHub release check: \(release.versionLabel), download available: \(release.downloadURL != nil)")
            return
        }
        assert(AppVersion("v1.2.0") == AppVersion("1.2"))
        assert(AppVersion("1.10.0")! > AppVersion("1.2.9")!)
        assert(AppVersion("2.0.0")! > AppVersion("1.99.99")!)
        for invalid in ["", "1", "1..2", "-1.2.0", "1.2.0-beta", "1.2.3.4", "1.2.999999999999999999999"] {
            assert(AppVersion(invalid) == nil)
        }
        print("PASS numeric version comparison and invalid versions")
        var fixture: [String: Any] = [
            "tag_name": "v1.2.0",
            "html_url": "https://github.com/christianfurr/taurine/releases/tag/v1.2.0",
            "draft": false, "prerelease": false,
            "assets": [["name": "Taurine-macOS-arm64.zip", "browser_download_url":
                "https://github.com/christianfurr/taurine/releases/download/v1.2.0/Taurine-macOS-arm64.zip"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        let update = try ReleaseUpdate(data: data, architecture: "arm64")
        assert(update.downloadURL != nil && update.versionLabel == "1.2.0")
        let intelUpdate = try ReleaseUpdate(data: data, architecture: "x86_64")
        assert(intelUpdate.downloadURL == nil)
        print("PASS correct architecture selection and missing architecture fallback")
        func reject(_ object: [String: Any]) throws {
            do {
                _ = try ReleaseUpdate(data: JSONSerialization.data(withJSONObject: object))
                fatalError("Invalid release was accepted")
            } catch {}
        }
        for flag in ["draft", "prerelease"] {
            var changed = fixture; changed[flag] = true
            try reject(changed)
        }
        print("PASS draft and prerelease rejection")
        for address in ["http://github.com/christianfurr/taurine/releases/tag/v1.2.0",
                        "https://evil.example/christianfurr/taurine/releases/tag/v1.2.0",
                        "https://github.com/someone/other/releases/tag/v1.2.0",
                        "https://github.com/christianfurr/taurine/releases/tag/v1.2.0?redirect=evil"] {
            var changed = fixture; changed["html_url"] = address
            try reject(changed)
        }
        print("PASS release URL origin and path validation")
        fixture["assets"] = [["name": "Taurine-macOS-arm64.zip", "browser_download_url": "https://evil.example/app.zip"]]
        try reject(fixture)
        print("PASS download URL validation")
    }
}
