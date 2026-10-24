import Foundation

/// Lecteur JSON minimal et rapide, octet par octet. Sert aux grosses listes Xtream (dizaines de milliers d'entrées) :
/// on ne garde que les champs utiles, sans construire tout l'arbre JSON en mémoire. Les valeurs simples (texte, nombre,
/// booléen, null) sont toutes rendues en texte, car les serveurs Xtream mélangent les types.
struct JSONScan {
    enum Err: Error { case bad(Int) }

    private let b: UnsafeBufferPointer<UInt8>
    private(set) var i = 0

    init(_ buffer: UnsafeBufferPointer<UInt8>) { b = buffer }

    var atEnd: Bool { var j = i; while j < b.count, Self.isWS(b[j]) { j += 1 }; return j >= b.count }

    private static func isWS(_ c: UInt8) -> Bool { c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 }

    mutating func ws() { while i < b.count, Self.isWS(b[i]) { i += 1 } }

    /// Prochain caractère significatif, sans l'avancer.
    mutating func peek() -> UInt8? { ws(); return i < b.count ? b[i] : nil }

    mutating func expect(_ c: UInt8) throws {
        ws()
        guard i < b.count, b[i] == c else { throw Err.bad(i) }
        i += 1
    }

    /// Consomme `c` s'il est là.
    mutating func take(_ c: UInt8) -> Bool {
        ws()
        if i < b.count, b[i] == c { i += 1; return true }
        return false
    }

    mutating func string() throws -> String {
        try expect(0x22)       // "
        let start = i
        var plain = true
        while i < b.count {
            let c = b[i]
            if c == 0x22 { break }
            if c == 0x5C { plain = false; i += 2; continue }   // \x
            i += 1
        }
        guard i < b.count else { throw Err.bad(i) }
        let end = i
        i += 1
        if plain { return String(decoding: UnsafeBufferPointer(rebasing: b[start..<end]), as: UTF8.self) }
        return Self.unescape(UnsafeBufferPointer(rebasing: b[start..<end]))
    }

    private static func hex(_ c: UInt8) -> UInt32? {
        switch c {
        case 0x30...0x39: return UInt32(c - 0x30)
        case 0x41...0x46: return UInt32(c - 0x41 + 10)
        case 0x61...0x66: return UInt32(c - 0x61 + 10)
        default: return nil
        }
    }

    private static func unescape(_ s: UnsafeBufferPointer<UInt8>) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(s.count)
        var j = 0
        func u4(_ k: Int) -> UInt32? {
            guard k + 4 <= s.count else { return nil }
            var v: UInt32 = 0
            for n in 0..<4 { guard let h = hex(s[k + n]) else { return nil }; v = v << 4 | h }
            return v
        }
        func put(_ scalar: UInt32) {
            let u = Unicode.Scalar(scalar) ?? "\u{FFFD}"
            out.append(contentsOf: Array(String(Character(u)).utf8))
        }
        while j < s.count {
            let c = s[j]
            if c != 0x5C { out.append(c); j += 1; continue }
            guard j + 1 < s.count else { break }
            let e = s[j + 1]
            j += 2
            switch e {
            case 0x6E: out.append(0x0A)       // n
            case 0x74: out.append(0x09)       // t
            case 0x72: out.append(0x0D)       // r
            case 0x62: out.append(0x08)       // b
            case 0x66: out.append(0x0C)       // f
            case 0x75:                        // uXXXX (avec paires de substitution)
                guard var v = u4(j) else { break }
                j += 4
                if (0xD800...0xDBFF).contains(v), j + 6 <= s.count, s[j] == 0x5C, s[j + 1] == 0x75, let lo = u4(j + 2), (0xDC00...0xDFFF).contains(lo) {
                    v = 0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00)
                    j += 6
                }
                put(v)
            default: out.append(e)           // " \ / et autres
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Valeur simple rendue en texte ; un objet ou un tableau est sauté et rend "".
    mutating func scalar() throws -> String {
        guard let c = peek() else { throw Err.bad(i) }
        switch c {
        case 0x22: return try string()
        case 0x7B, 0x5B: try skip(); return ""
        default:
            let start = i
            while i < b.count {
                let d = b[i]
                if d == 0x2C || d == 0x7D || d == 0x5D || Self.isWS(d) { break }
                i += 1
            }
            let t = String(decoding: UnsafeBufferPointer(rebasing: b[start..<i]), as: UTF8.self)
            return t == "null" ? "" : t
        }
    }

    /// Saute une valeur quelconque.
    mutating func skip() throws {
        guard let c = peek() else { throw Err.bad(i) }
        switch c {
        case 0x22: _ = try string()
        case 0x7B, 0x5B:
            var depth = 0
            while i < b.count {
                let d = b[i]
                if d == 0x22 { _ = try string(); continue }
                if d == 0x7B || d == 0x5B { depth += 1 }
                if d == 0x7D || d == 0x5D { depth -= 1; if depth == 0 { i += 1; return } }
                i += 1
            }
            throw Err.bad(i)
        default: _ = try scalar()
        }
    }

    /// Parcourt un objet : appelle `body` pour chaque clé, qui doit lire ou sauter la valeur.
    mutating func object(_ body: (inout JSONScan, String) throws -> Void) throws {
        try expect(0x7B)
        if take(0x7D) { return }
        repeat {
            let k = try string()
            try expect(0x3A)
            try body(&self, k)
        } while take(0x2C)
        try expect(0x7D)
    }

    /// Parcourt un tableau : `body` lit ou saute chaque élément.
    mutating func array(_ body: (inout JSONScan) throws -> Void) throws {
        try expect(0x5B)
        if take(0x5D) { return }
        repeat { try body(&self) } while take(0x2C)
        try expect(0x5D)
    }

    /// Liste d'objets envoyée en tableau, ou en objet indexé (« "1": {…}, "2": {…} ») par certains serveurs.
    /// `keyed` est vrai dans le second cas.
    mutating func list(_ body: (inout JSONScan) throws -> Void) throws -> (keyed: Bool, ok: Bool) {
        guard let c = peek() else { return (false, false) }
        if c == 0x5B { try array(body); return (false, true) }
        if c == 0x7B { try object { s, _ in try body(&s) }; return (true, true) }
        return (false, false)
    }
}
