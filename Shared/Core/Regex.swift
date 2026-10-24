import Foundation

/// Petite enveloppe autour de NSRegularExpression (moteur ICU, syntaxe proche de celle de Kotlin/Java).
struct Rx {
    let re: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        do { re = try NSRegularExpression(pattern: pattern, options: options) } catch {
            fatalError("Expression invalide : \(pattern) — \(error)")
        }
    }

    private func whole(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    func first(_ s: String) -> NSTextCheckingResult? { re.firstMatch(in: s, range: whole(s)) }
    func all(_ s: String) -> [NSTextCheckingResult] { re.matches(in: s, range: whole(s)) }
    func contains(_ s: String) -> Bool { first(s) != nil }
    func replace(_ s: String, _ template: String = "") -> String {
        re.stringByReplacingMatches(in: s, range: whole(s), withTemplate: NSRegularExpression.escapedTemplate(for: template))
    }
    /// Toute la chaîne correspond.
    func matches(_ s: String) -> Bool {
        guard let m = first(s) else { return false }
        return m.range.location == 0 && m.range.length == (s as NSString).length
    }
}

extension NSTextCheckingResult {
    /// Texte du groupe `i`, ou nil s'il n'a pas participé.
    func group(_ i: Int, in s: String) -> String? {
        guard i < numberOfRanges else { return nil }
        let r = range(at: i)
        if r.location == NSNotFound { return nil }
        return (s as NSString).substring(with: r)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Retire la plage (exprimée en UTF-16, comme les résultats d'expression).
    func removing(_ r: NSRange) -> String { (self as NSString).replacingCharacters(in: r, with: "") }
    func substring(fromUTF16 i: Int) -> String { (self as NSString).substring(from: i) }
    /// Minuscules et sans accents.
    var folded: String { lowercased().folding(options: [.diacriticInsensitive], locale: nil) }
}
