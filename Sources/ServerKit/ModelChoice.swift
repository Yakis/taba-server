import Foundation

/// One model a traveller can pick. `id` is the provider's slug, sent back with the trip.
public struct ModelOption: Codable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// What the server offers the traveller, and the model a trip uses when it names none.
public protocol TripModelCatalog: Sendable {
    var defaultModel: String { get }
    /// The models a traveller may pick now. Always includes the default model.
    func options() async -> [ModelOption]
}

/// Offline replay mode has no account to ask, so the only model offered is the default one.
public struct FixedModelCatalog: TripModelCatalog {
    public let defaultModel: String

    public init(defaultModel: String) {
        self.defaultModel = defaultModel
    }

    public func options() async -> [ModelOption] {
        [ModelChoice.option(for: defaultModel)]
    }
}

/// Picks the models the app offers from the plan's slugs. Slugs look like `gpt-<version>-<family>`.
public enum ModelChoice {
    /// The families the picker offers, in the order it shows them.
    public static let families = ["sol", "terra", "luna"]

    /// For each family, the slug with the highest version. A family with no slug is left out.
    public static func options(fromSlugs slugs: [String]) -> [ModelOption] {
        families.compactMap { family in
            let candidates = slugs.compactMap { slug -> (slug: String, version: [Int])? in
                guard let parsed = parse(slug), parsed.family == family else { return nil }
                return (slug, parsed.version)
            }
            guard let best = candidates.max(by: { isLower($0.version, than: $1.version) }) else { return nil }
            return option(for: best.slug)
        }
    }

    /// True when the slug has the shape the picker offers: `gpt-<version>-sol`, `-terra` or `-luna`.
    public static func isWellFormed(_ slug: String) -> Bool {
        guard let parsed = parse(slug) else { return false }
        return families.contains(parsed.family)
    }

    /// The picker entry for one slug: its family name when the slug has one, otherwise the slug itself.
    public static func option(for slug: String) -> ModelOption {
        guard let parsed = parse(slug) else { return ModelOption(id: slug, name: slug) }
        let name = parsed.family.prefix(1).uppercased() + parsed.family.dropFirst()
        return ModelOption(id: slug, name: name)
    }

    /// Splits `gpt-<version>-<family>` exactly. The version is plain digits separated by dots.
    static func parse(_ slug: String) -> (version: [Int], family: String)? {
        let parts = slug.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "gpt", !parts[2].isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts[1].split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        return (numbers, String(parts[2]))
    }

    /// Compares versions number by number, so 6.10 is higher than 6.9 and a missing part counts as zero.
    static func isLower(_ lhs: [Int], than rhs: [Int]) -> Bool {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
