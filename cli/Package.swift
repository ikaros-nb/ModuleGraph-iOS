// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "modulegraph",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "modulegraph", targets: ["modulegraph"]),
        .library(name: "ModuleGraphCore", targets: ["ModuleGraphCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ModuleGraphCore"),
        .executableTarget(
            name: "modulegraph",
            dependencies: [
                "ModuleGraphCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ModuleGraphCoreTests",
            dependencies: ["ModuleGraphCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
