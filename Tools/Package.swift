// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QualityTools",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "pmtools", targets: ["pmtools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
    ],
    targets: [
        .target(
            name: "QualityKit",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(name: "pmtools", dependencies: ["QualityKit"]),
        .testTarget(name: "QualityKitTests", dependencies: ["QualityKit"]),
    ]
)
