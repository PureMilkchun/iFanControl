import Foundation

enum UpdateChannel: String {
    case stable
    case beta

    var manifestURL: URL {
        switch self {
        case .stable: return UpdateManifest.channelURL
        case .beta: return URL(string: "https://ifan-59w.pages.dev/update-manifest-beta.json")!
        }
    }
}

struct UpdateSelection: Equatable {
    let channel: UpdateChannel
    let revision: UInt
}

/// Preferences are separate from fan configuration and default to the existing stable route.
@MainActor
final class UpdatePreferences {
    static let channelDidChange = Notification.Name("iFanControlUpdateChannelDidChange")
    static let shared = UpdatePreferences(defaults: .standard)
    private let defaults: UserDefaults
    private let developerModeKey = "ifancontrol.update.developer_mode_enabled"
    private let betaEnabledKey = "ifancontrol.update.beta_enabled"
    private var revision: UInt = 0

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var developerModeEnabled: Bool { defaults.bool(forKey: developerModeKey) }
    var betaEnabled: Bool { developerModeEnabled && defaults.bool(forKey: betaEnabledKey) }
    var channel: UpdateChannel { betaEnabled ? .beta : .stable }
    var selection: UpdateSelection { UpdateSelection(channel: channel, revision: revision) }

    func unlockDeveloperMode() {
        guard !developerModeEnabled else { return }
        // Unlocking reveals the controls; it never subscribes to Beta by itself.
        defaults.set(false, forKey: betaEnabledKey)
        defaults.set(true, forKey: developerModeKey)
    }

    func setBetaEnabled(_ enabled: Bool) {
        let oldChannel = channel
        defaults.set(enabled && developerModeEnabled, forKey: betaEnabledKey)
        if channel != oldChannel {
            revision &+= 1
            NotificationCenter.default.post(name: Self.channelDidChange, object: nil)
        }
    }

    func exitDeveloperMode() {
        setBetaEnabled(false)
        defaults.set(false, forKey: developerModeKey)
    }
}

/// One counter per help window; ordinary individual clicks count, with no timing requirement.
struct DeveloperModeUnlockCounter {
    private(set) var clickCount = 0

    mutating func registerClick() -> Bool {
        clickCount += 1
        guard clickCount == 10 else { return false }
        reset()
        return true
    }

    mutating func reset() { clickCount = 0 }
}
