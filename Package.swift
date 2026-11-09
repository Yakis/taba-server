// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TABA",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "GuideKit", targets: ["GuideKit"]),
        .library(name: "PipelineKit", targets: ["PipelineKit"]),
        .executable(name: "foursquare-probe", targets: ["FoursquareProbe"]),
        .executable(name: "taba-chatgpt", targets: ["TabaChatGPT"]),
        .library(name: "SourcesKit", targets: ["SourcesKit"]),
        .executable(name: "taba-sources-probe", targets: ["SourcesProbe"]),
        .executable(name: "taba", targets: ["Taba"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.1.1")
    ],
    targets: [
        .target(
            name: "GuideKit"
        ),
        .target(
            name: "PipelineKit",
            dependencies: ["GuideKit", "SourcesKit", "ResponsesKit"],
            path: ".",
            exclude: ["AGENTS.md", "CLAUDE.md", "README.md", "docs", "private", "probe-output", "scripts", "Tests",
                      "Sources/GuideKit", "Sources/FoursquareKit", "Sources/FoursquareProbe", "Sources/ResponsesKit",
                      "Sources/TabaChatGPT", "Sources/SourcesKit", "Sources/SourcesProbe", "Sources/Taba"],
            sources: ["Sources/PipelineKit"],
            resources: [.copy("Prompts")]
        ),
        .target(
            name: "FoursquareKit",
            dependencies: ["GuideKit"]
        ),
        .executableTarget(
            name: "FoursquareProbe",
            dependencies: ["FoursquareKit", "GuideKit"]
        ),
        .target(
            name: "ResponsesKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "TabaChatGPT",
            dependencies: ["ResponsesKit", "GuideKit"]
        ),
        .target(
            name: "SourcesKit",
            dependencies: ["GuideKit", "FoursquareKit"]
        ),
        .executableTarget(
            name: "SourcesProbe",
            dependencies: ["SourcesKit", "FoursquareKit", "GuideKit"]
        ),
        .executableTarget(
            name: "Taba",
            dependencies: ["PipelineKit", "SourcesKit", "FoursquareKit", "GuideKit", "ResponsesKit"]
        ),
        .testTarget(
            name: "TabaTests",
            dependencies: ["Taba", "GuideKit"]
        ),
        .testTarget(
            name: "PipelineKitTests",
            dependencies: ["PipelineKit", "GuideKit", "SourcesKit", "ResponsesKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SourcesKitTests",
            dependencies: ["SourcesKit", "FoursquareKit", "GuideKit"]
        ),
        .testTarget(
            name: "GuideKitTests",
            dependencies: ["GuideKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FoursquareProbeTests",
            dependencies: ["FoursquareKit", "GuideKit"]
        ),
        .testTarget(
            name: "ResponsesKitTests",
            dependencies: ["ResponsesKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
