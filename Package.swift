// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pointrans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Pointrans", targets: ["Pointrans"])
    ],
    targets: [
        .executableTarget(
            name: "Pointrans",
            path: "Sources/Pointrans",
            exclude: ["local_dict.json", "app_icon_transparent.png", "AppIcon.icns"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
