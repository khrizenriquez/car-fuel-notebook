// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CartrackCorePackage",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CartrackCore", targets: ["CartrackCore"]),
    ],
    targets: [
        .target(
            name: "CartrackCore",
            path: "CartrackCore/Sources/CartrackCore"
        ),
        .testTarget(
            name: "CartrackCoreTests",
            dependencies: ["CartrackCore"],
            path: "CartrackCore/Tests/CartrackCoreTests",
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
