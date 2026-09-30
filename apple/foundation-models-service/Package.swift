// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "sherpa-foundation-models",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "sherpa-foundation-models", targets: ["SherpaFoundationModels"])
    ],
    dependencies: [
        .package(path: "../worker-protocol")
    ],
    targets: [
        .executableTarget(
            name: "SherpaFoundationModels",
            dependencies: [
                .product(name: "SherpaWorkerProtocol", package: "worker-protocol")
            ]
        ),
        .testTarget(
            name: "SherpaFoundationModelsTests",
            dependencies: ["SherpaFoundationModels"]
        ),
    ]
)
