// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PVECenter",
    defaultLocalization: "fr",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
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
