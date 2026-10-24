import Foundation

/// Un programme du guide (XMLTV).
struct Prog: Codable, Equatable {
    var start: Date
    var stop: Date
    var title: String
    var desc: String
}

/// Guide des programmes : lecture du XMLTV en flux (fichiers de plusieurs dizaines de Mo), en ne gardant, par chaîne,
/// que les 8 prochains programmes des 12 prochaines heures. Clé : epg_channel_id en minuscules.
final class XMLTVParser: NSObject, XMLParserDelegate {
    private(set) var out: [String: [Prog]] = [:]
    private let now: Date
    private let horizon: Date
    private var ch: String?
    private var start = Date.distantPast, stop = Date.distantPast
    private var title = "", desc = ""
    private var buffer = ""
    private var inTitle = false, inDesc = false

    init(now: Date = Date()) {
        self.now = now
        horizon = now.addingTimeInterval(12 * 3600)
    }

    private static let f1: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f
    }()
    private static let f2: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    static func date(_ s: String?) -> Date? {
        guard let v = s?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        return f1.date(from: v) ?? f2.date(from: String(v.prefix(14)))
    }

    static func parse(_ data: Data, now: Date = Date()) -> [String: [Prog]] {
        let d = XMLTVParser(now: now)
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.out.mapValues { $0.sorted { $0.start < $1.start } }
    }

    static func parse(contentsOf url: URL, now: Date = Date()) -> [String: [Prog]] {
        let d = XMLTVParser(now: now)
        guard let p = XMLParser(contentsOf: url) else { return [:] }
        p.delegate = d
        p.parse()
        return d.out.mapValues { $0.sorted { $0.start < $1.start } }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String] = [:]) {
        switch name {
        case "programme":
            ch = a["channel"]
            start = Self.date(a["start"]) ?? .distantPast
            stop = Self.date(a["stop"]) ?? .distantPast
            title = ""; desc = ""
        case "title" where ch != nil && title.isEmpty: inTitle = true; buffer = ""
        case "desc" where ch != nil && desc.isEmpty: inDesc = true; buffer = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle || inDesc { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "title" where inTitle: title = buffer.trimmingCharacters(in: .whitespacesAndNewlines); inTitle = false
        case "desc" where inDesc: desc = buffer.trimmingCharacters(in: .whitespacesAndNewlines); inDesc = false
        case "programme":
            if let c = ch, stop > now, start < horizon {
                let k = c.lowercased()
                if (out[k]?.count ?? 0) < 8 { out[k, default: []].append(Prog(start: start, stop: stop, title: title, desc: desc)) }
            }
            ch = nil
        default: break
        }
    }

    /// Programme en cours et suivant.
    static func nowNext(_ list: [Prog]?, at now: Date = Date()) -> (Prog?, Prog?) {
        guard let l = list, let i = l.firstIndex(where: { $0.stop > now }) else { return (nil, nil) }
        let cur = l[i].start <= now ? l[i] : nil
        let nextIndex = cur != nil ? i + 1 : i
        return (cur, nextIndex < l.count ? l[nextIndex] : nil)
    }
}
