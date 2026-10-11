// swift-tools-version:5.10
// Tiroflan : suivi des heures freelance dans la barre des menus macOS.
import PackageDescription

let package = Package(
    name: "Tiroflan",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tiroflan", path: "Sources/Tiroflan")
    ]
)
