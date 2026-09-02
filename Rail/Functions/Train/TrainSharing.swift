import Foundation
import SwiftData

/// Encodes a saved journey into a `rail://` link and back.
///
/// The link is self-contained: everything needed to rebuild the journey travels
/// inside it, so importing one works offline and keeps working for trains the
/// live API has long stopped serving.
///
/// That makes length the thing to fight for. The payload is a packed binary
/// blob — no field names, varints instead of fixed-width numbers, stop times as
/// minute deltas from the first stop, and a lookup table for the handful of
/// logo and provider strings that ever occur — then deflated and base64url'd.
/// A six-stop journey with one passenger lands around 210 characters, against
/// roughly 330 for the JSON encoding this replaces.
///
/// Passenger codes travel as their text plus which symbology they were drawn
/// in, and the image is redrawn on the other side — a few dozen characters
/// instead of the several kilobytes the PNG would cost. When a code cannot be
/// read back at all (a photographed ticket, a damaged code) a shrunken copy of
/// the image itself is carried instead, so the passenger still arrives with
/// something scannable.
enum TrainSharing {
    static let scheme = "rail"
    /// Short on purpose: every character here is a character of link.
    private static let host = "t"
    /// Links shared by earlier versions, which carried deflated JSON.
    private static let legacyHost = "train"

    /// Deliberately lean. Everything that the app refreshes from the API anyway
    /// — weather, delays, live status — is left out, and each stop keeps a single
    /// timestamp instead of five. This is a seed for the journey, not a snapshot of it.
    struct Payload: Codable {
        struct Stop: Codable {
            var name: String
            var platform: String
            var time: Date
            var selected: Bool

            enum CodingKeys: String, CodingKey {
                case name = "n", platform = "p", time = "t", selected = "s"
            }
        }

        struct Seat: Codable {
            var name: String
            var carriage: String
            var number: String
            /// The text inside the passenger's code, not the image — a few dozen
            /// characters where the PNG would be kilobytes.
            var qr: String?
            /// Which symbology to redraw `qr` in. Trenitalia prints Aztec, Italo QR;
            /// rebuilding one as the other yields a code no gate will accept.
            var symbology: QRCodePayload.Symbology = .qr
            /// Only set when `qr` could not be read: a shrunken copy of the original.
            var image: Data?

            enum CodingKeys: String, CodingKey {
                case name = "n", carriage = "c", number = "s", qr = "q"
                case symbology = "y", image = "i"
            }

            init(name: String, carriage: String, number: String,
                 qr: String?, symbology: QRCodePayload.Symbology = .qr, image: Data? = nil) {
                self.name = name
                self.carriage = carriage
                self.number = number
                self.qr = qr
                self.symbology = symbology
                self.image = image
            }

            /// Written by hand so links from before these two fields existed still decode.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                carriage = try container.decode(String.self, forKey: .carriage)
                number = try container.decode(String.self, forKey: .number)
                qr = try container.decodeIfPresent(String.self, forKey: .qr)
                symbology = try container.decodeIfPresent(
                    QRCodePayload.Symbology.self, forKey: .symbology) ?? .qr
                image = try container.decodeIfPresent(Data.self, forKey: .image)
            }
        }

        var logo: String
        var number: String
        var identifier: String
        var provider: String
        var direction: String
        var stops: [Stop]
        var seats: [Seat]

        enum CodingKeys: String, CodingKey {
            case logo = "l", number = "n", identifier = "i", provider = "p"
            case direction = "d", stops = "st", seats = "se"
        }
    }

    // MARK: Encoding

    static func payload(train: Train, stops: [Stop], seats: [Seat]) -> Payload {
        Payload(
            logo: train.logo,
            number: train.number,
            identifier: train.identifier,
            provider: train.provider,
            direction: train.direction,
            stops: stops
                .sorted { $0.ref_time < $1.ref_time }
                .map { Payload.Stop(name: $0.name, platform: $0.platform, time: $0.ref_time, selected: $0.is_selected) },
            seats: seats.map { seat in
                let decoded = seat.image.flatMap { QRCodePayload.read(from: $0) }
                return Payload.Seat(
                    name: seat.name,
                    carriage: seat.carriage,
                    number: seat.number,
                    qr: decoded?.text,
                    symbology: decoded?.symbology ?? .qr,
                    // Unreadable code: send the picture rather than nothing at all.
                    image: decoded == nil
                        ? seat.image.flatMap { QRCodePayload.compressedForSharing($0) }
                        : nil
                )
            }
        )
    }

    static func url(train: Train, stops: [Stop], seats: [Seat]) -> URL? {
        url(for: payload(train: train, stops: stops, seats: seats))
    }

    static func url(for payload: Payload) -> URL? {
        let body = encode(payload)
        var container = Data()

        // Deflate only when it actually wins: on a short journey with no stop
        // names to repeat, zlib's header costs more than it saves.
        if let deflated = try? (body as NSData).compressed(using: .zlib) as Data, deflated.count < body.count {
            container.append(version | deflatedFlag)
            container.append(deflated)
        } else {
            container.append(version)
            container.append(body)
        }

        return URL(string: "\(scheme)://\(host)?d=\(base64URL(container))")
    }

    // MARK: Decoding

    static func payload(from url: URL) -> Payload? {
        guard url.scheme?.lowercased() == scheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let encoded = items.first(where: { $0.name == "d" })?.value,
              let raw = data(fromBase64URL: encoded), let marker = raw.first
        else { return nil }

        switch url.host()?.lowercased() {
        case host where isPacked(marker):
            return decode(raw)
        case legacyHost:
            return decodeLegacy(raw)
        default:
            // be forgiving about the host and let the payload identify itself
            return isPacked(marker) ? decode(raw) : decodeLegacy(raw)
        }
    }

    /// True for any packed version we still read, current or older.
    private static func isPacked(_ marker: UInt8) -> Bool {
        let carried = marker & versionMask
        return carried == version || carried == versionWithoutSymbology
    }

    /// Inserts a shared journey, or returns the existing one when it's already saved.
    @discardableResult
    @MainActor
    static func importPayload(_ payload: Payload, into context: ModelContext) -> Train? {
        guard !payload.stops.isEmpty else { return nil }

        let identifier = payload.identifier
        let existing = (try? context.fetch(FetchDescriptor<Train>()))?
            .first { $0.identifier == identifier && !identifier.isEmpty }
        if let existing { return existing }

        let trainID = UUID()
        let train = Train(
            id: trainID, logo: payload.logo, number: payload.number,
            identifier: payload.identifier, provider: payload.provider,
            last_update_time: .distantPast, delay: 0,
            direction: payload.direction, issue: ""
        )
        context.insert(train)

        for stop in payload.stops {
            // live fields start empty; the usual refresh fills them in
            context.insert(Stop(
                id: trainID, name: stop.name, platform: stop.platform, weather: "",
                is_selected: stop.selected, status: 0,
                is_completed: false, is_in_station: false,
                dep_delay: 0, arr_delay: 0,
                dep_time_id: stop.time, arr_time_id: stop.time,
                dep_time_eff: stop.time, arr_time_eff: stop.time, ref_time: stop.time
            ))
        }

        for seat in payload.seats {
            // Redraw from the text when we have it, so the code is crisp; otherwise
            // fall back to the copy of the image the link carried.
            let code = seat.qr
                .flatMap { QRCodePayload.image(from: $0, symbology: seat.symbology) }
                ?? seat.image
            context.insert(Seat(
                id: UUID(), trainID: trainID,
                name: seat.name, carriage: seat.carriage, number: seat.number,
                image: code
            ))
        }

        try? context.save()
        reloadWidgetTimelines()
        return train
    }

    // MARK: Wire format

    private static let version: UInt8 = 0x03
    /// Links written before passenger codes carried their symbology.
    private static let versionWithoutSymbology: UInt8 = 0x02
    private static let versionMask: UInt8 = 0x7F
    private static let deflatedFlag: UInt8 = 0x80

    /// The only provider and logo strings the APIs ever produce. Sending an
    /// index instead of the text saves ten-odd characters of link each.
    private static let providers = ["trenitalia", "italo"]
    private static let logos = ["FR", "FA", "FB", "IC", "ICN", "REG", "RV", "R", "RE", "EC", "EN", "EXP", "I", "NI", "ITALO"]

    private enum IdentifierKind: Int {
        /// Anything that doesn't fit the shapes below.
        case text = 0
        /// Trenitalia's `S01700/9612/1735689600000`, split into its three numbers.
        case trenitalia = 1
        /// Italo's bare train number.
        case numeric = 2
    }

    private static func encode(_ payload: Payload) -> Data {
        var writer = ByteWriter()

        writer.table(payload.provider, in: providers)
        writer.table(payload.logo, in: logos)
        encodeIdentifier(payload, into: &writer)
        writer.string(payload.direction)

        // Times ride as minutes from the first stop, which keeps every one of
        // them to a single byte on any journey shorter than two hours.
        let base = payload.stops.first.map { epochMinutes($0.time) } ?? 0
        writer.varint(base)
        writer.varint(payload.stops.count)
        for stop in payload.stops {
            writer.string(stop.name)
            writer.string(stop.platform)
            writer.varint(max(0, epochMinutes(stop.time) - base))
            writer.byte(stop.selected ? 1 : 0)
        }

        writer.varint(payload.seats.count)
        for seat in payload.seats {
            writer.string(seat.name)
            writer.string(seat.carriage)
            writer.string(seat.number)
            writer.string(seat.qr ?? "")
            writer.byte(UInt8(seat.symbology.rawValue))
            writer.blob(seat.image ?? Data())
        }

        return writer.data
    }

    private static func decode(_ raw: Data) -> Payload? {
        guard let marker = raw.first else { return nil }
        let carriesSymbology = (marker & versionMask) >= version
        var body = raw.dropFirst()
        if marker & deflatedFlag != 0 {
            guard let inflated = try? (Data(body) as NSData).decompressed(using: .zlib) as Data else { return nil }
            body = inflated[...]
        }

        var reader = ByteReader(Data(body))
        guard let provider = reader.table(providers),
              let logo = reader.table(logos),
              let identity = decodeIdentifier(&reader),
              let direction = reader.string(),
              let base = reader.varint(),
              let stopCount = reader.varint(), stopCount >= 0, stopCount < 1024
        else { return nil }

        var stops: [Payload.Stop] = []
        stops.reserveCapacity(stopCount)
        for _ in 0..<stopCount {
            guard let name = reader.string(),
                  let platform = reader.string(),
                  let delta = reader.varint(),
                  let selected = reader.byte()
            else { return nil }
            stops.append(Payload.Stop(
                name: name, platform: platform,
                time: Date(timeIntervalSince1970: TimeInterval(base + delta) * 60),
                selected: selected != 0
            ))
        }

        guard let seatCount = reader.varint(), seatCount >= 0, seatCount < 1024 else { return nil }
        var seats: [Payload.Seat] = []
        seats.reserveCapacity(seatCount)
        for _ in 0..<seatCount {
            guard let name = reader.string(),
                  let carriage = reader.string(),
                  let number = reader.string(),
                  let qr = reader.string()
            else { return nil }

            var symbology = QRCodePayload.Symbology.qr
            var image: Data?
            if carriesSymbology {
                guard let raw = reader.byte(), let read = reader.blob() else { return nil }
                symbology = QRCodePayload.Symbology(rawValue: Int(raw)) ?? .qr
                image = read.isEmpty ? nil : read
            }

            seats.append(Payload.Seat(
                name: name, carriage: carriage, number: number,
                qr: qr.isEmpty ? nil : qr,
                symbology: symbology,
                image: image
            ))
        }

        return Payload(
            logo: logo, number: identity.number, identifier: identity.identifier,
            provider: provider, direction: direction, stops: stops, seats: seats
        )
    }

    /// Deflated JSON, as shared by versions before the packed format.
    private static func decodeLegacy(_ raw: Data) -> Payload? {
        guard let json = try? (raw as NSData).decompressed(using: .zlib) as Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Payload.self, from: json)
    }

    // MARK: Identifier packing

    /// Packs the identifier into numbers when it has a shape we recognise, and
    /// only when unpacking reproduces the original string exactly — a malformed
    /// or unfamiliar identifier falls back to plain text rather than corrupting.
    private static func encodeIdentifier(_ payload: Payload, into writer: inout ByteWriter) {
        if let packed = trenitaliaParts(payload.identifier) {
            writer.varint(IdentifierKind.trenitalia.rawValue)
            writer.varint(packed.station)
            writer.varint(packed.number)
            writer.varint(packed.minutes)
            writer.implicit(payload.number, matches: String(packed.number))
            return
        }

        if let numeric = Int(payload.identifier),
           numeric >= 0, String(numeric) == payload.identifier {
            writer.varint(IdentifierKind.numeric.rawValue)
            writer.varint(numeric)
            writer.implicit(payload.number, matches: payload.identifier)
            return
        }

        writer.varint(IdentifierKind.text.rawValue)
        writer.string(payload.identifier)
        writer.string(payload.number)
    }

    private static func decodeIdentifier(_ reader: inout ByteReader) -> (identifier: String, number: String)? {
        guard let rawKind = reader.varint(), let kind = IdentifierKind(rawValue: rawKind) else { return nil }

        switch kind {
        case .trenitalia:
            guard let station = reader.varint(),
                  let number = reader.varint(),
                  let minutes = reader.varint(),
                  let explicit = reader.implicit(String(number))
            else { return nil }
            return (trenitaliaIdentifier(station: station, number: number, minutes: minutes), explicit)

        case .numeric:
            guard let value = reader.varint(), let explicit = reader.implicit(String(value)) else { return nil }
            return (String(value), explicit)

        case .text:
            guard let identifier = reader.string(), let number = reader.string() else { return nil }
            return (identifier, number)
        }
    }

    /// `S01700/9612/1735689600000` → station 1700, train 9612, and the day as
    /// epoch minutes. Returns nil unless the round trip is lossless.
    private static func trenitaliaParts(_ identifier: String) -> (station: Int, number: Int, minutes: Int)? {
        let parts = identifier.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].first == "S",
              let station = Int(parts[0].dropFirst()),
              let number = Int(parts[1]),
              let milliseconds = Int(parts[2]),
              station >= 0, number >= 0, milliseconds >= 0,
              milliseconds % 60_000 == 0
        else { return nil }

        let packed = (station: station, number: number, minutes: milliseconds / 60_000)
        guard trenitaliaIdentifier(station: packed.station, number: packed.number, minutes: packed.minutes) == identifier
        else { return nil }
        return packed
    }

    private static func trenitaliaIdentifier(station: Int, number: Int, minutes: Int) -> String {
        "S\(String(format: "%05d", station))/\(number)/\(minutes * 60_000)"
    }

    private static func epochMinutes(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded())
    }

    // MARK: Byte plumbing

    private struct ByteWriter {
        var data = Data()

        mutating func byte(_ value: UInt8) { data.append(value) }

        mutating func varint(_ value: Int) {
            var remaining = UInt64(max(0, value))
            while remaining >= 0x80 {
                data.append(UInt8(remaining & 0x7F) | 0x80)
                remaining >>= 7
            }
            data.append(UInt8(remaining))
        }

        mutating func string(_ value: String) {
            let bytes = Array(value.utf8)
            varint(bytes.count)
            data.append(contentsOf: bytes)
        }

        /// Length-prefixed raw bytes, for the rare shared ticket image.
        mutating func blob(_ value: Data) {
            varint(value.count)
            data.append(value)
        }

        /// A known value goes out as its index; anything else as `0` plus the text.
        mutating func table(_ value: String, in table: [String]) {
            if let index = table.firstIndex(of: value) {
                varint(index + 1)
            } else {
                varint(0)
                string(value)
            }
        }

        /// Skips a field entirely when it repeats something already on the wire.
        mutating func implicit(_ value: String, matches derived: String) {
            if value == derived {
                byte(1)
            } else {
                byte(0)
                string(value)
            }
        }
    }

    private struct ByteReader {
        private let data: Data
        private var index: Data.Index

        init(_ data: Data) {
            self.data = data
            self.index = data.startIndex
        }

        mutating func byte() -> UInt8? {
            guard index < data.endIndex else { return nil }
            defer { index = data.index(after: index) }
            return data[index]
        }

        mutating func varint() -> Int? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while let current = byte() {
                result |= UInt64(current & 0x7F) << shift
                if current & 0x80 == 0 { return Int(exactly: result) }
                shift += 7
                if shift > 56 { return nil }
            }
            return nil
        }

        mutating func string() -> String? {
            guard let count = varint(), count >= 0,
                  let end = data.index(index, offsetBy: count, limitedBy: data.endIndex)
            else { return nil }
            defer { index = end }
            return String(decoding: data[index..<end], as: UTF8.self)
        }

        mutating func blob() -> Data? {
            guard let count = varint(), count >= 0,
                  let end = data.index(index, offsetBy: count, limitedBy: data.endIndex)
            else { return nil }
            defer { index = end }
            return Data(data[index..<end])
        }

        mutating func table(_ table: [String]) -> String? {
            guard let code = varint() else { return nil }
            guard code > 0 else { return string() }
            guard code <= table.count else { return nil }
            return table[code - 1]
        }

        mutating func implicit(_ derived: String) -> String? {
            guard let flag = byte() else { return nil }
            return flag == 1 ? derived : string()
        }
    }

    // MARK: base64url

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(fromBase64URL string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
