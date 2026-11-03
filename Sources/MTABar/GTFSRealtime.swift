import Foundation

/// The subset of a GTFS-Realtime feed this app needs.
struct FeedSnapshot: Sendable {
    struct StopTime: Sendable {
        let stopID: String
        let time: Int64
    }

    struct Trip: Sendable {
        var tripID = ""
        var routeID = ""
        var stops: [StopTime] = []
    }

    var timestamp: Int64 = 0
    var trips: [Trip] = []
}

enum GTFSFeed {
    static let baseURL = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/"

    static func path(for route: String) -> String? {
        switch route {
        case "1", "2", "3", "4", "5", "6", "7", "GS": "nyct%2Fgtfs"
        case "A", "C", "E", "H", "FS": "nyct%2Fgtfs-ace"
        case "B", "D", "F", "M": "nyct%2Fgtfs-bdfm"
        case "G": "nyct%2Fgtfs-g"
        case "J", "Z": "nyct%2Fgtfs-jz"
        case "N", "Q", "R", "W": "nyct%2Fgtfs-nqrw"
        case "L": "nyct%2Fgtfs-l"
        case "SI": "nyct%2Fgtfs-si"
        default: nil
        }
    }

    /// Express variants (6X, 7X, FX) are shown as their base line.
    static func normalize(_ route: String) -> String {
        route.count == 2 && route.hasSuffix("X") ? String(route.prefix(1)) : route
    }

    @concurrent
    static func fetch(path: String) async throws -> FeedSnapshot {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try parse([UInt8](data))
    }

    static func parse(_ bytes: [UInt8]) throws -> FeedSnapshot {
        var snapshot = FeedSnapshot()
        var feed = ProtoReader(bytes)
        while let (field, wire) = try feed.next() {
            switch (field, wire) {
            case (1, 2):
                var header = try feed.message()
                while let (f, w) = try header.next() {
                    if f == 3, w == 0 { snapshot.timestamp = Int64(bitPattern: try header.varint()) }
                    else { try header.skip(w) }
                }
            case (2, 2):
                var entity = try feed.message()
                while let (f, w) = try entity.next() {
                    if f == 3, w == 2 { snapshot.trips.append(try parseTripUpdate(entity.message())) }
                    else { try entity.skip(w) }
                }
            default:
                try feed.skip(wire)
            }
        }
        return snapshot
    }

    private static func parseTripUpdate(_ reader: ProtoReader) throws -> FeedSnapshot.Trip {
        var reader = reader
        var trip = FeedSnapshot.Trip()
        while let (field, wire) = try reader.next() {
            switch (field, wire) {
            case (1, 2):
                var descriptor = try reader.message()
                while let (f, w) = try descriptor.next() {
                    switch (f, w) {
                    case (1, 2): trip.tripID = try descriptor.string()
                    case (5, 2): trip.routeID = try descriptor.string()
                    default: try descriptor.skip(w)
                    }
                }
            case (2, 2):
                var update = try reader.message()
                var stopID = ""
                var arrival: Int64 = 0
                var departure: Int64 = 0
                while let (f, w) = try update.next() {
                    switch (f, w) {
                    case (2, 2): arrival = try eventTime(update.message())
                    case (3, 2): departure = try eventTime(update.message())
                    case (4, 2): stopID = try update.string()
                    default: try update.skip(w)
                    }
                }
                let time = arrival != 0 ? arrival : departure
                if time != 0 { trip.stops.append(.init(stopID: stopID, time: time)) }
            default:
                try reader.skip(wire)
            }
        }
        return trip
    }

    private static func eventTime(_ reader: ProtoReader) throws -> Int64 {
        var reader = reader
        var time: Int64 = 0
        while let (field, wire) = try reader.next() {
            if field == 2, wire == 0 { time = Int64(bitPattern: try reader.varint()) }
            else { try reader.skip(wire) }
        }
        return time
    }
}

/// Minimal protobuf wire-format reader.
struct ProtoReader {
    struct Malformed: Error {}

    private let bytes: [UInt8]
    private var index: Int
    private let end: Int

    init(_ bytes: [UInt8]) {
        self.init(bytes, start: 0, end: bytes.count)
    }

    private init(_ bytes: [UInt8], start: Int, end: Int) {
        self.bytes = bytes
        self.index = start
        self.end = end
    }

    mutating func next() throws -> (Int, Int)? {
        guard index < end else { return nil }
        let key = try varint()
        return (Int(key >> 3), Int(key & 7))
    }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < end, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw Malformed()
    }

    mutating func message() throws -> ProtoReader {
        let range = try lengthDelimited()
        return ProtoReader(bytes, start: range.lowerBound, end: range.upperBound)
    }

    mutating func string() throws -> String {
        String(decoding: bytes[try lengthDelimited()], as: UTF8.self)
    }

    mutating func skip(_ wire: Int) throws {
        switch wire {
        case 0: _ = try varint()
        case 1: try advance(8)
        case 2: _ = try lengthDelimited()
        case 5: try advance(4)
        default: throw Malformed()
        }
    }

    private mutating func lengthDelimited() throws -> Range<Int> {
        let length = Int(try varint())
        let start = index
        try advance(length)
        return start..<index
    }

    private mutating func advance(_ count: Int) throws {
        guard count >= 0, index + count <= end else { throw Malformed() }
        index += count
    }
}
