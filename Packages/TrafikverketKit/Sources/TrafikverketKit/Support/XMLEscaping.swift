import Foundation

extension String {
    /// Escapes the five XML special characters so the value is safe inside an attribute or text node.
    var xmlEscaped: String {
        var result = ""
        result.reserveCapacity(utf8.count)
        for scalar in unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
