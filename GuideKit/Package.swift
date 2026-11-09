// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GuideKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
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
