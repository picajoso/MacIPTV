// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacIPTV",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacIPTVCore", targets: ["MacIPTVCore"]),
        .executable(name: "MacIPTV", targets: ["MacIPTV"]),
    ],
    targets: [
        .target(name: "MacIPTVCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "MacIPTV",
            dependencies: ["MacIPTVCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MacIPTVCoreTests",
            dependencies: ["MacIPTVCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
