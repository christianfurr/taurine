import Foundation

struct AppVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let plain = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]),
              let patch = parts.count == 3 ? Int(parts[2]) : 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

enum UpdateError: LocalizedError {
    case invalidRelease
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRelease:
            return "GitHub returned release information Taurine could not verify. Try again later."
        case .http(403), .http(429):
            return "GitHub is limiting update checks. Try again later."
        case .http(let status):
            return "GitHub returned HTTP \(status). Try again later."
        }
    }
}

struct ReleaseUpdate {
    let version: AppVersion
    let versionLabel: String
    let releaseURL: URL
    let downloadURL: URL?

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static func verifiedURL(_ value: String, path: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.path == path else { return nil }
        return url
    }

    init(data: Data, architecture: String = Self.architecture) throws {
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, let version = AppVersion(release.tag_name),
              let releaseURL = Self.verifiedURL(release.html_url,
                path: "/christianfurr/taurine/releases/tag/\(release.tag_name)") else {
            throw UpdateError.invalidRelease
        }
        self.version = version
        self.versionLabel = "\(version.major).\(version.minor).\(version.patch)"
        self.releaseURL = releaseURL
        let assetName = "Taurine-macOS-\(architecture).zip"
        if let asset = release.assets.first(where: { $0.name == assetName }) {
            guard let download = Self.verifiedURL(asset.browser_download_url,
                path: "/christianfurr/taurine/releases/download/\(release.tag_name)/\(assetName)") else {
                throw UpdateError.invalidRelease
            }
            downloadURL = download
        } else {
            downloadURL = nil
        }
    }

    static func latest() async throws -> ReleaseUpdate {
        let url = URL(string: "https://api.github.com/repos/christianfurr/taurine/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Taurine", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidRelease }
        guard response.statusCode == 200 else { throw UpdateError.http(response.statusCode) }
        return try ReleaseUpdate(data: data)
    }
}
