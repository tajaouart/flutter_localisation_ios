import Foundation
import XCTest
@testable import FlutterLocalisation

final class CatalogTests: XCTestCase {
    private var store: LiveStore!
    private var edge: LiveStore!

    override func setUpWithError() throws {
        store = LiveStore(directory: temporaryDirectory(), device: "mac")
        try store.apply(catalog: Fixture.catalog("Example"), lastModified: "1")
        try store.apply(catalog: ["strings": [:]], lastModified: "2")
        edge = LiveStore(directory: temporaryDirectory(), device: "mac")
        try edge.apply(catalog: Fixture.catalog("EdgeCases"), lastModified: "1")
    }

    private func format(_ key: String, _ locale: String, _ arguments: CVarArg...) -> String {
        let source = store.bundle(for: locale)?.localizedString(forKey: key, value: "∅", table: nil)
        let template = source == nil || source == "∅"
            ? edge.bundle(for: locale)!.localizedString(forKey: key, value: "∅", table: nil)
            : source!
        return String(format: template, locale: Locale(identifier: locale), arguments: arguments)
    }

    func testArabicUsesEveryPluralForm() {
        let cases: [(Int64, String)] = [(0, "لا توجد عناصر"), (1, "عنصر واحد"), (2, "عنصران"), (3, "3 عناصر"), (11, "11 عنصرًا"), (100, "100 عنصر")]
        for (count, expected) in cases {
            XCTAssertEqual(format("cart.items %lld", "ar", count), expected)
        }
    }

    func testZeroArmAppliesInEnglish() {
        XCTAssertEqual(format("cart.items %lld", "en", Int64(0)), "No items")
        XCTAssertEqual(format("cart.items %lld", "en", Int64(1)), "1 item")
        XCTAssertEqual(format("cart.items %lld", "en", Int64(7)), "7 items")
    }

    func testPositionalPluralDrivenByTheNumber() {
        XCTAssertEqual(format("files %@ %lld", "en", "Ana", Int64(0)), "Ana has no files")
        XCTAssertEqual(format("files %@ %lld", "en", "Ana", Int64(5)), "Ana has 5 files")
        XCTAssertEqual(format("files %@ %lld", "ru", "Ане", Int64(3)), "У Ане 3 файла")
        XCTAssertEqual(format("files %@ %lld", "ru", "Ане", Int64(5)), "У Ане 5 файлов")
        XCTAssertEqual(format("count first %lld %@", "en", Int64(1), "Ana"), "1 photo by Ana")
    }

    func testSubstitutions() {
        XCTAssertEqual(format("media %lld %lld", "en", Int64(1), Int64(0)), "1 photo and no videos")
        XCTAssertEqual(format("media %lld %lld", "en", Int64(4), Int64(2)), "4 photos and 2 videos")
    }

    func testDeviceVariationPicksThisDevice() {
        XCTAssertEqual(format("tap", "en"), "Click")
        let phone = LiveStore(directory: temporaryDirectory(), device: "iphone")
        try! phone.apply(catalog: Fixture.catalog("EdgeCases"), lastModified: "1")
        XCTAssertEqual(phone.bundle(for: "en")!.localizedString(forKey: "tap", value: nil, table: nil), "Tap")
        let watch = LiveStore(directory: temporaryDirectory(), device: "applewatch")
        try! watch.apply(catalog: Fixture.catalog("EdgeCases"), lastModified: "1")
        XCTAssertEqual(watch.bundle(for: "en")!.localizedString(forKey: "tap", value: nil, table: nil), "Select")
    }

    func testFrenchDecimalPlural() {
        XCTAssertEqual(format("distance %.1f", "fr", 1.5), "1,5 kilomètre")
        XCTAssertEqual(format("distance %.1f", "en", 1.5), "1.5 miles")
    }

    func testEscapedPercent() {
        XCTAssertEqual(format("percent %lld%%", "en", Int64(40)), "40% done")
    }

    func testRegionalLocaleKeepsItsOwnWording() {
        XCTAssertEqual(format("greeting.simple", "es-MX"), "¡Buen día!")
        XCTAssertEqual(format("greeting.simple", "es"), "¡Buenos días!")
        XCTAssertEqual(format("cart.items %lld", "es-MX", Int64(3)), "3 productos")
    }

    func testLaterUpdateReplacesOnlyItsLocales() throws {
        let update: [String: Any] = ["strings": ["greeting.simple": ["localizations": ["fr": ["stringUnit": ["state": "translated", "value": "Salut !"]]]]]]
        let before = store.keys(for: "en")
        try store.apply(catalog: update, lastModified: "3")
        XCTAssertEqual(store.keys(for: "fr"), ["greeting.simple"])
        XCTAssertEqual(store.keys(for: "en"), before)
        XCTAssertEqual(format("greeting.simple", "fr"), "Salut !")
    }

    func testStoreSurvivesARestart() throws {
        let reopened = LiveStore(directory: store.directory, device: "mac")
        XCTAssertEqual(reopened.lastModified, "2")
        XCTAssertEqual(reopened.revision, store.revision)
        XCTAssertEqual(reopened.bundle(for: "ar")?.localizedString(forKey: "greeting.simple", value: nil, table: nil), "صباح الخير!")
    }

    func testOldRevisionFoldersAreRemoved() throws {
        try store.apply(catalog: Fixture.catalog("Example"), lastModified: "3")
        try store.apply(catalog: Fixture.catalog("Example"), lastModified: "4")
        let folders = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).filter { $0.hasPrefix("revision-") }
        XCTAssertEqual(folders.sorted(), ["revision-3", "revision-4"])
    }

    func testNotACatalogIsRefused() {
        XCTAssertThrowsError(try store.apply(catalog: ["translations": [:]], lastModified: "9"))
        XCTAssertEqual(store.lastModified, "2")
    }

    func testFormatSpecifierParsing() {
        let specifiers = FormatSpecifier.parse("%2$lld of %1$@ (%.1f%%)")
        XCTAssertEqual(specifiers.map(\.position), [2, 1, 1])
        XCTAssertEqual(specifiers.map(\.valueType), ["lld", "@", "f"])
        XCTAssertEqual(specifiers.map(\.isNumeric), [true, false, true])
    }
}
