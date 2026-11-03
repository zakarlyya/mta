// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MTABar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "MTABar")
    ]
)
