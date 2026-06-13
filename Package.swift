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
        .package(url: "https://github.com/swift-foundations/swift-io.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-kernel.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-threads.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-executors.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-span-primitives.git", branch: "main"),
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
            ]
        ),
        .testTarget(
            name: "Sockets Tests",
            dependencies: [
                "Sockets",
                .product(name: "IO", package: "swift-io"),
                .product(name: "Kernel", package: "swift-kernel"),
                .product(name: "Span Raw Primitives", package: "swift-span-primitives"),
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
