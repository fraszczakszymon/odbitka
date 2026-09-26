// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PixportKit",
    platforms: [.iOS("26.0"), .macOS("14.0")],  // macOS wyłącznie po to, żeby `swift test` działał na hoście bez symulatora
    products: [
        .library(name: "PixportKit", targets: ["PixportKit"])
    ],
    targets: [
        .target(
            name: "PixportKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PixportKitTests",
            dependencies: ["PixportKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
