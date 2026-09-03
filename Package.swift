// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CorePersist",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "CorePersist", targets: ["CorePersist"])
    ],
    targets: [
        .target(
            name: "CorePersist",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "CorePersistTests",
            dependencies: ["CorePersist"]
        )
    ]
)
