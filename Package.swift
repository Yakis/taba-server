// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TABA",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "GuideKit", targets: ["GuideKit"])
    ],
    targets: [
        .target(
            name: "GuideKit"
        ),
        .testTarget(
            name: "GuideKitTests",
            dependencies: ["GuideKit"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
