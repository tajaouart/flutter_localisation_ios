import Foundation

/// One locale of a String Catalog, in the two shapes Foundation reads at
/// runtime: `.strings` for plain strings, `.stringsdict` for plurals.
struct CompiledTable: Equatable {
    var strings: [String: String] = [:]
    var plurals: [String: NSDictionary] = [:]

    var keys: Set<String> { Set(strings.keys).union(plurals.keys) }
    var isEmpty: Bool { strings.isEmpty && plurals.isEmpty }
}

enum CatalogError: Error, Equatable {
    case notACatalog
}

/// Compiles an `.xcstrings` catalog the way `xcstringstool compile` does, so a
/// string delivered live is formatted by Foundation exactly like one Xcode
/// built into the app.
enum Catalog {
    static let pluralCategories = ["zero", "one", "two", "few", "many", "other"]

    static func compile(_ data: Data, device: String = Catalog.currentDevice) throws -> [String: CompiledTable] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.notACatalog
        }
        return try compile(root, device: device)
    }

    static func compile(_ root: [String: Any], device: String = Catalog.currentDevice) throws -> [String: CompiledTable] {
        guard let strings = root["strings"] as? [String: Any] else { throw CatalogError.notACatalog }
        var tables: [String: CompiledTable] = [:]
        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            for (locale, rawUnit) in localizations {
                guard let unit = rawUnit as? [String: Any] else { continue }
                var table = tables[locale] ?? CompiledTable()
                switch compileUnit(unit, key: key, device: device) {
                case .string(let value): table.strings[key] = value
                case .plural(let dictionary): table.plurals[key] = dictionary
                case nil: break
                }
                tables[locale] = table
            }
        }
        return tables.filter { !$0.value.isEmpty }
    }

    /// The device a `variations.device` entry is picked for.
    static var currentDevice: String {
        #if os(watchOS)
        return "applewatch"
        #elseif os(tvOS)
        return "appletv"
        #elseif os(visionOS)
        return "applevision"
        #elseif os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac { return "mac" }
        return deviceModel.hasPrefix("iPad") ? "ipad" : "iphone"
        #else
        return "mac"
        #endif
    }

    #if os(iOS)
    private static let deviceModel: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()
    #endif

    // MARK: - Units

    private enum Compiled {
        case string(String)
        case plural(NSDictionary)
    }

    private static func compileUnit(_ unit: [String: Any], key: String, device: String) -> Compiled? {
        if let variations = unit["variations"] as? [String: Any] {
            if let devices = variations["device"] as? [String: Any] {
                guard let chosen = (devices[device] ?? devices["other"]) as? [String: Any] else { return nil }
                return compileUnit(chosen, key: key, device: device)
            }
            if let plural = variations["plural"] as? [String: Any] {
                return wholeStringPlural(plural, key: key)
            }
            return nil
        }
        guard let value = stringValue(unit) else { return nil }
        if let substitutions = unit["substitutions"] as? [String: Any], !substitutions.isEmpty {
            return substitutionPlural(value, substitutions, device: device)
        }
        return .string(value)
    }

    private static func stringValue(_ unit: [String: Any]) -> String? {
        guard let stringUnit = unit["stringUnit"] as? [String: Any] else { return nil }
        return stringUnit["value"] as? String
    }

    private static func arms(_ plural: [String: Any]) -> [String: String] {
        var arms: [String: String] = [:]
        for category in pluralCategories {
            if let unit = plural[category] as? [String: Any], let value = stringValue(unit) {
                arms[category] = value
            }
        }
        return arms
    }

    /// `variations.plural` on the whole string: Xcode drives it from the first
    /// numeric argument and names the variable `value`.
    private static func wholeStringPlural(_ plural: [String: Any], key: String) -> Compiled? {
        let arms = arms(plural)
        guard !arms.isEmpty else { return nil }
        let sample = arms["other"] ?? arms.values.sorted().first!
        let numeric = FormatSpecifier.parse(sample).first(where: \.isNumeric)
            ?? FormatSpecifier.parse(key).first(where: \.isNumeric)
        let position = numeric?.position ?? 1
        let positional = arms.values.contains { FormatSpecifier.parse($0).contains(where: \.isPositional) }
        let formatKey = positional || position != 1 ? "%\(position)$#@value@" : "%#@value@"
        var rule: [String: String] = [
            "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
            "NSStringFormatValueTypeKey": numeric?.valueType ?? "lld",
        ]
        rule.merge(arms) { $1 }
        return .plural(["NSStringLocalizedFormatKey": formatKey, "value": rule] as NSDictionary)
    }

    /// A string with `%#@name@` tokens, each one argument varied by plural.
    /// Inside a substitution `%arg` stands for that argument.
    private static func substitutionPlural(_ value: String, _ substitutions: [String: Any], device: String) -> Compiled {
        var formatKey = value
        var dictionary: [String: Any] = [:]
        for (name, raw) in substitutions {
            guard let substitution = raw as? [String: Any] else { continue }
            let argNum = (substitution["argNum"] as? Int) ?? 1
            let spec = (substitution["formatSpecifier"] as? String) ?? "lld"
            var variations = substitution["variations"] as? [String: Any] ?? [:]
            if let devices = variations["device"] as? [String: Any],
               let chosen = (devices[device] ?? devices["other"]) as? [String: Any] {
                variations = chosen["variations"] as? [String: Any] ?? [:]
            }
            guard let plural = variations["plural"] as? [String: Any] else { continue }
            formatKey = formatKey.replacingOccurrences(of: "%#@\(name)@", with: "%\(argNum)$#@\(name)@")
            var rule: [String: String] = [
                "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                "NSStringFormatValueTypeKey": spec,
            ]
            for (category, text) in arms(plural) {
                rule[category] = text.replacingOccurrences(of: "%arg", with: "%\(argNum)$\(spec)")
            }
            dictionary[name] = rule
        }
        dictionary["NSStringLocalizedFormatKey"] = formatKey
        return .plural(dictionary as NSDictionary)
    }
}

/// One printf conversion in a format string, `%2$lld` or `%@`.
struct FormatSpecifier: Equatable {
    var position: Int
    var isPositional: Bool
    var length: String
    var conversion: Character

    var valueType: String { length + String(conversion) }
    var isNumeric: Bool { "diouxXfFeEgGaA".contains(conversion) }

    private static let pattern = try! NSRegularExpression(
        pattern: #"%(?:(\d+)\$)?[-+ 0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|z|t|L)?([@diouxXfFeEgGaAcsSpC%])"#
    )

    static func parse(_ text: String) -> [FormatSpecifier] {
        let range = NSRange(text.startIndex..., in: text)
        var sequential = 0
        var found: [FormatSpecifier] = []
        for match in pattern.matches(in: text, range: range) {
            let conversion = Character(String(text[Range(match.range(at: 3), in: text)!]))
            if conversion == "%" { continue }
            let length = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            if let explicit = Range(match.range(at: 1), in: text).flatMap({ Int(text[$0]) }) {
                found.append(FormatSpecifier(position: explicit, isPositional: true, length: length, conversion: conversion))
            } else {
                sequential += 1
                found.append(FormatSpecifier(position: sequential, isPositional: false, length: length, conversion: conversion))
            }
        }
        return found
    }
}
