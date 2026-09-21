// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OdbitkaKit",
    platforms: [.iOS("26.0"), .macOS("14.0")],  // macOS wyłącznie po to, żeby `swift test` działał na hoście bez symulatora
    products: [
        .library(name: "OdbitkaKit", targets: ["OdbitkaKit"])
    ],
    targets: [
        .target(
            name: "OdbitkaKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OdbitkaKitTests",
            dependencies: ["OdbitkaKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
