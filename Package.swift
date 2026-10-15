// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PowerDeck",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PowerDeck",
            path: "Sources/PowerDeck"
        )
    ],
    swiftLanguageModes: [.v5]
)
