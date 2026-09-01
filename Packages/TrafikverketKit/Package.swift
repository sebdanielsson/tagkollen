// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrafikverketKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "TrafikverketKit", targets: ["TrafikverketKit"]),
    ],
    targets: [
        .target(
            name: "TrafikverketKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TrafikverketKitTests",
            dependencies: ["TrafikverketKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
