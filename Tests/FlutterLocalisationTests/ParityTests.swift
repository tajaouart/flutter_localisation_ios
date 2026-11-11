import Foundation
import XCTest
@testable import FlutterLocalisation

/// A live string must render exactly like the same string built into the app
/// by Xcode, for every key, locale and argument value.
final class ParityTests: XCTestCase {
    private let counts: [Int] = [0, 1, 2, 3, 4, 5, 11, 21, 22, 100, 101, 1_000_000]
    private let decimals: [Double] = [0, 1, 1.5, 2, 3.25, 11, 1_000_000]

    func testExampleCatalog() throws { try assertParity("Example") }

    func testEdgeCases() throws { try assertParity("EdgeCases") }

    private func assertParity(_ fixture: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let xcode = try xcodeBuiltBundle(fixture)
        let store = LiveStore(directory: temporaryDirectory(), device: Catalog.currentDevice)
        try store.apply(catalog: Fixture.catalog(fixture), lastModified: "2026-11-11T10:00:00Z")
        var compared = 0
        for locale in store.locales {
            let built = try singleLocaleBundle(from: xcode, locale: locale)
            let live = try XCTUnwrap(store.bundle(for: locale))
            for key in store.keys(for: locale).sorted() {
                let expectedFormat = built.localizedString(forKey: key, value: "∅", table: "Localizable")
                let liveFormat = live.localizedString(forKey: key, value: "∅", table: "Localizable")
                XCTAssertNotEqual(liveFormat, "∅", "\(locale) \(key) missing live", file: file, line: line)
                for arguments in argumentSets(for: key) {
                    let expected = String(format: expectedFormat, locale: Locale(identifier: locale), arguments: arguments)
                    let actual = String(format: liveFormat, locale: Locale(identifier: locale), arguments: arguments)
                    XCTAssertEqual(actual, expected, "\(locale) \(key) \(arguments)", file: file, line: line)
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(compared, 50, file: file, line: line)
    }

    private func argumentSets(for key: String) -> [[CVarArg]] {
        let specifiers = FormatSpecifier.parse(key).sorted { $0.position < $1.position }
        guard !specifiers.isEmpty else { return [[]] }
        var sets: [[CVarArg]] = [[]]
        for specifier in specifiers {
            let values: [CVarArg]
            switch specifier.conversion {
            case "@": values = ["Ana" as NSString]
            case "f", "F", "e", "g": values = decimals
            default: values = counts.map { Int64($0) }
            }
            sets = sets.flatMap { set in values.map { set + [$0] } }
        }
        return sets
    }
}
