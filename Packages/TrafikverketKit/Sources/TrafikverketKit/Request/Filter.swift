import Foundation

/// A filter expression for a Trafikverket query. Composes into the `<FILTER>` element.
///
/// Values are XML-escaped when rendered. Date values can use API functions such as
/// `$now` and `$dateadd(-0.00:15:00)` — pass them as plain strings.
public indirect enum Filter: Sendable, Hashable {
    case equal(String, String)
    case notEqual(String, String)
    case greaterThan(String, String)
    case greaterThanOrEqual(String, String)
    case lessThan(String, String)
    case lessThanOrEqual(String, String)
    case like(String, String)
    case notLike(String, String)
    case `in`(String, [String])
    case notIn(String, [String])
    case exists(String, Bool)
    /// Spatial: `WITHIN name shape="center" radius="500m" value="POINT (lon lat)"`.
    case within(name: String, shape: String, radius: String, value: String)
    case intersects(name: String, value: String)
    case near(name: String, value: String, minDistance: String?, maxDistance: String?)
    case elementMatch([Filter])
    case and([Filter])
    case or([Filter])
    case not([Filter])

    // MARK: Convenience constructors that accept API-typed values.

    public static func equal(_ name: String, _ value: Bool) -> Filter {
        .equal(name, value ? "true" : "false")
    }

    public static func equal(_ name: String, _ value: Int) -> Filter {
        .equal(name, String(value))
    }

    /// Filters a datetime field with a Swedish-civil-time literal.
    public static func equal(_ name: String, date: Date) -> Filter {
        .equal(name, SwedishTime.dateTimeString(date))
    }

    public static func greaterThan(_ name: String, date: Date) -> Filter {
        .greaterThan(name, SwedishTime.dateTimeString(date))
    }

    public static func greaterThanOrEqual(_ name: String, date: Date) -> Filter {
        .greaterThanOrEqual(name, SwedishTime.dateTimeString(date))
    }

    public static func lessThan(_ name: String, date: Date) -> Filter {
        .lessThan(name, SwedishTime.dateTimeString(date))
    }

    public static func lessThanOrEqual(_ name: String, date: Date) -> Filter {
        .lessThanOrEqual(name, SwedishTime.dateTimeString(date))
    }

    // MARK: Rendering

    func render(into output: inout String, indent: Int) {
        let pad = String(repeating: " ", count: indent)
        switch self {
        case let .equal(n, v): output += "\(pad)<EQ name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .notEqual(n, v): output += "\(pad)<NE name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .greaterThan(n, v): output += "\(pad)<GT name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .greaterThanOrEqual(n, v): output += "\(pad)<GTE name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .lessThan(n, v): output += "\(pad)<LT name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .lessThanOrEqual(n, v): output += "\(pad)<LTE name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .like(n, v): output += "\(pad)<LIKE name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .notLike(n, v): output += "\(pad)<NOTLIKE name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .in(n, vs): output += "\(pad)<IN name=\"\(n.xmlEscaped)\" value=\"\(vs.joined(separator: ",").xmlEscaped)\" />\n"
        case let .notIn(n, vs): output += "\(pad)<NOTIN name=\"\(n.xmlEscaped)\" value=\"\(vs.joined(separator: ",").xmlEscaped)\" />\n"
        case let .exists(n, v): output += "\(pad)<EXISTS name=\"\(n.xmlEscaped)\" value=\"\(v ? "true" : "false")\" />\n"
        case let .within(n, shape, radius, v):
            output += "\(pad)<WITHIN name=\"\(n.xmlEscaped)\" shape=\"\(shape.xmlEscaped)\" "
            output += "radius=\"\(radius.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .intersects(n, v): output += "\(pad)<INTERSECTS name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\" />\n"
        case let .near(n, v, minD, maxD):
            var attrs = "name=\"\(n.xmlEscaped)\" value=\"\(v.xmlEscaped)\""
            if let minD {
                attrs += " mindistance=\"\(minD.xmlEscaped)\""
            }
            if let maxD {
                attrs += " maxdistance=\"\(maxD.xmlEscaped)\""
            }
            output += "\(pad)<NEAR \(attrs) />\n"
        case let .elementMatch(children): renderGroup("ELEMENTMATCH", children, into: &output, indent: indent)
        case let .and(children): renderGroup("AND", children, into: &output, indent: indent)
        case let .or(children): renderGroup("OR", children, into: &output, indent: indent)
        case let .not(children): renderGroup("NOT", children, into: &output, indent: indent)
        }
    }

    private func renderGroup(_ tag: String, _ children: [Filter], into output: inout String, indent: Int) {
        let pad = String(repeating: " ", count: indent)
        output += "\(pad)<\(tag)>\n"
        for child in children {
            child.render(into: &output, indent: indent + 2)
        }
        output += "\(pad)</\(tag)>\n"
    }
}
