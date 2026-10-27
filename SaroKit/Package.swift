// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SaroKit",
    platforms: [.macOS("27.0")],
    products: [.library(name: "SaroKit", targets: ["SaroKit"])],
    targets: [
        .target(name: "SaroKit"),
        .testTarget(name: "SaroKitTests", dependencies: ["SaroKit"]),
    ]
)
