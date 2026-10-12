// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DotWiz",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DotWiz",
            path: "Sources/DotWiz"
        )
    ]
)
