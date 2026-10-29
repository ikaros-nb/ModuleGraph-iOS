// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Analytics",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Analytics", targets: ["Analytics"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "Analytics", dependencies: [.product(name: "Core", package: "Core")]),
    ]
)
