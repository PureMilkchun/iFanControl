import Foundation

@main
struct UpdateChannelTests {
    @MainActor
    static func main() throws {
        let suite = "com.ifancontrol.update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UpdatePreferences(defaults: defaults)
        precondition(!preferences.developerModeEnabled && !preferences.betaEnabled)
        precondition(preferences.channel == .stable)
        precondition(preferences.channel.manifestURL == UpdateManifest.channelURL)
        precondition(UpdateChannel.beta.manifestURL.path == "/update-manifest-beta.json")

        preferences.setBetaEnabled(true)
        precondition(preferences.channel == .stable, "Hidden mode must not enable Beta")
        var counter = DeveloperModeUnlockCounter()
        for _ in 1...9 { precondition(!counter.registerClick()) }
        counter.reset() // A closed help window must discard the first nine clicks.
        precondition(!counter.registerClick())
        for _ in 2...9 { precondition(!counter.registerClick()) }
        precondition(counter.registerClick(), "The tenth click must unlock")
        preferences.unlockDeveloperMode()
        precondition(preferences.developerModeEnabled && preferences.channel == .stable)

        let originalStableRequest = preferences.selection
        preferences.setBetaEnabled(true)
        let betaRequest = preferences.selection
        precondition(betaRequest.channel == .beta && betaRequest != originalStableRequest)
        let restarted = UpdatePreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(restarted.developerModeEnabled && restarted.betaEnabled, "Restart must preserve both preferences")
        preferences.setBetaEnabled(false)
        precondition(preferences.channel == .stable && preferences.selection != originalStableRequest)
        preferences.setBetaEnabled(true)
        precondition(preferences.selection != betaRequest, "Switching away and back must invalidate the old request")
        let currentRequest = preferences.selection
        preferences.setBetaEnabled(true)
        precondition(preferences.selection == currentRequest, "Unchanged selection must not invalidate work")
        preferences.exitDeveloperMode()
        precondition(!preferences.developerModeEnabled && preferences.channel == .stable)
        preferences.unlockDeveloperMode()
        precondition(!preferences.betaEnabled, "Unlocking again must not restore a previous Beta subscription")

        func manifest(channel: String? = nil, releaseURL: String? = nil) throws -> UpdateManifest {
            var json: [String: Any] = ["latest_version": "3.0.0", "latest_build": 63]
            json["release_channel"] = channel
            json["release_url"] = releaseURL
            return try JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let legacySchema = try manifest()
        precondition(legacySchema.isCompatible(with: .stable) && legacySchema.versionDisplay == "3.0.0")
        let stable = try manifest(channel: "stable")
        precondition(stable.isCompatible(with: .stable) && stable.isCompatible(with: .beta))
        let beta = try manifest(channel: "beta", releaseURL: "https://github.com/PureMilkchun/iFanControl/releases/tag/v3.0.0-beta.1")
        precondition(!beta.isCompatible(with: .stable) && beta.isCompatible(with: .beta))
        precondition(beta.versionDisplay == "3.0.0 Beta" && beta.betaReleaseURL != nil)
        let unknownChannel = try manifest(channel: "unknown")
        precondition(!unknownChannel.isCompatible(with: .beta))
        for badURL in ["http://github.com/PureMilkchun/iFanControl/releases/tag/v3.0.0-beta.1",
                       "https://example.com/release", "https://github.com/other/project/releases/tag/test"] {
            let invalidLink = try manifest(channel: "beta", releaseURL: badURL)
            precondition(invalidLink.betaReleaseURL == nil)
        }
        print("PASS: stable default, ten clicks/reset, explicit Beta opt-in, persistence/exit, stale requests and feed isolation")
    }
}
