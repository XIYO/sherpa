// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "sherpa-worker-protocol",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SherpaWorkerProtocol", targets: ["SherpaWorkerProtocol"])
    ],
    targets: [
        .target(name: "SherpaWorkerProtocol"),
        .testTarget(
            name: "SherpaWorkerProtocolTests",
            dependencies: ["SherpaWorkerProtocol"]
        ),
    ]
)
