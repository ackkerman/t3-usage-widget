// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "T3UsageWidget",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .library(name: "UsageWidget", targets: ["UsageWidget"]),
    ],
    targets: [
        .target(name: "UsageCore", resources: [.process("Resources")]),
        .target(name: "UsageWidget", dependencies: ["UsageCore"]),
        .executableTarget(name: "UsageProbe", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
