// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibePaper",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "VibePaper",
            path: "Sources/VibePaper",
            resources: [
                .process("../../Resources")
            ],
            swiftSettings: [
                // MVP: Swift 5 兼容模式，最小并发检查
                .unsafeFlags(["-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
