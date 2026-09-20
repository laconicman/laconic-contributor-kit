// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "laconic-contributor-kit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ContributorKit", targets: ["ContributorKit"]),
        .executable(name: "contrib", targets: ["contrib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ContributorKit",
            dependencies: [.product(name: "Yams", package: "Yams")],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "contrib",
            dependencies: [
                "ContributorKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ContributorKitTests",
            dependencies: ["ContributorKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
