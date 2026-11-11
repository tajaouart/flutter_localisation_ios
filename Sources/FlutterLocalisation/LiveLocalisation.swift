import Foundation
#if canImport(Combine)
import Combine
#endif

/// Live translation updates from flutterlocalisation.com for an app that
/// ships an Xcode String Catalog.
///
/// ```swift
/// let live = LiveLocalisation(secretKey: "sk_live_...", projectId: 42, flavor: "Default")
/// live.start()
/// ```
///
/// After `start()` every `String(localized:)`, `NSLocalizedString` and
/// SwiftUI `Text` lookup on the bundle (`Bundle.main` by default) returns the
/// live string when an update carries one, formatted by Foundation from the
/// same `.strings` / `.stringsdict` shape Xcode builds, so plurals, positional
/// arguments and device variations behave exactly like the bundled copy.
@MainActor
public final class LiveLocalisation: ObservableObject {
    /// Posted on the main queue after an update has been applied.
    public static let didUpdateNotification = Notification.Name("FlutterLocalisationDidUpdate")

    nonisolated public static let defaultEndpoint = URL(string: "https://api.flutterlocalisation.com/api/v1/translations/live-update/")!

    public let projectId: Int
    public let flavor: String

    /// Bumped whenever the live strings change; `.liveLocalisation(_:)` keys the
    /// view tree on it so every `Text` looks its string up again.
    @Published public private(set) var revision: Int
    @Published public private(set) var lastModified: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?

    private let secretKey: String?
    private let endpoint: URL
    private let session: URLSession
    private let bundle: Bundle
    private let resolver: LiveResolver
    private let logging: Bool

    /// - Parameters:
    ///   - secretKey: the live update key from the dashboard. With nil the
    ///     bundled strings are used and nothing is fetched.
    ///   - bundledAt: when the catalog in the app was exported. Live strings
    ///     older than that are dropped, the same rule the Flutter package
    ///     applies with the ARB `@@last_modified`.
    ///   - bundle: the bundle whose lookups are answered, `Bundle.main` for an app.
    ///   - storage: where live strings are kept, Application Support by default.
    public init(
        secretKey: String?,
        projectId: Int,
        flavor: String,
        bundledAt: Date? = nil,
        bundle: Bundle = .main,
        storage: URL? = nil,
        endpoint: URL = LiveLocalisation.defaultEndpoint,
        session: URLSession = .shared,
        logging: Bool = false
    ) {
        self.secretKey = secretKey?.isEmpty == true ? nil : secretKey
        self.projectId = projectId
        self.flavor = flavor
        self.endpoint = endpoint
        self.session = session
        self.bundle = bundle
        self.logging = logging
        let root = storage ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FlutterLocalisation", isDirectory: true)
        let folder = root.appendingPathComponent("\(projectId)-\(LiveLocalisation.safe(flavor))", isDirectory: true)
        let store = LiveStore(directory: folder)
        if let bundledAt, let cached = store.lastModified.flatMap(LiveLocalisation.date), cached < bundledAt {
            store.clear()
        }
        self.resolver = LiveResolver(store: store, bundle: bundle)
        self.revision = store.revision
        self.lastModified = store.lastModified ?? bundledAt.map(LiveLocalisation.timestamp)
        LiveBundle.install(resolver, on: bundle)
    }

    public var isConfigured: Bool { secretKey != nil }

    /// Locales that currently have live strings.
    public var liveLocales: [String] { resolver.store.locales }

    /// The locales the app's own lookups go through, most specific first.
    public var lookupChain: [String] { resolver.chain() }

    /// Whether the app currently shows the live copy of `key`.
    public func isLive(_ key: String) -> Bool { resolver.isLive(key) }

    /// Keys with a live string in `locale`.
    public func liveKeys(in locale: String) -> Set<String> { resolver.store.keys(for: locale) }

    /// Fetches in the background; call once at launch.
    public func start() {
        Task { try? await refresh() }
    }

    /// Fetches the latest update. Returns whether anything changed.
    @discardableResult
    public func refresh() async throws -> Bool {
        guard let secretKey else { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let changed = try await fetch(secretKey: secretKey)
            lastError = nil
            return changed
        } catch {
            lastError = error.localizedDescription
            log("update failed: \(error)")
            throw error
        }
    }

    /// Drops every live string; the bundled ones show again.
    public func reset() {
        resolver.store.clear()
        lastModified = nil
        revision += 1
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
    }

    // MARK: - Network

    public enum UpdateError: LocalizedError {
        case http(Int, String?)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .http(let code, let message): return message.map { "HTTP \(code): \($0)" } ?? "HTTP \(code)"
            case .invalidResponse: return "The server answered something that is not an update."
            }
        }
    }

    private func fetch(secretKey: String) async throws -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["project_id": projectId, "flavor": flavor, "format": "xcstrings"]
        if let lastModified { body["current_timestamp"] = lastModified }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.http(http.statusCode, json?["error"] as? String)
        }
        guard let json, let hasUpdates = json["has_updates"] as? Bool else { throw UpdateError.invalidResponse }
        guard hasUpdates else {
            log("no new update")
            return false
        }
        guard let catalog = json["catalog"] as? [String: Any],
              let modified = json["last_modified"] as? String else { throw UpdateError.invalidResponse }
        let store = resolver.store
        let locales = try await Task.detached { try store.apply(catalog: catalog, lastModified: modified) }.value
        log("applied update \(modified) for \(locales.sorted().joined(separator: ", "))")
        lastModified = modified
        revision = store.revision
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
        return true
    }

    private func log(_ message: String) {
        if logging { print("[FlutterLocalisation] \(message)") }
    }

    // MARK: - Helpers

    nonisolated private static func safe(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    nonisolated static func date(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        // The dashboard's own ARB stamp has no zone: 2025-06-22T10:04:05.496424
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }

    nonisolated static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Rebuilds the view tree when a live update lands, so every `Text`
    /// resolves its string again.
    func liveLocalisation(_ live: LiveLocalisation) -> some View {
        modifier(LiveLocalisationModifier(live: live))
    }
}

private struct LiveLocalisationModifier: ViewModifier {
    @ObservedObject var live: LiveLocalisation

    func body(content: Content) -> some View {
        content
            .id(live.revision)
            .environmentObject(live)
    }
}
#endif
