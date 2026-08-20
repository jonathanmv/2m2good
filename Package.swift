// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BreakCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BreakCompanion", targets: ["BreakCompanion"])
    ],
    targets: [
        .executableTarget(
            name: "BreakCompanion",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Speech")
            ]
        ),
        .testTarget(
            name: "BreakCompanionTests",
            dependencies: ["BreakCompanion"]
        )
    ]
)
