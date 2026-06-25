// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "media-desc",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "media-desc",
            path: "Sources"
        ),
    ]
)
