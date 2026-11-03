// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MTCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "MTCore", targets: ["MTCore"])],
    targets: [
        .target(name: "MTCore"),
        .testTarget(name: "MTCoreTests", dependencies: ["MTCore"]),
    ],
    swiftLanguageModes: [.v5]
)
