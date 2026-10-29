// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Features",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Catalog", targets: ["Catalog"]),
        .library(name: "Checkout", targets: ["Checkout"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Analytics"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],
    targets: [
        // Analytics is declared but never imported: a "gap" in the viewer.
        .target(name: "Catalog", dependencies: [
            .product(name: "Core", package: "Core"),
            .product(name: "Analytics", package: "Analytics"),
            .product(name: "Collections", package: "swift-collections"),
        ]),
        .target(name: "Checkout", dependencies: ["Catalog", .product(name: "Core", package: "Core")]),
    ]
)
