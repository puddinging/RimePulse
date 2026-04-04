// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RimePulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RimePulse",
            path: "Sources/RimePulse"
        )
    ]
)
