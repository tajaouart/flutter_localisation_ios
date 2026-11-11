import Foundation

/// The CLDR plural category Foundation picks for `count` in the languages this
/// demo ships, with the `zero` arm iOS applies to 0 whenever a string has one.
enum PluralCategory {
    static func of(_ count: Int, language: String, hasZeroArm: Bool) -> String {
        if count == 0 && hasZeroArm { return "zero" }
        let n = abs(count)
        switch language {
        case "ar":
            switch n {
            case 0: return "zero"
            case 1: return "one"
            case 2: return "two"
            default:
                if (3...10).contains(n % 100) { return "few" }
                if (11...99).contains(n % 100) { return "many" }
                return "other"
            }
        case "fr":
            if n == 0 || n == 1 { return "one" }
            return n % 1_000_000 == 0 ? "many" : "other"
        case "es":
            if n == 1 { return "one" }
            return n != 0 && n % 1_000_000 == 0 ? "many" : "other"
        case "zh":
            return "other"
        default:
            return n == 1 ? "one" : "other"
        }
    }
}
