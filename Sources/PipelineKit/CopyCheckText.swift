import CoreFoundation
import Foundation

// Deliberately conservative lexical checks; these cannot establish semantic truth or recognise every locale.
enum CopyTextChecks {
    private static let banned = [
        "hidden gem", "must-see", "must-visit", "bustling", "nestled", "vibrant", "breathtaking", "boasts",
        "unforgettable", "immerse yourself", "a feast for the senses", "something for everyone", "look no further"
    ]
    private static let numbers: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
        "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12",
        "thirteen": "13", "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30", "forty": "40",
        "fifty": "50", "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
        "hundred": "100", "thousand": "1000"
    ]
    private static let numberWord = #"(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|"#
        + #"thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|"#
        + #"seventy|eighty|ninety|hundred|thousand|million|billion|first|second|third|fourth|fifth|sixth|"#
        + #"seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|"#
        + #"eighteenth|nineteenth|twentieth|thirtieth|fortieth|fiftieth|sixtieth|seventieth|eightieth|ninetieth|"#
        + #"hundredth|thousandth|millionth|billionth)"#
    private static let numberPattern = #"(?<![\p{L}\p{N}_])(?:[£$€]\s*)?\d+(?:[.,:/-]\d+)*(?:st|nd|rd|th)?%?"#
        + #"(?![\p{L}\p{N}_])|(?<![\p{L}\p{N}_])"# + numberWord
        + #"(?:(?:[\s\p{Pd}]+|\s+and\s+)"# + numberWord + #")*(?![\p{L}\p{N}_])"#

    // swiftlint:disable:next cyclomatic_complexity
    static func check(_ fields: [CopyField], input: String) -> [CopyCheckIssue] {
        var issues: [CopyCheckIssue] = []
        let inputNumbers = Set(groundingValues(input).map { splitTimeRanges(splitDateTimes($0)) }
            .flatMap { matches(numberPattern, $0) }.map(normalNumber))
        let iconicAllowed = containsIconicFact(input)
        var exclamations = 0
        var hearts = 0
        for field in fields {
            let text = field.text
            let words = matches(#"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#, text).count
            if words < field.minWords || words > field.maxWords {
                issues.append(.init(kind: .wordLimit(min: field.minWords, max: field.maxWords),
                                    path: field.path, text: text))
            }
            let sentences = sentenceParts(text)
            if sentences.count < field.minSentences || sentences.count > field.maxSentences {
                issues.append(.init(kind: .sentenceLimit(min: field.minSentences, max: field.maxSentences),
                                    path: field.path, text: text))
            }
            let normalizedText = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\p{Pd}"#, with: "-", options: .regularExpression)
            for phrase in banned where !matches(
                #"(?<!\p{L})"# + NSRegularExpression.escapedPattern(for: phrase) + #"(?!\p{L})"#, normalizedText
            ).isEmpty {
                issues.append(.init(kind: .bannedPhrase(phrase), path: field.path, text: text))
            }
            if !matches(#"\bwhether\s+you['’]re\b[\s\S]*?\bor\b"#, text).isEmpty {
                issues.append(.init(kind: .bannedPhrase("whether you're … or …"), path: field.path, text: text))
            }
            if !iconicAllowed && !matches(#"\biconic\b"#, text).isEmpty {
                issues.append(.init(kind: .bannedPhrase("iconic"), path: field.path, text: text))
            }
            for _ in matches(#"\bin the heart of\b"#, text) {
                hearts += 1
                if hearts > 1 {
                    issues.append(.init(kind: .bannedPhrase("in the heart of"), path: field.path, text: text))
                }
            }
            if text.contains(where: isEmoji) { issues.append(.init(kind: .emoji, path: field.path, text: text)) }
            for character in text where character == "!" {
                exclamations += 1
                if exclamations > 1 { issues.append(.init(kind: .exclamationLimit, path: field.path, text: text)) }
            }
            for sentence in sentences {
                for claim in matches(numberPattern, splitTimeRanges(sentence))
                where !inputNumbers.contains(normalNumber(claim)) && !ordinals.contains(claim.lowercased()) {
                    issues.append(.init(kind: .ungroundedNumber(claim), path: field.path, text: sentence))
                }
            }
        }
        return issues
    }

    /// Booking times arrive as ISO local date-times (`2025-11-25T18:52`). The `T` would make the whole value
    /// one token that grounds neither the date nor the time, so it becomes a space first.
    private static func splitDateTimes(_ value: String) -> String {
        value.replacingOccurrences(of: #"(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})"#, with: "$1 $2",
                                   options: .regularExpression)
    }

    /// Opening hours arrive as ranges (`10:00-21:00`). The hyphen would make the range one token that grounds
    /// neither time, so the closing time could never be mentioned. Ranges become two times, in the input and in the
    /// copy.
    private static func splitTimeRanges(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?<!\d)(\d{1,2}:\d{2})\s*[-\p{Pd}]\s*(\d{1,2}:\d{2})(?!\d)"#, with: "$1 $2",
                                   options: .regularExpression)
    }

    /// Ordinals that order things in the copy ("a second stop", "the first day") rather than state a fact.
    private static let ordinals: Set<String> = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"
    ]

    /// A number as digits when it can be: "ten" is 10, and "twenty-one" or "forty five" is 21 or 45.
    private static func normalNumber(_ value: String) -> String {
        let lower = value.lowercased()
        if let digits = numbers[lower] { return digits }
        let parts = lower.split { !$0.isLetter }.map(String.init)
        if parts.count == 2, let tens = numbers[parts[0]].flatMap(Int.init),
           let units = numbers[parts[1]].flatMap(Int.init),
           (20...90).contains(tens), tens % 10 == 0, (1...9).contains(units) {
            return String(tens + units)
        }
        return lower.replacingOccurrences(of: " ", with: "")
    }

    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        // Digits, # and * have the Emoji property for keycaps but are not emoji on their own.
        return scalars.contains {
            $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 127)
                || $0.value == 0xFE0F || $0.value == 0x20E3
        }
    }

    private static func sentenceParts(_ text: String) -> [String] {
        // A dot inside a decimal is not a sentence boundary. Unterminated text still counts as one sentence.
        matches(#"(?:[^.!?]|(?<=\d)\.(?=\d))+[.!?]*(?=\s|$)"#, text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func matches(_ pattern: String, _ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    // Values only: keys and identifier fields cannot support a numerical claim. Dates, times,
    // prices, percentages and compound number words are indivisible tokens; shorter forms need
    // their own evidence. Invalid JSON provides no evidence. This is not semantic verification.
    private static func groundingValues(_ input: String) -> [String] {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        func collect(_ value: Any) -> [String] {
            if let text = value as? String { return [text] }
            if let number = value as? NSNumber {
                return CFGetTypeID(number) == CFBooleanGetTypeID() ? [] : [number.stringValue]
            }
            if let array = value as? [Any] { return array.flatMap(collect) }
            if let object = value as? [String: Any] {
                return object.flatMap { key, value in
                    let identifier = key == "id" || key == "ids" || key.hasSuffix("ID") || key.hasSuffix("IDs")
                        || key.hasSuffix("Id") || key.hasSuffix("Ids") || key.hasSuffix("_id")
                        || key.hasSuffix("_ids")
                    return identifier ? [] : collect(value)
                }
            }
            return []
        }
        return collect(json)
    }

    private static func containsIconicFact(_ input: String) -> Bool {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        func affirmative(_ text: String) -> Bool {
            sentenceParts(text).contains { sentence in
                !matches(#"\biconic\b"#, sentence).isEmpty
                    && matches(#"\b(?:not|never|no|isn['’]t|wasn['’]t)\b[^.!?]*\biconic\b"#, sentence).isEmpty
            }
        }
        func fact(_ value: Any) -> Bool {
            if let text = value as? String { return affirmative(text) }
            if let array = value as? [Any] { return array.contains(where: fact) }
            if let object = value as? [String: Any] {
                return ["text", "statement"].contains { key in
                    (object[key] as? String).map(affirmative) ?? false
                }
            }
            return false
        }
        func search(_ value: Any) -> Bool {
            if let array = value as? [Any] { return array.contains(where: search) }
            if let object = value as? [String: Any] {
                return object.contains { key, value in key == "facts" ? fact(value) : search(value) }
            }
            return false
        }
        return search(json)
    }
}
