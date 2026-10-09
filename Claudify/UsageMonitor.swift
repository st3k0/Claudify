//
//  UsageMonitor.swift
//  Claudify
//
//  Fetches real Claude subscription usage (the same numbers as `/usage` in
//  Claude Code) from Anthropic's OAuth usage endpoint, reusing the OAuth token
//  that Claude Code stores in the login Keychain.
//

import Foundation
import Observation
import Security

/// One usage window (5-hour session or 7-day) as reported by the API.
struct UsageWindow: Sendable {
    var percent: Double
    var resetsAt: Date?
}

@Observable
@MainActor
final class UsageMonitor {

    // MARK: Published state

    private(set) var session: UsageWindow?   // five_hour
    private(set) var weekly: UsageWindow?    // seven_day
    private(set) var errorText: String?
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var plan: String?           // e.g. "Pro", "Max 20x"
    private(set) var claudeVersion: String?  // installed Claude Code version
    var hasData: Bool { session != nil || weekly != nil }

    private var timer: Timer?

    // MARK: Lifecycle

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Refresh

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            if let creds = try? CredentialStore.load() {
                self.plan = Self.planName(subscription: creds.subscriptionType, tier: creds.rateLimitTier)
            }
            self.claudeVersion = await Self.detectClaudeVersion()
            do {
                let usage = try await Self.fetchUsage()
                self.session = usage.five_hour?.window
                self.weekly = usage.seven_day?.window
                self.errorText = nil
            } catch let error as UsageError {
                self.errorText = error.message
            } catch {
                self.errorText = "Couldn't load usage."
            }
            self.lastRefresh = Date()
            self.isRefreshing = false
        }
    }

    // MARK: API models

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
            var window: UsageWindow {
                UsageWindow(percent: utilization ?? 0, resetsAt: resets_at.flatMap(parseDate))
            }
        }
        let five_hour: Window?
        let seven_day: Window?
    }

    enum UsageError: Error {
        case noCredentials
        case refreshFailed
        case badResponse(Int)

        var message: String {
            switch self {
            case .noCredentials: return "Log in with Claude Code first."
            case .refreshFailed:  return "Session expired — run Claude Code to re-auth."
            case .badResponse:    return "Anthropic API returned an error."
            }
        }
    }

    // MARK: Networking (off the main actor)

    private nonisolated static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private nonisolated static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private nonisolated static let tokenURL = URL(string: "https://api.anthropic.com/v1/oauth/token")!

    private nonisolated static func fetchUsage() async throws -> UsageResponse {
        var creds = try CredentialStore.load()

        // Refresh proactively if the access token is expired or about to expire.
        if creds.isExpiring {
            creds = try await refreshToken(creds)
        }

        do {
            return try await requestUsage(token: creds.accessToken)
        } catch UsageError.badResponse(401) {
            // Token rejected — refresh once and retry.
            let refreshed = try await refreshToken(creds)
            return try await requestUsage(token: refreshed.accessToken)
        }
    }

    private nonisolated static func requestUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UsageError.badResponse(code) }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    /// Exchanges the refresh token for a new access token and persists the
    /// rotated credentials so Claude Code stays in sync.
    private nonisolated static func refreshToken(_ creds: Credentials) async throws -> Credentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": clientID,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            throw UsageError.refreshFailed
        }
        let refresh = json["refresh_token"] as? String ?? creds.refreshToken
        let expiresIn = json["expires_in"] as? Double ?? 0

        var updated = creds
        updated.accessToken = access
        updated.refreshToken = refresh
        updated.expiresAtMs = Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000
        try CredentialStore.save(updated)
        return updated
    }

    // MARK: Plan & version

    /// Turns the raw `subscriptionType` / `rateLimitTier` values into a display
    /// name, e.g. ("max", "default_claude_max_20x") → "Max 20x".
    private nonisolated static func planName(subscription: String?, tier: String?) -> String? {
        guard let subscription, !subscription.isEmpty else { return nil }
        var name = subscription.prefix(1).uppercased() + subscription.dropFirst()
        if let tier, let match = tier.firstMatch(of: /(\d+)x$/) {
            name += " \(match.1)x"
        }
        return name
    }

    /// Finds the installed Claude Code version without launching it. Native
    /// installs symlink `claude` to `.../versions/<version>`; npm installs keep
    /// a `package.json` next to the resolved binary. Falls back to the last
    /// version recorded in `~/.claude.json`.
    private nonisolated static func detectClaudeVersion() async -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        let isVersion = { (s: String) in s.wholeMatch(of: /\d+\.\d+\.\d+.*/) != nil }

        for link in candidates where fm.fileExists(atPath: link.path) {
            let resolved = link.resolvingSymlinksInPath()
            if isVersion(resolved.lastPathComponent) { return resolved.lastPathComponent }
            // Walk up looking for the npm package manifest.
            var dir = resolved.deletingLastPathComponent()
            for _ in 0..<3 {
                let manifest = dir.appendingPathComponent("package.json")
                if let data = try? Data(contentsOf: manifest),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["name"] as? String == "@anthropic-ai/claude-code",
                   let version = json["version"] as? String {
                    return version
                }
                dir = dir.deletingLastPathComponent()
            }
        }

        if let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = json["lastReleaseNotesSeen"] as? String, isVersion(version) {
            return version
        }
        return nil
    }

    private nonisolated static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        let stripped = string.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        return f.date(from: stripped)
    }
}

// MARK: - Credentials

/// The OAuth credentials Claude Code stores, plus where they came from so we
/// can write rotated tokens back to the same place.
struct Credentials {
    var accessToken: String
    var refreshToken: String
    var expiresAtMs: Double
    var subscriptionType: String?   // "pro", "max", "team", …
    var rateLimitTier: String?      // e.g. "default_claude_max_20x"
    /// The full decoded credentials JSON, preserved so we don't drop fields on save.
    fileprivate var root: [String: Any]
    fileprivate var source: CredentialStore.Source

    /// True when the access token expires within the next 5 minutes.
    var isExpiring: Bool {
        Date().timeIntervalSince1970 * 1000 > expiresAtMs - 5 * 60 * 1000
    }
}

/// Reads/writes Claude Code's OAuth credentials from the login Keychain,
/// falling back to `~/.claude/.credentials.json`.
enum CredentialStore {
    enum Source {
        case keychain(account: String)
        case file(URL)
    }

    private static let service = "Claude Code-credentials"

    static func load() throws -> Credentials {
        if let (data, account) = readKeychain(), let creds = parse(data, source: .keychain(account: account)) {
            return creds
        }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: url), let creds = parse(data, source: .file(url)) {
            return creds
        }
        throw UsageMonitor.UsageError.noCredentials
    }

    static func save(_ creds: Credentials) throws {
        var root = creds.root
        var oauth = root["claudeAiOauth"] as? [String: Any] ?? [:]
        oauth["accessToken"] = creds.accessToken
        oauth["refreshToken"] = creds.refreshToken
        oauth["expiresAt"] = creds.expiresAtMs
        root["claudeAiOauth"] = oauth
        let data = try JSONSerialization.data(withJSONObject: root)

        switch creds.source {
        case .keychain(let account): writeKeychain(data, account: account)
        case .file(let url): try? data.write(to: url)
        }
    }

    // MARK: Parsing

    private static func parse(_ data: Data, source: Source) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String, !access.isEmpty,
              let refresh = oauth["refreshToken"] as? String else { return nil }
        let expires = (oauth["expiresAt"] as? Double) ?? 0
        return Credentials(accessToken: access, refreshToken: refresh,
                           expiresAtMs: expires,
                           subscriptionType: oauth["subscriptionType"] as? String,
                           rateLimitTier: oauth["rateLimitTier"] as? String,
                           root: root, source: source)
    }

    // MARK: Keychain

    private static func readKeychain() -> (Data, String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let dict = item as? [String: Any],
              let data = dict[kSecValueData as String] as? Data else { return nil }
        let account = dict[kSecAttrAccount as String] as? String ?? ""
        return (data, account)
    }

    private static func writeKeychain(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
