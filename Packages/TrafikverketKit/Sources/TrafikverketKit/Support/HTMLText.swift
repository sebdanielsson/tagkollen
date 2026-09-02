import Foundation

/// Some free-text fields (notably `TrainStation.LocationInformationText`) contain HTML fragments:
/// `<br>`, `<div>` wrappers and `<a href>` links. These helpers turn them into plain text or Markdown.
public extension String {
    /// Converts an HTML fragment to inline Markdown: line breaks become newlines, anchors become
    /// `[text](url)`, every other tag is dropped and common entities are decoded.
    var htmlToMarkdown: String {
        var text = self
        // <a href="url" ...>text</a> → [text](url)
        let anchor = try? NSRegularExpression(
            pattern: #"<a\b[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        if let anchor {
            text = anchor.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[$2]($1)"
            )
        }
        text = text.replacingOccurrences(
            of: #"<\s*br\s*/?\s*>|</\s*(p|div|li|h[1-6])\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.decodingHTMLEntities
        // Collapse runs of spaces and stray whitespace around newlines.
        text = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #" *\n+ *"#, with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain text: like ``htmlToMarkdown`` but with link text only.
    var strippingHTML: String {
        htmlToMarkdown.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression
        )
    }

    /// True when the string contains something that looks like an HTML tag or entity.
    var containsHTML: Bool {
        range(of: #"<[a-zA-Z/][^>]*>|&[a-zA-Z#0-9]+;"#, options: .regularExpression) != nil
    }

    var decodingHTMLEntities: String {
        var text = self
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": "\u{00A0}", "&aring;": "å", "&auml;": "ä", "&ouml;": "ö", "&Aring;": "Å", "&Auml;": "Ä", "&Ouml;": "Ö",
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        if let numeric = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            let matches = numeric.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
            for m in matches {
                guard let full = Range(m.range, in: text), let digits = Range(m.range(at: 1), in: text),
                      let code = UInt32(text[digits]), let scalar = Unicode.Scalar(code) else { continue }
                text.replaceSubrange(full, with: String(Character(scalar)))
            }
        }
        return text
    }
}

public extension TrainStation {
    /// `LocationInformationText` as Markdown (links preserved), or nil when empty.
    var informationMarkdown: String? {
        guard let raw = locationInformationText?.htmlToMarkdown, !raw.isEmpty else { return nil }
        return raw
    }
}
