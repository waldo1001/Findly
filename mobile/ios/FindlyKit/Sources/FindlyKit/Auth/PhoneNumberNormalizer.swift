import Foundation

/// specs/006-phone-auth.md §3 — pure E.164 normalization, applied to user input before any
/// provider call. Rules are identical to Android's (003 §7) so both platforms reject/accept the
/// exact same inputs.
public enum PhoneNumberNormalizer {
    private static let e164Regex: NSRegularExpression = {
        // ^\+[1-9]\d{6,14}$ (006 §3 rule 4).
        try! NSRegularExpression(pattern: "^\\+[1-9][0-9]{6,14}$")
    }()

    /// Returns the normalized E.164 number, or `nil` if the result doesn't match E.164 — the
    /// caller MUST treat `nil` as `INVALID_PHONE_NUMBER` and make no provider call.
    public static func normalize(_ input: String) -> String? {
        // 1. Strip spaces, dashes, dots, and parentheses.
        var result = input
        for character in [" ", "-", ".", "(", ")"] {
            result = result.replacingOccurrences(of: character, with: "")
        }

        // 2. A leading "00" becomes "+".
        if result.hasPrefix("00") {
            result = "+" + result.dropFirst(2)
        } else if result.hasPrefix("0") && !result.hasPrefix("+") {
            // 3. A leading single "0" with no "+" becomes "+32" + rest (Belgium-centric default).
            result = "+32" + result.dropFirst(1)
        }

        // 4. The result MUST match E.164, else reject.
        let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
        guard e164Regex.firstMatch(in: result, options: [], range: fullRange) != nil else {
            return nil
        }
        return result
    }
}
