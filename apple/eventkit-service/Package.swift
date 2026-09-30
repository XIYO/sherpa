// swift-tools-version: 6.2

import PackageDescription

let infoPlist = Context.packageDirectory + "/Resources/Info.plist"

let package = Package(
    name: "sherpa",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "sherpa", targets: ["SherpaNative"]),
        .executable(
            name: "sherpa-eventkit-live-verify",
            targets: ["SherpaEventKitLiveVerifier"]
        ),
    ],
    dependencies: [
        .package(path: "../worker-protocol")
    ],
    targets: [
        .target(
            name: "SherpaPlannerContract",
            dependencies: [
                .product(name: "SherpaWorkerProtocol", package: "worker-protocol")
            ]
        ),
        .target(
            name: "SherpaPlannerApplication",
            dependencies: ["SherpaPlannerContract"]
        ),
        .target(
            name: "SherpaEventKitAdapter",
            dependencies: [
                "SherpaPlannerApplication",
                "SherpaPlannerContract",
                .product(name: "SherpaWorkerProtocol", package: "worker-protocol"),
            ]
        ),
        .target(name: "SherpaMutationApplication"),
        .target(
            name: "SherpaNativeCommandAdapter",
            dependencies: ["SherpaMailShim", "SherpaMutationApplication"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "SherpaMailShim",
            publicHeadersPath: "include",
            cSettings: [.define("SHERPA_MAIL_LIBRARY")],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreServices"),
            ]
        ),
        .target(
            name: "SherpaReminderKitShim",
            publicHeadersPath: "include",
            cSettings: [.define("SHERPA_REMINDER_KIT_LIBRARY")],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("EventKit"),
                .linkedFramework("ImageIO"),
                .linkedLibrary("dl"),
            ]
        ),
        .executableTarget(
            name: "SherpaNative",
            dependencies: [
                "SherpaMutationApplication",
                "SherpaNativeCommandAdapter",
                "SherpaEventKitAdapter",
                "SherpaMailShim",
                "SherpaReminderKitShim",
                .product(name: "SherpaWorkerProtocol", package: "worker-protocol"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ])
            ]
        ),
        .target(
            name: "SherpaEventKitLiveVerifierSupport",
            dependencies: [
                "SherpaPlannerContract",
                .product(name: "SherpaWorkerProtocol", package: "worker-protocol")
            ]
        ),
        .executableTarget(
            name: "SherpaEventKitLiveVerifier",
            dependencies: ["SherpaEventKitLiveVerifierSupport"]
        ),
        .testTarget(
            name: "SherpaEventKitTests",
            dependencies: [
                "SherpaPlannerContract",
                "SherpaEventKitAdapter",
                .product(name: "SherpaWorkerProtocol", package: "worker-protocol"),
            ]
        ),
        .testTarget(
            name: "SherpaEventKitLiveVerifierTests",
            dependencies: ["SherpaEventKitLiveVerifierSupport"]
        ),
        .testTarget(
            name: "SherpaNativeCommandAdapterTests",
            dependencies: [
                "SherpaMutationApplication", "SherpaNativeCommandAdapter", "SherpaMailShim",
                "SherpaReminderKitShim",
            ]
        ),
    ]
)
