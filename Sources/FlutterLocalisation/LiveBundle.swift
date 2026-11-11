import Foundation
import ObjectiveC

/// Answers lookups on one app bundle from the live store first.
///
/// Order, for an app running in `es-MX`: a live `es-MX` string, then the
/// bundled `es-MX` one, then a live `es` string, then whatever the bundle does
/// on its own. A base language only follows a region or script variant when
/// both are written in the same script, so `zh-Hant` never shows `zh` (which
/// is Simplified) strings.
final class LiveResolver: @unchecked Sendable {
    let store: LiveStore
    private unowned let bundle: Bundle
    private let lock = NSLock()
    private var bundledKeys: [String: Set<String>] = [:]
    private var chains: [String: [String]] = [:]

    init(store: LiveStore, bundle: Bundle) {
        self.store = store
        self.bundle = bundle
    }

    /// The live bundle answering `key`, nil when the app's own copy wins.
    func liveBundle(forKey key: String, table: String?, preferred: String? = nil) -> Bundle? {
        guard table == nil || table == "Localizable" || table == "" else { return nil }
        for locale in preferred.map(chain(for:)) ?? chain() {
            if store.contains(key, locale: locale) { return store.bundle(for: locale) }
            if bundled(locale).contains(key) { return nil }
        }
        return nil
    }

    func isLive(_ key: String) -> Bool {
        liveBundle(forKey: key, table: nil) != nil
    }

    /// The locales consulted, most specific first.
    func chain() -> [String] {
        chain(for: bundle.preferredLocalizations.first ?? bundle.developmentLocalization ?? "en")
    }

    func chain(for current: String) -> [String] {
        lock.withLock {
            if let cached = chains[current] { return cached }
            let built = LiveResolver.fallbacks(of: current)
            chains[current] = built
            return built
        }
    }

    static func fallbacks(of identifier: String) -> [String] {
        let language = Locale.Language(identifier: identifier)
        guard let code = language.languageCode?.identifier, code != identifier else { return [identifier] }
        let script = language.maximalIdentifier.split(separator: "-").dropFirst().first
        let baseScript = Locale.Language(identifier: code).maximalIdentifier.split(separator: "-").dropFirst().first
        return script == baseScript ? [identifier, code] : [identifier]
    }

    private func bundled(_ locale: String) -> Set<String> {
        lock.withLock {
            if let keys = bundledKeys[locale] { return keys }
            var keys = Set<String>()
            for ext in ["strings", "stringsdict"] {
                if let url = bundle.url(forResource: "Localizable", withExtension: ext, subdirectory: nil, localization: locale),
                   let table = NSDictionary(contentsOf: url) as? [String: Any] {
                    keys.formUnion(table.keys)
                }
            }
            bundledKeys[locale] = keys
            return keys
        }
    }
}

/// The class an app bundle is switched to so its lookups reach the live
/// store. Foundation has several entry points and each API takes its own:
/// `NSLocalizedString` the public three-argument one, `String(localized:)`
/// and `LocalizedStringResource` a private one with a locale list,
/// `AttributedString(localized:)` an uncached one. Each is answered by the
/// same selector on the live bundle, so Foundation still does the formatting.
final class LiveBundle: Bundle, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var resolvers: [ObjectIdentifier: LiveResolver] = [:]
    nonisolated(unsafe) private static var hooked = false

    static func resolver(for bundle: Bundle) -> LiveResolver? {
        lock.withLock { resolvers[ObjectIdentifier(bundle)] }
    }

    static func install(_ resolver: LiveResolver, on bundle: Bundle) {
        lock.withLock {
            if !hooked {
                hookLookups()
                hooked = true
            }
            resolvers[ObjectIdentifier(bundle)] = resolver
            if !(bundle is LiveBundle) { object_setClass(bundle, LiveBundle.self) }
        }
    }

    /// The bundle that answers: the live one for `key`, or `bundle` itself.
    fileprivate static func target(_ bundle: AnyObject, key: NSString, table: NSString?, locales: Any?) -> (Bundle, isLive: Bool) {
        let own = bundle as! Bundle
        guard let resolver = resolver(for: own),
              let live = resolver.liveBundle(forKey: key as String, table: table as String?, preferred: firstLocale(locales))
        else { return (own, false) }
        return (live, true)
    }

    private static func firstLocale(_ locales: Any?) -> String? {
        switch locales {
        case let single as String: return single
        case let list as [Any]: return list.first.map { String(describing: $0) }
        default: return nil
        }
    }

    private typealias Three = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?) -> AnyObject
    private typealias Four = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?, AnyObject?) -> AnyObject
    private typealias Six = @convention(c) (AnyObject, Selector, NSString, NSString?, NSString?, AnyObject?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> AnyObject

    private static func original(_ selector: Selector) -> IMP? {
        class_getInstanceMethod(Bundle.self, selector).map(method_getImplementation)
    }

    private static func add(_ selector: Selector, _ block: Any) {
        guard let method = class_getInstanceMethod(Bundle.self, selector) else { return }
        class_addMethod(LiveBundle.self, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }

    private static func hookLookups() {
        for name in ["localizedStringForKey:value:table:", "localizedAttributedStringForKey:value:table:"] {
            let selector = NSSelectorFromString(name)
            guard let imp = original(selector) else { continue }
            let call = unsafeBitCast(imp, to: Three.self)
            let block: @convention(block) (AnyObject, NSString, NSString?, NSString?) -> AnyObject = { this, key, value, table in
                let (bundle, isLive) = target(this, key: key, table: table, locales: nil)
                return call(bundle, selector, key, value, isLive ? nil : table)
            }
            add(selector, block)
        }
        for name in [
            "localizedStringForKey:value:table:localization:",
            "localizedStringForKey:value:table:localizations:",
            "_localizedStringForKey:value:table:localizations:",
            "localizedAttributedStringForKey:value:table:localization:",
        ] {
            let selector = NSSelectorFromString(name)
            guard let imp = original(selector) else { continue }
            let call = unsafeBitCast(imp, to: Four.self)
            let block: @convention(block) (AnyObject, NSString, NSString?, NSString?, AnyObject?) -> AnyObject = { this, key, value, table, locales in
                let (bundle, isLive) = target(this, key: key, table: table, locales: locales)
                // The live bundle holds a single locale, it must not be asked for another.
                return isLive ? call(bundle, selector, key, value, nil, nil) : call(bundle, selector, key, value, table, locales)
            }
            add(selector, block)
        }
        let uncached = NSSelectorFromString(
            "_localizedStringNoCacheNoMarkdownParsingForKey:value:table:localizations:actualTableURL:formatSpecifierConfiguration:"
        )
        if let imp = original(uncached) {
            let call = unsafeBitCast(imp, to: Six.self)
            let block: @convention(block) (AnyObject, NSString, NSString?, NSString?, AnyObject?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> AnyObject = { this, key, value, table, locales, url, configuration in
                let (bundle, isLive) = target(this, key: key, table: table, locales: locales)
                return isLive
                    ? call(bundle, uncached, key, value, nil, nil, url, configuration)
                    : call(bundle, uncached, key, value, table, locales, url, configuration)
            }
            add(uncached, block)
        }
    }
}
