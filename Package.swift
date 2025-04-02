// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Rewrite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Rewrite", targets: ["Rewrite"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3")
    ],
    targets: [
        .executableTarget(
            name: "Rewrite",
            dependencies: ["HotKey"]
        )
    ]
)