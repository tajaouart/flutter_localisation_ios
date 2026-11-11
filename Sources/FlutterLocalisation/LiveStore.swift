import Foundation

/// The live strings on disk and in memory.
///
/// Each locale keeps the units of the last update that carried it, the way
/// the Flutter package keeps one override map per locale. The compiled
/// `.strings` and `.stringsdict` go to a fresh `revision-N` folder on every
/// change because `Bundle` caches a table for the life of the process.
final class LiveStore: @unchecked Sendable {
    struct State: Codable, Equatable {
        var lastModified: String?
        var revision: Int = 0
    }

    let directory: URL
    private let device: String
    private let lock = NSLock()
    private var units: [String: [String: Any]] = [:]
    private var tables: [String: CompiledTable] = [:]
    private var bundles: [String: Bundle] = [:]
    private(set) var state = State()

    init(directory: URL, device: String = Catalog.currentDevice) {
        self.directory = directory
        self.device = device
        load()
    }

    var lastModified: String? { lock.withLock { state.lastModified } }
    var revision: Int { lock.withLock { state.revision } }
    var locales: [String] { lock.withLock { tables.keys.sorted() } }

    func keys(for locale: String) -> Set<String> {
        lock.withLock { tables[locale]?.keys ?? [] }
    }

    func contains(_ key: String, locale: String) -> Bool {
        lock.withLock { tables[locale]?.keys.contains(key) ?? false }
    }

    /// The bundle holding `locale`'s live tables, nil when it has none.
    func bundle(for locale: String) -> Bundle? {
        lock.withLock { bundles[locale] }
    }

    /// Applies one update: every locale in `catalog` replaces what that locale
    /// had before, the others stay.
    @discardableResult
    func apply(catalog: [String: Any], lastModified: String) throws -> Set<String> {
        guard let strings = catalog["strings"] as? [String: Any] else { throw CatalogError.notACatalog }
        var incoming: [String: [String: Any]] = [:]
        for (key, raw) in strings {
            guard let localizations = (raw as? [String: Any])?["localizations"] as? [String: Any] else { continue }
            for (locale, unit) in localizations {
                incoming[locale, default: [:]][key] = unit
            }
        }
        return try lock.withLock {
            var merged = units
            for (locale, localeUnits) in incoming { merged[locale] = localeUnits }
            try write(units: merged, state: State(lastModified: lastModified, revision: state.revision + 1))
            return Set(incoming.keys)
        }
    }

    func clear() {
        lock.withLock {
            try? FileManager.default.removeItem(at: directory)
            units = [:]
            tables = [:]
            bundles = [:]
            state = State()
        }
    }

    // MARK: - Disk

    private var unitsFile: URL { directory.appendingPathComponent("units.json") }
    private var stateFile: URL { directory.appendingPathComponent("state.json") }

    private func revisionDirectory(_ revision: Int) -> URL {
        directory.appendingPathComponent("revision-\(revision)", isDirectory: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateFile),
              let saved = try? JSONDecoder().decode(State.self, from: data),
              let unitData = try? Data(contentsOf: unitsFile),
              let savedUnits = try? JSONSerialization.jsonObject(with: unitData) as? [String: [String: Any]] else {
            return
        }
        // Rewritten on every launch: the tables are cheap and this drops any
        // revision folder a crash left half written.
        try? lock.withLock { try write(units: savedUnits, state: saved) }
    }

    /// Caller holds the lock.
    private func write(units newUnits: [String: [String: Any]], state newState: State) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalog: [String: Any] = ["strings": Dictionary(grouping: newUnits.flatMap { locale, units in
            units.map { (key: $0.key, locale: locale, unit: $0.value) }
        }, by: \.key).mapValues { entries in
            ["localizations": Dictionary(uniqueKeysWithValues: entries.map { ($0.locale, $0.unit) })]
        }]
        let compiled = try Catalog.compile(catalog, device: device)
        let folder = revisionDirectory(newState.revision)
        try? fileManager.removeItem(at: folder)
        var newBundles: [String: Bundle] = [:]
        for (locale, table) in compiled {
            let lproj = folder.appendingPathComponent(locale, isDirectory: true)
                .appendingPathComponent("\(locale).lproj", isDirectory: true)
            try fileManager.createDirectory(at: lproj, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: table.strings, format: .binary, options: 0)
                .write(to: lproj.appendingPathComponent("Localizable.strings"))
            try PropertyListSerialization.data(fromPropertyList: table.plurals, format: .binary, options: 0)
                .write(to: lproj.appendingPathComponent("Localizable.stringsdict"))
            let info: [String: Any] = [
                "CFBundleIdentifier": "com.flutterlocalisation.live.\(locale)",
                "CFBundleDevelopmentRegion": locale,
                "CFBundleLocalizations": [locale],
            ]
            try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
                .write(to: lproj.deletingLastPathComponent().appendingPathComponent("Info.plist"))
            newBundles[locale] = Bundle(url: lproj.deletingLastPathComponent())
        }
        try JSONSerialization.data(withJSONObject: newUnits).write(to: unitsFile, options: .atomic)
        try JSONEncoder().encode(newState).write(to: stateFile, options: .atomic)

        // The previous folder stays one more round for a lookup that picked
        // up its bundle just before the swap.
        for item in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] {
            guard item.hasPrefix("revision-"), let number = Int(item.dropFirst("revision-".count)),
                  number < newState.revision - 1 else { continue }
            try? fileManager.removeItem(at: directory.appendingPathComponent(item))
        }
        units = newUnits
        tables = compiled
        bundles = newBundles
        state = newState
    }
}
