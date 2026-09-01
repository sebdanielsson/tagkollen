import Foundation

/// Errors surfaced by ``TrafikverketClient``.
public enum TrafikverketError: Error, Sendable, Equatable, LocalizedError {
    case missingAPIKey
    case invalidAuthentication
    case api(source: String?, message: String)
    case http(status: Int)
    case decoding(String)
    case sseUnavailable
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No Trafikverket API key configured."
        case .invalidAuthentication: "The Trafikverket API rejected the API key."
        case let .api(source, message): source.map { "\($0): \(message)" } ?? message
        case let .http(status): "The server responded with HTTP \(status)."
        case let .decoding(detail): "Could not read the server response: \(detail)"
        case .sseUnavailable: "The server did not provide a live-update URL."
        case let .transport(detail): detail
        }
    }
}

/// Metadata returned alongside query results.
public struct ResponseInfo: Sendable, Hashable {
    public var lastChangeID: String?
    public var sseURL: URL?
    public var lastModified: Date?
    public var evalResult: [String: String]?
}

/// Decoded result of one query.
public struct QueryResult<Object: TRVObject>: Sendable {
    public var objects: [Object]
    public var info: ResponseInfo

    public init(objects: [Object], info: ResponseInfo) {
        self.objects = objects
        self.info = info
    }
}

/// Decodes the `{"RESPONSE":{"RESULT":[...]}}` envelope for a single object type.
enum ResponseEnvelope {
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? {
            nil
        }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    struct APIError: Decodable {
        var source: String?
        var message: String
        enum CodingKeys: String, CodingKey {
            case source = "SOURCE"
            case message = "MESSAGE"
        }
    }

    struct Info: Decodable {
        var lastChangeID: String?
        var sseURL: String?
        var lastModified: LastModified?
        var evalResult: [String: String]?

        struct LastModified: Decodable {
            var datetime: Date?
            enum CodingKeys: String, CodingKey { case datetime = "_attributes" }
            /// The API nests it as {"@datetime": "..."}; handled leniently below.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                for key in c.allKeys where key.stringValue.lowercased().contains("datetime") {
                    if let s = try? c.decode(String.self, forKey: key) {
                        datetime = TRVDateParser.parse(s)
                    }
                }
            }
        }

        enum CodingKeys: String, CodingKey {
            case lastChangeID = "LASTCHANGEID"
            case sseURL = "SSEURL"
            case lastModified = "LASTMODIFIED"
            case evalResult = "EVALRESULT"
        }
    }

    /// Decodes every result block that carries `Object.objectType`, concatenating objects.
    static func decode<Object: TRVObject>(_ data: Data, as _: Object.Type) throws -> QueryResult<Object> {
        let decoder = JSONDecoder.trafikverket
        let root: [String: [[String: LenientJSON]]]
        do {
            let top = try decoder.decode([String: [String: [[String: LenientJSON]]]].self, from: data)
            guard let response = top["RESPONSE"], let result = response["RESULT"] else {
                throw TrafikverketError.decoding("Missing RESPONSE.RESULT")
            }
            root = ["RESULT": result]
        } catch let error as TrafikverketError {
            throw error
        } catch {
            throw TrafikverketError.decoding(String(describing: error))
        }

        var objects: [Object] = []
        var info = ResponseInfo()
        for block in root["RESULT"] ?? [] {
            if let err = block["ERROR"] {
                let apiError = try decoder.decode(APIError.self, from: err.rawData)
                if apiError.source == "Security" {
                    throw TrafikverketError.invalidAuthentication
                }
                throw TrafikverketError.api(source: apiError.source, message: apiError.message)
            }
            if let list = block[Object.objectType] {
                do {
                    objects += try decoder.decode([Object].self, from: list.rawData)
                } catch {
                    throw TrafikverketError.decoding(describe(error))
                }
            }
            if let infoBlock = block["INFO"], let decoded = try? decoder.decode(Info.self, from: infoBlock.rawData) {
                info.lastChangeID = decoded.lastChangeID ?? info.lastChangeID
                info.sseURL = decoded.sseURL.flatMap(URL.init(string:)) ?? info.sseURL
                info.lastModified = decoded.lastModified?.datetime ?? info.lastModified
                info.evalResult = decoded.evalResult ?? info.evalResult
            }
        }
        return QueryResult(objects: objects, info: info)
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return String(describing: error) }
        switch decodingError {
        case let .keyNotFound(key, ctx): return "Missing key \(key.stringValue) at \(path(ctx))"
        case let .typeMismatch(type, ctx): return "Type mismatch (\(type)) at \(path(ctx)): \(ctx.debugDescription)"
        case let .valueNotFound(type, ctx): return "Missing value (\(type)) at \(path(ctx))"
        case let .dataCorrupted(ctx): return "Corrupt data at \(path(ctx)): \(ctx.debugDescription)"
        @unknown default: return String(describing: error)
        }
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map(\.stringValue).joined(separator: ".")
    }
}

/// Captures an arbitrary JSON subtree so it can be re-decoded with a concrete type later.
struct LenientJSON: Decodable {
    let rawData: Data

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        rawData = try JSONEncoder().encode(value)
    }
}

/// Minimal JSON value tree used to round-trip untyped subtrees without loss.
indirect enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case integer(Int64)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null; return
        }
        if let b = try? c.decode(Bool.self) {
            self = .bool(b); return
        }
        if let i = try? c.decode(Int64.self) {
            self = .integer(i); return
        }
        if let d = try? c.decode(Double.self) {
            self = .number(d); return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s); return
        }
        if let a = try? c.decode([JSONValue].self) {
            self = .array(a); return
        }
        if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o); return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .string(s): try c.encode(s)
        case let .number(d): try c.encode(d)
        case let .integer(i): try c.encode(i)
        case let .bool(b): try c.encode(b)
        case .null: try c.encodeNil()
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }
}
