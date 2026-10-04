import Foundation
import CryptoKit

@main
struct UpdateManifestTests {
    static func main() throws {
        let payload = Data("verified installer fixture".utf8)
        let checksum = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        func decode(_ assets: [String: String]) throws -> UpdateManifest {
            let json: [String: Any] = ["latest_version": "3.0.0", "latest_build": 53, "assets": assets]
            return try JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let url = "https://ifan-59w.pages.dev/iFanControl-macOS.pkg?build=53"
        let valid = try decode(["macos_arm64_pkg_url": url, "pkg_sha256": checksum.uppercased(),
                                "macos_arm64_zip_url": "https://example.com/old.zip", "sha256": checksum])
        let selectedURL = try valid.packageDownloadURL()
        precondition(selectedURL.absoluteString == url)
        try valid.verifyPackage(payload)
        do {
            try valid.verifyPackage(Data("corrupt installer".utf8))
            fatalError("Corrupt package accepted")
        } catch UpdateManifest.PackageError.checksumMismatch {}

        for assets in [
            ["macos_arm64_zip_url": "https://example.com/old.zip", "sha256": checksum],
            ["macos_arm64_pkg_url": url],
            ["macos_arm64_pkg_url": url, "pkg_sha256": "invalid"],
            ["macos_arm64_pkg_url": "http://example.com/update.pkg", "pkg_sha256": checksum],
            ["macos_arm64_pkg_url": "https://example.com/update.zip", "pkg_sha256": checksum]
        ] {
            do {
                _ = try decode(assets).packageDownloadURL()
                fatalError("Invalid package metadata accepted: \(assets)")
            } catch UpdateManifest.PackageError.invalidMetadata {}
        }
        precondition(UpdateManifest.channelURL.path == "/update-manifest-pkg.json")
        print("PASS: native channel, PKG selection, SHA256, corruption and missing metadata; no ZIP fallback")
    }
}
