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
    ],
    dependencies: [
        // TX-N2 composes the published IO byte-channel vocabulary at the
        // approved producer revision. Package.resolved remains generated state
        // and is deliberately not rewritten by this source-only transaction.
        .package(
            url: "https://github.com/swift-foundations/swift-io.git",
            revision: "a81f0e5cbdf8b35c7e66374f284af8b1c5a9eaa3"
        ),
        .package(url: "https://github.com/swift-foundations/swift-kernel.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-threads.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-executors.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-span-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-primitives.git", branch: "main"),
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
                .product(name: "Buffer Primitives", package: "swift-buffer-primitives"),
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
            ]
        ),
        .testTarget(
            name: "Sockets Tests",
            dependencies: [
                "Sockets",
                .product(name: "IO", package: "swift-io"),
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
