// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClutterClear",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClutterClear",
            path: "Sources/ClutterClear"
        )
    ]
)
