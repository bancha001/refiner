// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Refiner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Refiner", path: "Sources/Refiner")
    ]
)
