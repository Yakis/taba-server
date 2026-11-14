// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TABA",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "PipelineKit", targets: ["PipelineKit"]),
        .executable(name: "foursquare-probe", targets: ["FoursquareProbe"]),
        .executable(name: "taba-chatgpt", targets: ["TabaChatGPT"]),
        .library(name: "SourcesKit", targets: ["SourcesKit"]),
        .executable(name: "taba-sources-probe", targets: ["SourcesProbe"]),
        .executable(name: "taba", targets: ["Taba"]),
        .executable(name: "taba-server", targets: ["TabaServer"]),
        .executable(name: "taba-score", targets: ["TabaScore"])
    ],
    dependencies: [
        .package(path: "GuideKit"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.1.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.26.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.9.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.5.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.3"),
        .package(url: "https://github.com/hummingbird-project/postgres-migrations.git", from: "1.2.0"),
        .package(url: "https://github.com/hummingbird-project/swift-jobs.git", from: "1.4.0"),
        .package(url: "https://github.com/hummingbird-project/swift-jobs-postgres.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.8.0")
    ],
    targets: [
        .target(
            name: "PipelineKit",
            dependencies: [.product(name: "GuideKit", package: "GuideKit"), "SourcesKit", "ResponsesKit"],
            path: ".",
            exclude: ["AGENTS.md", "CLAUDE.md", "README.md", "docs", "private", "probe-output", "scripts", "Tests",
                      "GuideKit", "Sources/FoursquareKit", "Sources/FoursquareProbe", "Sources/ResponsesKit",
                      "Sources/TabaChatGPT", "Sources/SourcesKit", "Sources/SourcesProbe", "Sources/Taba",
                      "Sources/ServerHTTPKit", "Sources/ServerKit", "Sources/BuildKit",
                      "Sources/LivePipelineKit", "Sources/TabaServer", "Sources/GuideScoreKit", "Sources/TabaScore",
                      "Evaluation", "Dockerfile", "compose.local.yml", ".dockerignore"],
            sources: ["Sources/PipelineKit"],
            resources: [.copy("Prompts")]
        ),
        .target(
            name: "FoursquareKit",
            dependencies: [.product(name: "GuideKit", package: "GuideKit")]
        ),
        .executableTarget(
            name: "FoursquareProbe",
            dependencies: ["FoursquareKit", .product(name: "GuideKit", package: "GuideKit")]
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
            dependencies: ["ResponsesKit", .product(name: "GuideKit", package: "GuideKit")]
        ),
        .target(
            name: "SourcesKit",
            dependencies: [.product(name: "GuideKit", package: "GuideKit"), "FoursquareKit"]
        ),
        .target(
            name: "ServerKit",
            dependencies: [
                .product(name: "GuideKit", package: "GuideKit"), "PipelineKit", "ResponsesKit",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "PostgresMigrations", package: "postgres-migrations"),
                .product(name: "Jobs", package: "swift-jobs"),
                .product(name: "JobsPostgres", package: "swift-jobs-postgres"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")
            ]
        ),
        .target(
            name: "ServerHTTPKit",
            dependencies: [
                "SourcesKit", "ResponsesKit",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ]
        ),
        .target(
            name: "BuildKit",
            dependencies: [
                .product(name: "GuideKit", package: "GuideKit"),
                "PipelineKit", "SourcesKit", "ResponsesKit"
            ]
        ),
        .target(
            name: "LivePipelineKit",
            dependencies: ["BuildKit", "ServerKit", "ServerHTTPKit", .product(name: "GuideKit", package: "GuideKit"),
                           "PipelineKit", "SourcesKit", "ResponsesKit",
                           .product(name: "AsyncHTTPClient", package: "async-http-client")]
        ),
        .executableTarget(
            name: "TabaServer",
            dependencies: ["ServerKit", "LivePipelineKit", "ServerHTTPKit", "ResponsesKit",
                           .product(name: "Hummingbird", package: "hummingbird"),
                           .product(name: "AsyncHTTPClient", package: "async-http-client"),
                           .product(name: "PostgresNIO", package: "postgres-nio"),
                           .product(name: "PostgresMigrations", package: "postgres-migrations"),
                           .product(name: "Jobs", package: "swift-jobs"),
                           .product(name: "JobsPostgres", package: "swift-jobs-postgres"),
                           .product(name: "Logging", package: "swift-log"),
                           .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")]
        ),
        .testTarget(name: "BuildKitTests",
                    dependencies: ["BuildKit", .product(name: "GuideKit", package: "GuideKit"), "PipelineKit",
                                   "ResponsesKit"]),
        .testTarget(name: "LivePipelineKitTests",
                    dependencies: ["LivePipelineKit", "ServerKit", .product(name: "GuideKit", package: "GuideKit"),
                                   "PipelineKit", "ResponsesKit"]),
        .executableTarget(
            name: "SourcesProbe",
            dependencies: ["SourcesKit", "FoursquareKit", .product(name: "GuideKit", package: "GuideKit")]
        ),
        .executableTarget(
            name: "Taba",
            dependencies: ["BuildKit", "PipelineKit", "SourcesKit",
                           .product(name: "GuideKit", package: "GuideKit"), "ResponsesKit"]
        ),
        .testTarget(
            name: "ServerHTTPKitTests",
            dependencies: [
                "ServerHTTPKit",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ]
        ),
        .testTarget(
            name: "ServerKitTests",
            dependencies: ["ServerKit", .product(name: "GuideKit", package: "GuideKit"), "PipelineKit", "ResponsesKit",
                           .product(name: "PostgresNIO", package: "postgres-nio"),
                           .product(name: "PostgresMigrations", package: "postgres-migrations"),
                           .product(name: "Jobs", package: "swift-jobs"),
                           .product(name: "JobsPostgres", package: "swift-jobs-postgres"),
                           .product(name: "Logging", package: "swift-log"),
                           .product(name: "HummingbirdTesting", package: "hummingbird") ]
        ),
        .testTarget(
            name: "TabaTests",
            dependencies: ["Taba", .product(name: "GuideKit", package: "GuideKit")]
        ),
        .testTarget(
            name: "PipelineKitTests",
            dependencies: ["PipelineKit", .product(name: "GuideKit", package: "GuideKit"), "SourcesKit",
                           "ResponsesKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SourcesKitTests",
            dependencies: ["SourcesKit", "FoursquareKit", .product(name: "GuideKit", package: "GuideKit")]
        ),
        .testTarget(
            name: "FoursquareProbeTests",
            dependencies: ["FoursquareKit", .product(name: "GuideKit", package: "GuideKit")]
        ),
        .testTarget(
            name: "ResponsesKitTests",
            dependencies: ["ResponsesKit"]
        ),
        .target(
            name: "GuideScoreKit",
            dependencies: [
                .product(name: "GuideKit", package: "GuideKit"), "PipelineKit", "ResponsesKit"
            ]
        ),
        .executableTarget(
            name: "TabaScore",
            dependencies: ["GuideScoreKit"]
        ),
        .testTarget(
            name: "GuideScoreKitTests",
            dependencies: [
                "GuideScoreKit", "ServerKit", .product(name: "GuideKit", package: "GuideKit")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
