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
        .executable(name: "foursquare-probe", targets: ["FoursquareProbe"])
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
        .testTarget(
            name: "GuideKitTests",
            dependencies: ["GuideKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FoursquareProbeTests",
            dependencies: ["FoursquareKit", "GuideKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
