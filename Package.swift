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
        .executable(name: "foursquare-probe", targets: ["FoursquareProbe"]),
        .executable(name: "taba-chatgpt", targets: ["TabaChatGPT"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.1.1")
    ],
    targets: [
        .target(
            name: "GuideKit"
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
