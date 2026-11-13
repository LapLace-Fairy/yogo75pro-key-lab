// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YogoKeyLab",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "YogoCore", targets: ["YogoCore"]),
        .executable(name: "YogoKeyLab", targets: ["YogoKeyLab"]),
        .executable(name: "YogoSignal", targets: ["YogoSignal"]),
    ],
    targets: [
        .target(name: "YogoCore"),
        .executableTarget(name: "YogoKeyLab", dependencies: ["YogoCore"]),
        .executableTarget(name: "YogoSignal", dependencies: ["YogoCore"]),
        .testTarget(name: "YogoCoreTests", dependencies: ["YogoCore"]),
    ]
)
