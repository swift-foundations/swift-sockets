// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-sockets",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "Sockets", targets: ["Sockets"]),
    ],
    dependencies: [
        .package(path: "../swift-io"),
        .package(path: "../swift-kernel"),
        .package(path: "../../swift-primitives/swift-memory-primitives"),
        .package(path: "../../swift-primitives/swift-memory-buffer-primitives"),
        .package(path: "../../swift-ietf/swift-rfc-791"),
        .package(path: "../../swift-ietf/swift-rfc-4291"),
    ],
    targets: [
        .target(
            name: "Sockets",
            dependencies: [
                .product(name: "IO", package: "swift-io"),
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Memory Primitives", package: "swift-memory-primitives"),
                .product(name: "Memory Buffer Primitives", package: "swift-memory-buffer-primitives"),
                .product(name: "RFC 791", package: "swift-rfc-791"),
                .product(name: "RFC 4291", package: "swift-rfc-4291"),
            ]
        ),
        .testTarget(
            name: "Sockets Tests",
            dependencies: [
                "Sockets",
                .product(name: "IO", package: "swift-io"),
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Memory Primitives", package: "swift-memory-primitives"),
                .product(name: "Memory Buffer Primitives", package: "swift-memory-buffer-primitives"),
            ],
            path: "Tests/Sockets Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
