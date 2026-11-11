import Foundation
import XCTest
@testable import FlutterLocalisation

@MainActor
final class LiveLocalisationTests: XCTestCase {
    private var storage: URL!

    override func setUp() async throws {
        storage = temporaryDirectory()
        MockURLProtocol.requests = []
        MockURLProtocol.handler = nil
    }

    private func live(on bundle: Bundle, key: String? = "sk_live_test", bundledAt: Date? = nil) -> LiveLocalisation {
        LiveLocalisation(
            secretKey: key, projectId: 7, flavor: "Default", bundledAt: bundledAt,
            bundle: bundle, storage: storage, session: MockURLProtocol.session
        )
    }

    private func serve(_ strings: [String: Any], at modified: String = "2026-11-11T10:00:00.000000+00:00") {
        MockURLProtocol.handler = { _ in
            (200, ["has_updates": true, "last_modified": modified, "catalog": ["sourceLanguage": "en", "strings": strings], "languages": []])
        }
    }

    private static func unit(_ value: String) -> [String: Any] {
        ["stringUnit": ["state": "translated", "value": value]]
    }

    private static func plural(_ arms: [String: String]) -> [String: Any] {
        ["variations": ["plural": arms.mapValues { unit($0) }]]
    }

    func testLiveStringsReachEveryLookupApi() async throws {
        let bundle = try xcodeBuiltBundle("Example")
        let live = live(on: bundle)
        XCTAssertEqual(String(localized: "greeting.simple", bundle: bundle), "Good morning!")

        serve([
            "greeting.simple": ["localizations": ["en": Self.unit("Morning, live!")]],
            "greeting.hello %@": ["localizations": ["en": Self.unit("Hey %@, live!")]],
            "cart.items %lld": ["localizations": ["en": Self.plural(["zero": "Live: empty", "one": "Live: one", "other": "Live: %lld"])]],
        ])
        let changed = try await live.refresh()
        XCTAssertTrue(changed)

        XCTAssertEqual(NSLocalizedString("greeting.simple", bundle: bundle, comment: ""), "Morning, live!")
        XCTAssertEqual(bundle.localizedString(forKey: "greeting.simple", value: nil, table: nil), "Morning, live!")
        XCTAssertEqual(String(localized: "greeting.simple", bundle: bundle), "Morning, live!")
        let name = "Ana"
        XCTAssertEqual(String(localized: "greeting.hello \(name)", bundle: bundle), "Hey Ana, live!")
        XCTAssertEqual(String(localized: "cart.items \(0)", bundle: bundle), "Live: empty")
        XCTAssertEqual(String(localized: "cart.items \(1)", bundle: bundle), "Live: one")
        XCTAssertEqual(String(localized: "cart.items \(42)", bundle: bundle), "Live: 42")
        XCTAssertEqual(String(localized: LocalizedStringResource("greeting.simple", bundle: .atURL(bundle.bundleURL))), "Morning, live!")
        XCTAssertEqual(AttributedString(localized: "greeting.hello \(name)", bundle: bundle).characters.map(String.init).joined(), "Hey Ana, live!")
        XCTAssertEqual(String.localizedStringWithFormat(NSLocalizedString("cart.items %lld", bundle: bundle, comment: ""), 3), "Live: 3")

        // Untouched keys still come from the app.
        XCTAssertEqual(String(localized: "greeting.welcome \(name)", bundle: bundle), "Welcome back, Ana!")
        XCTAssertTrue(live.isLive("greeting.simple"))
        XCTAssertFalse(live.isLive("greeting.welcome %@"))
        XCTAssertEqual(live.revision, 1)
    }

    func testRequestAsksForACatalogSinceTheLastUpdate() async throws {
        let live = live(on: try xcodeBuiltBundle("Example"))
        serve(["greeting.simple": ["localizations": ["en": Self.unit("A")]]], at: "2026-11-11T10:00:00+00:00")
        try await live.refresh()
        MockURLProtocol.handler = { _ in (200, ["has_updates": false, "current_timestamp": "2026-11-11T10:00:00+00:00"]) }
        let changed = try await live.refresh()
        XCTAssertFalse(changed)

        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        let first = MockURLProtocol.requests[0]
        XCTAssertEqual(first["format"] as? String, "xcstrings")
        XCTAssertEqual(first["project_id"] as? Int, 7)
        XCTAssertEqual(first["flavor"] as? String, "Default")
        XCTAssertNil(first["current_timestamp"])
        XCTAssertEqual(first["authorization"] as? String, "Bearer sk_live_test")
        XCTAssertEqual(MockURLProtocol.requests[1]["current_timestamp"] as? String, "2026-11-11T10:00:00+00:00")
    }

    func testLiveStringsAreKeptAcrossLaunches() async throws {
        let bundle = try xcodeBuiltBundle("Example")
        serve(["greeting.simple": ["localizations": ["en": Self.unit("Kept")]]])
        try await live(on: bundle).refresh()

        let fresh = try xcodeBuiltBundle("Example")
        let relaunched = live(on: fresh)
        XCTAssertEqual(String(localized: "greeting.simple", bundle: fresh), "Kept")
        XCTAssertEqual(relaunched.lastModified, "2026-11-11T10:00:00.000000+00:00")
    }

    func testAppBuiltAfterTheUpdateDropsIt() async throws {
        let bundle = try xcodeBuiltBundle("Example")
        serve(["greeting.simple": ["localizations": ["en": Self.unit("Stale")]]], at: "2026-01-01T00:00:00.000000+00:00")
        try await live(on: bundle).refresh()

        let newer = try xcodeBuiltBundle("Example")
        let relaunched = live(on: newer, bundledAt: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z"))
        XCTAssertEqual(String(localized: "greeting.simple", bundle: newer), "Good morning!")
        XCTAssertEqual(relaunched.lastModified, "2026-06-01T00:00:00.000Z")
    }

    func testWithoutAKeyNothingIsFetched() async throws {
        let live = live(on: try xcodeBuiltBundle("Example"), key: nil)
        let changed = try await live.refresh()
        XCTAssertFalse(changed)
        XCTAssertFalse(live.isConfigured)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testServerErrorIsReportedAndStringsStay() async throws {
        let bundle = try xcodeBuiltBundle("Example")
        let live = live(on: bundle)
        serve(["greeting.simple": ["localizations": ["en": Self.unit("Live")]]])
        try await live.refresh()
        MockURLProtocol.handler = { _ in (401, ["error": "Invalid API key"]) }
        do {
            try await live.refresh()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(live.lastError, "HTTP 401: Invalid API key")
        }
        XCTAssertEqual(String(localized: "greeting.simple", bundle: bundle), "Live")
    }

    func testResetShowsTheBundledStringsAgain() async throws {
        let bundle = try xcodeBuiltBundle("Example")
        let live = live(on: bundle)
        serve(["greeting.simple": ["localizations": ["en": Self.unit("Live")]]])
        try await live.refresh()
        live.reset()
        XCTAssertEqual(String(localized: "greeting.simple", bundle: bundle), "Good morning!")
        XCTAssertNil(live.lastModified)
    }

    func testOtherTablesAreLeftAlone() async throws {
        let bundle = try xcodeBuiltBundle("Example")
        let live = live(on: bundle)
        serve(["greeting.simple": ["localizations": ["en": Self.unit("Live")]]])
        try await live.refresh()
        XCTAssertEqual(bundle.localizedString(forKey: "greeting.simple", value: "own", table: "InfoPlist"), "own")
    }

    /// An app running in es-MX. Its catalog holds every key, with the es text
    /// where Mexico has no wording of its own, so the dashboard sends an es
    /// edit to es-MX too. A key the app does not have at all takes the live
    /// es string instead of showing as the raw key.
    func testRegionalApp() async throws {
        let bundle = try xcodeBuiltBundle("Example", only: ["en", "es", "es-MX"])
        let live = live(on: bundle)
        func mexican(_ key: String.LocalizationValue) -> String {
            var resource = LocalizedStringResource(key, bundle: .atURL(bundle.bundleURL))
            resource.locale = Locale(identifier: "es_MX")
            return String(localized: resource)
        }
        XCTAssertEqual(mexican("greeting.simple"), "¡Buen día!")
        XCTAssertEqual(mexican("greeting.hello \("Ana")"), "¡Hola Ana!")
        // iOS does not fall back from es-MX to es on its own.
        XCTAssertEqual(mexican("brand.slogan"), "brand.slogan")

        serve([
            "greeting.hello %@": ["localizations": ["es": Self.unit("¡Hola %@, live!"), "es-MX": Self.unit("¡Hola %@, live!")]],
            "brand.slogan": ["localizations": ["es": Self.unit("Hecho en vivo")]],
        ])
        try await live.refresh()
        XCTAssertEqual(mexican("greeting.simple"), "¡Buen día!")
        XCTAssertEqual(mexican("greeting.hello \("Ana")"), "¡Hola Ana, live!")
        XCTAssertEqual(mexican("brand.slogan"), "Hecho en vivo")

        serve(["greeting.simple": ["localizations": ["es-MX": Self.unit("Buen día live")]]], at: "2026-11-12T10:00:00+00:00")
        try await live.refresh()
        XCTAssertEqual(mexican("greeting.simple"), "Buen día live")
        XCTAssertEqual(mexican("cart.items \(2)"), "2 productos")
    }

    func testFallbackChains() {
        XCTAssertEqual(LiveResolver.fallbacks(of: "es-MX"), ["es-MX", "es"])
        XCTAssertEqual(LiveResolver.fallbacks(of: "pt-BR"), ["pt-BR", "pt"])
        XCTAssertEqual(LiveResolver.fallbacks(of: "zh-Hans"), ["zh-Hans", "zh"])
        XCTAssertEqual(LiveResolver.fallbacks(of: "zh-Hant"), ["zh-Hant"])
        XCTAssertEqual(LiveResolver.fallbacks(of: "sr-Latn"), ["sr-Latn"])
        XCTAssertEqual(LiveResolver.fallbacks(of: "en"), ["en"])
    }
}
