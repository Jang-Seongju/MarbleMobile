// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarbleMobileCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MarbleMobileCore", targets: ["MarbleMobileCore"]),
    ],
    targets: [
        .target(name: "MarbleMobileCore"),
        .testTarget(name: "MarbleMobileCoreTests", dependencies: ["MarbleMobileCore"]),
    ]
)
