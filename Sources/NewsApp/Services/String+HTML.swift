import Foundation

extension String {
    func strippingHTML() -> String {
        let withoutTags = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags.decodingHTMLEntities().sanitizingProblematicCharacters().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fast HTML entity decoding without WebKit initialization.
    /// Handles common named entities and numeric character references.
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }

        var result = self

        // Decode numeric character references (&#123; or &#x7B;)
        result = result.decodingNumericEntities()

        // Decode common named entities
        for (entity, char) in String.htmlEntityMap {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        return result
    }

    /// Removes problematic Unicode characters that cause display issues.
    func sanitizingProblematicCharacters() -> String {
        var result = self

        // Remove Unicode replacement character and other problematic sequences
        result = result.replacingOccurrences(of: "\u{FFFD}", with: "") // Replacement character
        result = result.replacingOccurrences(of: "\u{25CA}", with: "") // Lozenge (◊)

        // Remove isolated surrogate halves and other invalid sequences
        result = result.unicodeScalars
            .filter { scalar in
                // Keep valid Unicode scalars, filter out surrogates and specials
                let value = scalar.value
                // Filter out surrogate range (shouldn't appear in valid UTF-8)
                if value >= 0xD800 && value <= 0xDFFF { return false }
                // Filter out private use area placeholders that render as boxes
                if value >= 0xE000 && value <= 0xF8FF { return false }
                // Filter out specials block except for valid characters
                if value >= 0xFFF0 && value <= 0xFFFF && value != 0xFFFC { return false }
                return true
            }
            .map { String($0) }
            .joined()

        // Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result
    }

    private func decodingNumericEntities() -> String {
        var result = ""
        var index = startIndex

        while index < endIndex {
            if self[index] == "&" {
                let remaining = self[index...]

                // Try to match &#xHEX; or &#DECIMAL;
                if remaining.hasPrefix("&#") {
                    if let semicolonIdx = remaining.firstIndex(of: ";"),
                       semicolonIdx > remaining.index(remaining.startIndex, offsetBy: 2) {
                        let content = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<semicolonIdx]
                        var codePoint: UInt32?

                        if content.hasPrefix("x") || content.hasPrefix("X") {
                            // Hex: &#x7B;
                            let hex = String(content.dropFirst())
                            codePoint = UInt32(hex, radix: 16)
                        } else {
                            // Decimal: &#123;
                            codePoint = UInt32(content)
                        }

                        if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                            result.append(Character(scalar))
                            index = self.index(after: semicolonIdx)
                            continue
                        }
                    }
                }
            }

            result.append(self[index])
            index = self.index(after: index)
        }

        return result
    }

    private static let htmlEntityMap: [String: String] = [
        // Common entities
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&apos;": "'",
        "&nbsp;": " ",

        // Punctuation
        "&ndash;": "–",
        "&mdash;": "—",
        "&lsquo;": "'",
        "&rsquo;": "'",
        "&ldquo;": "\u{201C}",
        "&rdquo;": "\u{201D}",
        "&hellip;": "…",
        "&bull;": "•",
        "&middot;": "·",
        "&copy;": "©",
        "&reg;": "®",
        "&trade;": "™",
        "&deg;": "°",
        "&plusmn;": "±",
        "&times;": "×",
        "&divide;": "÷",
        "&frac12;": "½",
        "&frac14;": "¼",
        "&frac34;": "¾",
        "&cent;": "¢",
        "&pound;": "£",
        "&euro;": "€",
        "&yen;": "¥",
        "&sect;": "§",
        "&para;": "¶",
        "&dagger;": "†",
        "&Dagger;": "‡",

        // Accented characters
        "&Aacute;": "Á",
        "&aacute;": "á",
        "&Agrave;": "À",
        "&agrave;": "à",
        "&Acirc;": "Â",
        "&acirc;": "â",
        "&Atilde;": "Ã",
        "&atilde;": "ã",
        "&Auml;": "Ä",
        "&auml;": "ä",
        "&Aring;": "Å",
        "&aring;": "å",
        "&AElig;": "Æ",
        "&aelig;": "æ",
        "&Ccedil;": "Ç",
        "&ccedil;": "ç",
        "&Eacute;": "É",
        "&eacute;": "é",
        "&Egrave;": "È",
        "&egrave;": "è",
        "&Ecirc;": "Ê",
        "&ecirc;": "ê",
        "&Euml;": "Ë",
        "&euml;": "ë",
        "&Iacute;": "Í",
        "&iacute;": "í",
        "&Igrave;": "Ì",
        "&igrave;": "ì",
        "&Icirc;": "Î",
        "&icirc;": "î",
        "&Iuml;": "Ï",
        "&iuml;": "ï",
        "&Ntilde;": "Ñ",
        "&ntilde;": "ñ",
        "&Oacute;": "Ó",
        "&oacute;": "ó",
        "&Ograve;": "Ò",
        "&ograve;": "ò",
        "&Ocirc;": "Ô",
        "&ocirc;": "ô",
        "&Otilde;": "Õ",
        "&otilde;": "õ",
        "&Ouml;": "Ö",
        "&ouml;": "ö",
        "&Oslash;": "Ø",
        "&oslash;": "ø",
        "&OElig;": "Œ",
        "&oelig;": "œ",
        "&szlig;": "ß",
        "&Uacute;": "Ú",
        "&uacute;": "ú",
        "&Ugrave;": "Ù",
        "&ugrave;": "ù",
        "&Ucirc;": "Û",
        "&ucirc;": "û",
        "&Uuml;": "Ü",
        "&uuml;": "ü",
        "&Yacute;": "Ý",
        "&yacute;": "ý",
        "&Yuml;": "Ÿ",
        "&yuml;": "ÿ",

        // Greek letters (common)
        "&Alpha;": "Α",
        "&alpha;": "α",
        "&Beta;": "Β",
        "&beta;": "β",
        "&Gamma;": "Γ",
        "&gamma;": "γ",
        "&Delta;": "Δ",
        "&delta;": "δ",
        "&pi;": "π",
        "&Pi;": "Π",
        "&sigma;": "σ",
        "&Sigma;": "Σ",
        "&omega;": "ω",
        "&Omega;": "Ω",

        // Math/symbols
        "&infin;": "∞",
        "&ne;": "≠",
        "&le;": "≤",
        "&ge;": "≥",
        "&sum;": "∑",
        "&prod;": "∏",
        "&radic;": "√",
        "&part;": "∂",
        "&int;": "∫",
        "&permil;": "‰",
        "&prime;": "′",
        "&Prime;": "″",

        // Arrows
        "&larr;": "←",
        "&rarr;": "→",
        "&uarr;": "↑",
        "&darr;": "↓",
        "&harr;": "↔",

        // Misc
        "&laquo;": "«",
        "&raquo;": "»",
        "&iexcl;": "¡",
        "&iquest;": "¿",
        "&shy;": "\u{00AD}",
        "&zwj;": "\u{200D}",
        "&zwnj;": "\u{200C}",
    ]
}
