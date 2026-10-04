import Foundation
import CryptoKit

// This endpoint is separate from the frozen pre-2.9.9 ZIP update channel.
struct UpdateManifest: Decodable {
    static let channelURL = URL(string: "https://ifan-59w.pages.dev/update-manifest-pkg.json")!

    let latestVersion: String
    let latestBuild: Int
    let publishedAt: String?
    let notes: String?
    let mandatory: Bool?
    let assets: Assets?

    enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case latestBuild = "latest_build"
        case publishedAt = "published_at"
        case notes, mandatory, assets
    }

    struct Assets: Decodable {
        let packageURL: String?
        let packageSHA256: String?

        enum CodingKeys: String, CodingKey {
            case packageURL = "macos_arm64_pkg_url"
            case packageSHA256 = "pkg_sha256"
        }
    }

    enum PackageError: Error {
        case invalidMetadata
        case checksumMismatch
    }

    func packageDownloadURL() throws -> URL {
        guard let raw = assets?.packageURL, let url = URL(string: raw),
              url.scheme == "https", url.host != nil,
              url.pathExtension.lowercased() == "pkg",
              let checksum = assets?.packageSHA256,
              checksum.count == 64,
              checksum.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw PackageError.invalidMetadata
        }
        return url
    }

    func verifyPackage(_ data: Data) throws {
        _ = try packageDownloadURL()
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == assets?.packageSHA256?.lowercased() else {
            throw PackageError.checksumMismatch
        }
    }
}
