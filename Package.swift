// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PVECenter",
    defaultLocalization: "fr",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
        .tvOS("27.0"),
    ],
    products: [
        .executable(name: "PVECenter", targets: ["PVECenter"]),
    ],
    targets: [
        .executableTarget(
            name: "PVECenter",
            path: "PVECenter",
            exclude: ["Resources"]
        ),
    ]
)
