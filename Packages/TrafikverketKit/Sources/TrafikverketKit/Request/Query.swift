import Foundation

/// Describes a Trafikverket object type: name, namespace and schema version.
public protocol TRVObject: Decodable, Sendable {
    static var objectType: String { get }
    static var namespace: String? { get }
    static var schemaVersion: String { get }
}

/// Sort direction for `orderby`.
public enum SortOrder: String, Sendable {
    case ascending = "asc"
    case descending = "desc"
}

public struct Sort: Sendable, Hashable {
    public var field: String
    public var order: SortOrder

    public init(_ field: String, _ order: SortOrder = .ascending) {
        self.field = field
        self.order = order
    }

    var rendered: String {
        "\(field) \(order.rawValue)"
    }
}

/// A single `<QUERY>` element. Build with the fluent modifiers, then hand it to ``TrafikverketClient``.
public struct Query<Object: TRVObject>: Sendable {
    public var filter: Filter?
    public var includes: [String] = []
    public var excludes: [String] = []
    public var limit: Int?
    public var skip: Int?
    public var orderBy: [Sort] = []
    public var includeDeleted = false
    public var lastModified = false
    /// Pass `"0"` for a full snapshot, then the `LASTCHANGEID` from the previous response for deltas.
    public var changeID: String?
    /// Ask the API to return a Server-Sent-Events URL for live updates matching this query.
    public var sseURL = false
    public var distinct: String?

    public init() {}

    public func filter(_ filter: Filter) -> Query {
        var q = self; q.filter = filter; return q
    }

    public func filter(_ filters: Filter...) -> Query {
        filter(.and(filters))
    }

    public func include(_ fields: String...) -> Query {
        var q = self; q.includes += fields; return q
    }

    public func include(_ fields: [String]) -> Query {
        var q = self; q.includes += fields; return q
    }

    public func exclude(_ fields: String...) -> Query {
        var q = self; q.excludes += fields; return q
    }

    public func limit(_ n: Int) -> Query {
        var q = self; q.limit = n; return q
    }

    public func skip(_ n: Int) -> Query {
        var q = self; q.skip = n; return q
    }

    public func orderBy(_ sorts: Sort...) -> Query {
        var q = self; q.orderBy += sorts; return q
    }

    public func includeDeleted(_ v: Bool = true) -> Query {
        var q = self; q.includeDeleted = v; return q
    }

    public func lastModified(_ v: Bool = true) -> Query {
        var q = self; q.lastModified = v; return q
    }

    public func changeID(_ id: String?) -> Query {
        var q = self; q.changeID = id; return q
    }

    public func sseURL(_ v: Bool = true) -> Query {
        var q = self; q.sseURL = v; return q
    }

    public func distinct(_ field: String) -> Query {
        var q = self; q.distinct = field; return q
    }

    /// Renders the `<QUERY>` element (without the surrounding `<REQUEST>`/`<LOGIN>`).
    public func renderXML(indent: Int = 2) -> String {
        let pad = String(repeating: " ", count: indent)
        var attrs = "objecttype=\"\(Object.objectType)\" schemaversion=\"\(Object.schemaVersion)\""
        if let ns = Object.namespace {
            attrs += " namespace=\"\(ns.xmlEscaped)\""
        }
        if let limit {
            attrs += " limit=\"\(limit)\""
        }
        if let skip {
            attrs += " skip=\"\(skip)\""
        }
        if !orderBy.isEmpty {
            attrs += " orderby=\"\(orderBy.map(\.rendered).joined(separator: ", ").xmlEscaped)\""
        }
        if includeDeleted {
            attrs += " includedeletedobjects=\"true\""
        }
        if lastModified {
            attrs += " lastmodified=\"true\""
        }
        if let changeID {
            attrs += " changeid=\"\(changeID.xmlEscaped)\""
        }
        if sseURL {
            attrs += " sseurl=\"true\""
        }

        var out = "\(pad)<QUERY \(attrs)>\n"
        if let filter {
            out += "\(pad)  <FILTER>\n"
            filter.render(into: &out, indent: indent + 4)
            out += "\(pad)  </FILTER>\n"
        }
        for field in includes {
            out += "\(pad)  <INCLUDE>\(field.xmlEscaped)</INCLUDE>\n"
        }
        for field in excludes {
            out += "\(pad)  <EXCLUDE>\(field.xmlEscaped)</EXCLUDE>\n"
        }
        if let distinct {
            out += "\(pad)  <DISTINCT>\(distinct.xmlEscaped)</DISTINCT>\n"
        }
        out += "\(pad)</QUERY>\n"
        return out
    }
}

/// Renders a complete `<REQUEST>` document with the login element and one or more queries.
public enum RequestDocument {
    public static func render(apiKey: String, queries: [String]) -> String {
        var out = "<REQUEST>\n  <LOGIN authenticationkey=\"\(apiKey.xmlEscaped)\" />\n"
        for q in queries {
            out += q
        }
        out += "</REQUEST>\n"
        return out
    }
}
