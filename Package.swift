// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-sockets",
    platforms: [
        .macOS("27"),
        .iOS("27"),
        .tvOS("27"),
        .watchOS("27"),
        .visionOS("27")
    ],
    products: [
        .library(name: "Sockets", targets: ["Sockets"]),
        .library(name: "Sockets Byte Channel", targets: ["Sockets Byte Channel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-io.git", branch: "main"),
        .package(
            url: "https://github.com/swift-foundations/swift-byte-channel.git",
            revision: "f56b4393496fd52fffd1f27bfffca3b101a992d2"
        ),
        .package(url: "https://github.com/swift-foundations/swift-kernel.git", branch: "main"),
        .package(
            url: "https://github.com/swift-iso/swift-iso-9945.git",
            revision: "00ab4956fd6e8e20798684150e990bab39d27e08"
        ),
        .package(url: "https://github.com/swift-foundations/swift-threads.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-executors.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-span-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-byte-primitives.git", branch: "main"),
        // Test-only: the reactive test-support IO factory pins a
        // Kernel.Thread.Actor and drives readiness through POSIX poll(2).
        .package(url: "https://github.com/swift-foundations/swift-posix.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Sockets",
            dependencies: [
                .product(name: "IO", package: "swift-io"),
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Thread Actor", package: "swift-threads"),
                .product(name: "Executors", package: "swift-executors"),
                .product(name: "Span Raw Primitives", package: "swift-span-primitives"),
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
                .product(name: "ISO 9945 Kernel File", package: "swift-iso-9945"),
            ]
        ),
        .target(
            name: "Sockets Byte Channel",
            dependencies: [
                "Sockets",
                .product(name: "Byte Chunk", package: "swift-byte-channel"),
            ]
        ),
        .testTarget(
            name: "Sockets Tests",
            dependencies: [
                "Sockets",
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Span Raw Primitives", package: "swift-span-primitives"),
                // Test-only: reactive-strategy IO factory (see
                // Sockets.Tests.ReactiveIO.swift). Not consumed by the
                // Sockets target.
                .product(name: "Thread Actor", package: "swift-threads"),
                .product(name: "Executors", package: "swift-executors"),
                .product(name: "POSIX Kernel Poll", package: "swift-posix"),
            ],
            path: "Tests/Sockets Tests"
        ),
        .testTarget(
            name: "Sockets Byte Channel Tests",
            dependencies: ["Sockets Byte Channel"],
            path: "Tests/Sockets Byte Channel Tests"
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
