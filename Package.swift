// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PointTrans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PointTrans", targets: ["PointTrans"])
    ],
    targets: [
        .executableTarget(
            name: "PointTrans",
            path: "Sources/PointTrans",
            exclude: ["local_dict.json", "app_icon_transparent.png", "AppIcon.icns"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
