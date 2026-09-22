// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "McWinBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "McWinBar",
            path: "Sources/McWinBar",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
