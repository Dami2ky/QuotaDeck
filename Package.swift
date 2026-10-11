// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "QuotaDeckCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "QuotaDeck",
            dependencies: ["QuotaDeckCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "QuotaDeckCLI",
            dependencies: ["QuotaDeckCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
