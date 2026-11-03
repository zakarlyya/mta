import Foundation

/// Token-based station search tolerant of MTA abbreviations ("Sq", "St", "Av"),
/// ordinals ("57th"), punctuation, and line letters ("union sq n").
enum StationSearch {
    private static let synonyms: [String: String] = [
        "square": "sq", "street": "st", "streets": "sts", "avenue": "av", "ave": "av",
        "avenues": "avs", "road": "rd", "boulevard": "blvd", "parkway": "pkwy",
        "place": "pl", "heights": "hts", "center": "ctr", "centre": "ctr",
        "junction": "jct", "terminal": "term", "plaza": "plz", "turnpike": "tpke",
        "highway": "hwy", "beach": "bch", "court": "ct", "lane": "ln", "drive": "dr",
        "saint": "st", "mount": "mt", "fort": "ft", "park": "pk", "bridge": "br",
        "east": "e", "west": "w", "north": "n", "south": "s",
    ]
    private static let stopWords: Set<String> = ["and", "the", "station", "stop"]
    private static let boroughs = [
        "M": "manhattan", "Bk": "brooklyn", "Q": "queens", "Bx": "bronx", "SI": "staten island",
    ]

    private struct Entry {
        let station: Station
        let nameTokens: [String]
        let otherTokens: [String]
        let routes: Set<String>
    }

    private static let index: [Entry] = Station.all.map { station in
        Entry(
            station: station,
            nameTokens: tokenize(station.name),
            otherTokens: tokenize(station.line + " " + (boroughs[station.borough] ?? "")),
            routes: Set(station.routes.map { RouteStyle.displayName($0).lowercased() })
        )
    }

    static func search(_ query: String, limit: Int = 25) -> [Station] {
        let terms = tokenize(query)
        guard !terms.isEmpty else { return [] }
        let joined = terms.joined(separator: " ")

        let scored: [(Station, Int)] = index.compactMap { entry in
            var score = 0
            for term in terms {
                if entry.nameTokens.contains(term) { score += 3 }
                else if entry.nameTokens.contains(where: { $0.hasPrefix(term) }) { score += 2 }
                else if entry.routes.contains(term) { score += 2 }
                else if entry.otherTokens.contains(where: { $0.hasPrefix(term) }) { score += 1 }
                else { return nil }
            }
            if entry.nameTokens.joined(separator: " ").hasPrefix(joined) { score += 3 }
            return (entry.station, score)
        }

        return scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.0.name.count != $1.0.name.count { return $0.0.name.count < $1.0.name.count }
                return $0.0.name < $1.0.name
            }
            .prefix(limit)
            .map(\.0)
    }

    static func tokenize(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private static func normalize(_ token: String) -> String {
        if let match = token.wholeMatch(of: /(\d+)(st|nd|rd|th)/) { return String(match.1) }
        return synonyms[token] ?? token
    }
}
