import AppKit
import CryptoKit
import Foundation

struct FixtureResponse: Sendable {
    let data: Data
    let status: Int
    let delay: TimeInterval
    var stream = false
    var knownLength = true
}

final class UpdateNetworkFixtures: @unchecked Sendable {
    static let shared = UpdateNetworkFixtures()
    private let lock = NSLock()
    private var responses: [String: FixtureResponse] = [:]
    private var requests: [URL] = []

    func reset(_ responses: [String: FixtureResponse]) {
        lock.withLock { self.responses = responses; requests = [] }
    }
    func response(for url: URL) -> FixtureResponse {
        lock.withLock {
            requests.append(url)
            return responses[url.path] ?? FixtureResponse(data: Data(), status: 404, delay: 0)
        }
    }
    var paths: [String] { lock.withLock { requests.map(\.path) } }
}

final class UpdateFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private let stateLock = NSLock()
    private var stopped = false
    override func startLoading() {
        let url = request.url!
        let fixture = UpdateNetworkFixtures.shared.response(for: url)
        DispatchQueue.global().asyncAfter(deadline: .now() + fixture.delay) { [self] in
            guard !stateLock.withLock({ stopped }) else { return }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: nil, headerFields: fixture.knownLength ? ["Content-Length": "\(fixture.data.count)"] : nil)!, cacheStoragePolicy: .notAllowed)
            if fixture.stream {
                let middle = fixture.data.count / 2
                client?.urlProtocol(self, didLoad: fixture.data.prefix(middle))
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [self] in
                    guard !stateLock.withLock({ stopped }) else { return }
                    client?.urlProtocol(self, didLoad: fixture.data.suffix(fixture.data.count - middle))
                    client?.urlProtocolDidFinishLoading(self)
                }
            } else {
                client?.urlProtocol(self, didLoad: fixture.data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() { stateLock.withLock { stopped = true } }
}

let updateFixtureSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [UpdateFixtureProtocol.self]
    return URLSession(configuration: config)
}()

@MainActor
enum UpdateFixtureUI {
    static var progressStages: [String] = []
    static var transferAmounts: [(Int64, Int64)] = []
    static var cancelAction: (() -> Void)?
    static var retryAction: (() -> Void)?
    static var messages: [String] = []
    static var notices: [String] = []
    static var openedPackages: [URL] = []
    static var terminationCount = 0
    static var acceptUpdate = false
    static var openSucceeds = true
    static var checksInFlight = 0
    static var downloadsInFlight = 0

    static func reset(accept: Bool = false, openSucceeds: Bool = true) {
        UserDefaults.standard.removeObject(forKey: "ifancontrol.update.pending_build")
        progressStages = []; transferAmounts = []; cancelAction = nil; retryAction = nil
        messages = []; notices = []; openedPackages = []; terminationCount = 0
        acceptUpdate = accept; self.openSucceeds = openSucceeds
    }
    @discardableResult
    static func open(_ url: URL) -> Bool { openedPackages.append(url); return openSucceeds }
    static func terminate() { terminationCount += 1 }
}

@MainActor
final class UpdateFixtureAlert: NSAlert {
    @discardableResult
    override func runModal() -> NSApplication.ModalResponse {
        UpdateFixtureUI.messages.append(messageText)
        return UpdateFixtureUI.acceptUpdate && buttons.first?.title == "立即更新"
            ? .alertFirstButtonReturn : .alertSecondButtonReturn
    }
}

@MainActor
final class InteractionNotice {
    static let shared = InteractionNotice()
    func show(_ message: String) { UpdateFixtureUI.notices.append(message) }
}

@MainActor
final class UpdateProgressWindowController {
    func present(title: String, detail: String, cancel: (() -> Void)? = nil, retry: (() -> Void)? = nil, manual: (() -> Void)? = nil) {
        UpdateFixtureUI.progressStages.append(title)
        UpdateFixtureUI.cancelAction = cancel
        UpdateFixtureUI.retryAction = retry
        if title.contains("失败") || title.contains("未完成") { UpdateFixtureUI.messages.append(title) }
    }
    func updateTransfer(received: Int64, total: Int64) { UpdateFixtureUI.transferAmounts.append((received, total)) }
    func bringForward() {}
    func dismiss() {}
}

@main
struct UpdateServiceTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let domain = Bundle.main.bundleIdentifier!
        precondition(domain.hasPrefix("com.ifancontrol.update-service-test."))
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer {
            for url in UpdateFixtureUI.openedPackages {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        let service = UpdateService.shared
        let preferences = UpdatePreferences.shared
        let payload = Data("installer verification fixture".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        func feed(_ build: Int, channel: String? = nil) throws -> Data {
            var json: [String: Any] = ["latest_version": "2.9.10", "latest_build": build,
                "assets": ["macos_arm64_pkg_url": "https://ifan-59w.pages.dev/fixture.pkg?build=\(build)", "pkg_sha256": digest]]
            json["release_channel"] = channel
            return try JSONSerialization.data(withJSONObject: json)
        }
        func setup(_ data: Data, package: Data? = nil, status: Int = 200, delay: TimeInterval = 0.01) {
            UpdateNetworkFixtures.shared.reset([
                "/update-manifest-pkg.json": FixtureResponse(data: data, status: 200, delay: delay),
                "/update-manifest-beta.json": FixtureResponse(data: data, status: 200, delay: delay),
                "/fixture.pkg": FixtureResponse(data: package ?? payload, status: status, delay: delay)
            ])
        }
        func finishCheck() async throws {
            let deadline = Date().addingTimeInterval(5)
            while UpdateFixtureUI.checksInFlight > 0 || UpdateFixtureUI.downloadsInFlight > 0 {
                precondition(Date() < deadline, "Updater fixture timed out")
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        service.automaticChecksEnabled = false
        setup(try feed(62))
        service.checkForUpdates(triggeredByUser: false)
        try await finishCheck()
        precondition(UpdateNetworkFixtures.shared.paths.isEmpty)
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateNetworkFixtures.shared.paths == ["/update-manifest-pkg.json"])
        precondition(UpdateFixtureUI.messages == ["已是最新版本"])
        precondition(service.currentVersionDisplay == "2.9.10 (62)")

        preferences.unlockDeveloperMode()
        UpdateFixtureUI.reset()
        setup(try feed(999))
        service.automaticChecksEnabled = true
        service.checkForUpdates(triggeredByUser: false)
        try await finishCheck()
        precondition(UpdateNetworkFixtures.shared.paths == ["/update-manifest-pkg.json"])
        precondition(UpdateFixtureUI.messages == ["发现新版本 2.9.10"])
        precondition(UpdateFixtureUI.openedPackages.isEmpty, "Later must not download or install")

        preferences.setBetaEnabled(true)
        UpdateFixtureUI.reset(accept: true)
        setup(try feed(999, channel: "beta"), package: Data("corrupt".utf8))
        service.checkForUpdates(triggeredByUser: false)
        try await finishCheck()
        precondition(UpdateNetworkFixtures.shared.paths == ["/update-manifest-beta.json", "/fixture.pkg"])
        precondition(UpdateFixtureUI.messages == ["发现新版本 2.9.10 Beta", "更新未完成"])
        precondition(UpdateFixtureUI.openedPackages.isEmpty && UpdateFixtureUI.terminationCount == 0)

        UpdateFixtureUI.reset(accept: true)
        setup(try feed(999, channel: "beta"))
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateFixtureUI.openedPackages.count == 1 && UpdateFixtureUI.terminationCount == 1)
        let downloadedPackage = UpdateFixtureUI.openedPackages[0]
        let downloadedBytes = try Data(contentsOf: downloadedPackage)
        precondition(downloadedBytes == payload && downloadedPackage.pathExtension == "pkg")
        try FileManager.default.removeItem(at: downloadedPackage.deletingLastPathComponent())

        // A normal stable package uses the same download, verification and termination path.
        preferences.setBetaEnabled(false)
        UpdateFixtureUI.reset(accept: true)
        setup(try feed(999))
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateNetworkFixtures.shared.paths == ["/update-manifest-pkg.json", "/fixture.pkg"])
        precondition(UpdateFixtureUI.openedPackages.count == 1 && UpdateFixtureUI.terminationCount == 1)
        try FileManager.default.removeItem(at: UpdateFixtureUI.openedPackages[0].deletingLastPathComponent())

        UpdateFixtureUI.reset(accept: true, openSucceeds: false)
        setup(try feed(999))
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateFixtureUI.messages.last == "更新未完成" && UpdateFixtureUI.terminationCount == 0)
        try FileManager.default.removeItem(at: UpdateFixtureUI.openedPackages[0].deletingLastPathComponent())

        UpdateFixtureUI.reset(accept: true)
        setup(try feed(999), status: 503)
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateFixtureUI.messages.last == "更新未完成" && UpdateFixtureUI.openedPackages.isEmpty)

        UpdateFixtureUI.reset()
        setup(try feed(999, channel: "beta"))
        service.checkForUpdates(triggeredByUser: false)
        try await finishCheck()
        precondition(UpdateFixtureUI.messages.isEmpty, "Stable must quietly reject a misplaced Beta feed during automatic checks")

        preferences.setBetaEnabled(true)
        UpdateFixtureUI.reset()
        setup(try feed(999, channel: "beta"), delay: 0.3)
        service.checkForUpdates(triggeredByUser: true)
        try await Task.sleep(for: .milliseconds(50))
        preferences.setBetaEnabled(false)
        preferences.setBetaEnabled(true)
        try await finishCheck()
        precondition(UpdateFixtureUI.messages.isEmpty, "An old result is invalid even after switching back to Beta")

        UpdateFixtureUI.reset(accept: true)
        UpdateNetworkFixtures.shared.reset([
            "/update-manifest-beta.json": FixtureResponse(data: try feed(999, channel: "beta"), status: 200, delay: 0.01),
            "/fixture.pkg": FixtureResponse(data: payload, status: 200, delay: 0.3)
        ])
        service.checkForUpdates(triggeredByUser: true)
        let downloadDeadline = Date().addingTimeInterval(5)
        while UpdateNetworkFixtures.shared.paths.count < 2 {
            precondition(Date() < downloadDeadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        preferences.setBetaEnabled(false)
        try await finishCheck()
        precondition(UpdateFixtureUI.openedPackages.isEmpty && UpdateFixtureUI.terminationCount == 0,
                     "Switching routes during a download must prevent installation of the old result")

        UpdateFixtureUI.reset()
        setup(Data("unavailable".utf8))
        service.checkForUpdates(triggeredByUser: false)
        try await finishCheck()
        precondition(UpdateFixtureUI.messages.isEmpty)
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateFixtureUI.messages == ["检查更新失败"])
        UpdateFixtureUI.reset(accept: true)
        setup(try feed(999), delay: 0.3)
        service.checkForUpdates(triggeredByUser: true)
        try await Task.sleep(for: .milliseconds(40))
        UpdateFixtureUI.cancelAction?()
        try await finishCheck()
        precondition(UpdateFixtureUI.messages.isEmpty && UpdateFixtureUI.openedPackages.isEmpty)

        UpdateFixtureUI.reset(accept: true)
        UpdateNetworkFixtures.shared.reset([
            "/update-manifest-pkg.json": FixtureResponse(data: try feed(999), status: 200, delay: 0.01),
            "/fixture.pkg": FixtureResponse(data: payload, status: 200, delay: 0.3)
        ])
        service.checkForUpdates(triggeredByUser: true)
        while UpdateNetworkFixtures.shared.paths.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        UpdateFixtureUI.cancelAction?()
        try await finishCheck()
        precondition(UpdateFixtureUI.openedPackages.isEmpty && UpdateFixtureUI.terminationCount == 0)
        precondition(!UpdateFixtureUI.progressStages.contains("正在验证安装包"))

        UpdateFixtureUI.reset(accept: true)
        UpdateNetworkFixtures.shared.reset([
            "/update-manifest-pkg.json": FixtureResponse(data: try feed(999), status: 200, delay: 0.01),
            "/fixture.pkg": FixtureResponse(data: payload, status: 200, delay: 0.01, stream: true)
        ])
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateFixtureUI.progressStages == ["正在检查更新", "正在下载安装包", "正在验证安装包", "即将打开系统安装器"])
        precondition(!UpdateFixtureUI.transferAmounts.isEmpty, "Known-size transfer must report actual received bytes")
        precondition(UpdateFixtureUI.transferAmounts.allSatisfy { $0.0 <= $0.1 && $0.1 == payload.count })
        precondition(UserDefaults.standard.integer(forKey: "ifancontrol.update.pending_build") == 999)
        service.presentInstalledUpdateIfNeeded()
        precondition(UserDefaults.standard.integer(forKey: "ifancontrol.update.pending_build") == 999, "Opening Installer is not successful installation")
        precondition(UpdateFixtureUI.notices.isEmpty)
        UserDefaults.standard.set(62, forKey: "ifancontrol.update.pending_build")
        service.presentInstalledUpdateIfNeeded()
        precondition(UpdateFixtureUI.notices == ["已更新至 2.9.10 (62)"])
        precondition(UserDefaults.standard.object(forKey: "ifancontrol.update.pending_build") == nil)
        try FileManager.default.removeItem(at: UpdateFixtureUI.openedPackages[0].deletingLastPathComponent())

        UpdateFixtureUI.reset(accept: true)
        UpdateNetworkFixtures.shared.reset([
            "/update-manifest-pkg.json": FixtureResponse(data: try feed(999), status: 200, delay: 0.01),
            "/fixture.pkg": FixtureResponse(data: payload, status: 200, delay: 0.01, stream: true, knownLength: false)
        ])
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(!UpdateFixtureUI.transferAmounts.isEmpty && UpdateFixtureUI.transferAmounts.allSatisfy { $0.1 <= 0 }, "Unknown-size transfer must not invent a total")
        try FileManager.default.removeItem(at: UpdateFixtureUI.openedPackages[0].deletingLastPathComponent())

        UpdateFixtureUI.reset(accept: true)
        setup(try feed(999), status: 503)
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateFixtureUI.retryAction != nil)
        setup(try feed(999))
        UpdateFixtureUI.retryAction?()
        try await finishCheck()
        precondition(UpdateFixtureUI.terminationCount == 1 && UpdateFixtureUI.openedPackages.count == 1)
        try FileManager.default.removeItem(at: UpdateFixtureUI.openedPackages[0].deletingLastPathComponent())

        UpdateFixtureUI.reset()
        setup(try feed(62), delay: 0.2)
        service.checkForUpdates(triggeredByUser: false)
        service.checkForUpdates(triggeredByUser: true)
        try await finishCheck()
        precondition(UpdateNetworkFixtures.shared.paths.count == 1 && UpdateFixtureUI.messages == ["已是最新版本"], "Manual check during an automatic check must surface its result")

        print("PASS: real updater routing, live byte progress/unknown totals, cancellation, retry, SHA256/HTTP/open failures, receipt truthfulness and stale-result handling (external effects stubbed)")
    }
}
