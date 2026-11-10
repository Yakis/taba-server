import Foundation

/// One model a traveller can pick. `id` is the provider's slug, sent back with the trip. `provider` names who runs it
/// ("ChatGPT", "Claude" or "DeepSeek"), so the app can group the list.
public struct ModelOption: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let provider: String

    public init(id: String, name: String, provider: String) {
        self.id = id
        self.name = name
        self.provider = provider
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

/// The company that runs a model, decided by the model id alone.
public enum ModelProvider: String, Sendable, Equatable, CaseIterable {
    case chatGPT = "ChatGPT"
    case claude = "Claude"
    case deepSeek = "DeepSeek"

    /// `gpt-...` is ChatGPT, `claude-...` is Claude and `deepseek-...` is DeepSeek. Any other id has no provider.
    public static func of(_ model: String) -> ModelProvider? {
        if model.hasPrefix("gpt-") { return .chatGPT }
        if model.hasPrefix("claude-") { return .claude }
        if model.hasPrefix("deepseek-") { return .deepSeek }
        return nil
    }
}

/// Picks the models the app offers. ChatGPT slugs come from the plan's list and look like `gpt-<version>-<family>`.
/// Claude and DeepSeek models are fixed here, and offered only when their key is set.
public enum ModelChoice {
    /// The ChatGPT families the picker offers, in the order it shows them.
    public static let families = ["sol", "terra", "luna"]

    /// The Claude models offered when `ANTHROPIC_API_KEY` is set.
    public static let claudeOptions = [
        ModelOption(id: "claude-opus-5-5", name: "Claude Opus 5.5", provider: ModelProvider.claude.rawValue),
        ModelOption(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", provider: ModelProvider.claude.rawValue)
    ]

    /// The DeepSeek models offered when `DEEPSEEK_API_KEY` is set.
    public static let deepSeekOptions = [
        ModelOption(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: ModelProvider.deepSeek.rawValue),
        ModelOption(id: "deepseek-flash", name: "DeepSeek Flash", provider: ModelProvider.deepSeek.rawValue)
    ]

    /// The fixed options for the providers whose key is set, Claude first, then DeepSeek.
    public static func fixedOptions(anthropic: Bool, deepSeek: Bool) -> [ModelOption] {
        (anthropic ? claudeOptions : []) + (deepSeek ? deepSeekOptions : [])
    }

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

    /// True when the id has a shape a trip may name: `gpt-<version>-sol`, `-terra` or `-luna`; or a `claude-` or
    /// `deepseek-` id of at most 64 lowercase letters, digits, dots and hyphens. Whether it is offered is checked
    /// separately against the server's list.
    public static func isWellFormed(_ slug: String) -> Bool {
        if ModelProvider.of(slug) == .claude || ModelProvider.of(slug) == .deepSeek {
            return slug.utf8.count <= 64 && slug.unicodeScalars.allSatisfy(isProviderIDCharacter)
        }
        guard let parsed = parse(slug) else { return false }
        return families.contains(parsed.family)
    }

    /// The picker entry for one id: its fixed entry for Claude and DeepSeek, its family name for ChatGPT, otherwise
    /// the id itself. The provider is always set, and `Other` when no provider runs the id.
    public static func option(for slug: String) -> ModelOption {
        if let fixed = (claudeOptions + deepSeekOptions).first(where: { $0.id == slug }) {
            return fixed
        }
        let provider = ModelProvider.of(slug)?.rawValue ?? "Other"
        guard let parsed = parse(slug) else { return ModelOption(id: slug, name: slug, provider: provider) }
        let name = parsed.family.prefix(1).uppercased() + parsed.family.dropFirst()
        return ModelOption(id: slug, name: name, provider: provider)
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

    private static func isProviderIDCharacter(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x61 && scalar.value <= 0x7A)
            || (scalar.value >= 0x30 && scalar.value <= 0x39)
            || scalar == "." || scalar == "-"
    }
}
