// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lunar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lunar", targets: ["Lunar"])
    ],
    targets: [
        .executableTarget(
            name: "Lunar",
            path: "Sources/Lunar",
            exclude: ["Info.plist"],
            resources: [.copy("Resources/phases")]
        ),
        .testTarget(
            name: "LunarTests",
            dependencies: ["Lunar"],
            path: "Tests/LunarTests",
            resources: [.process("Resources")]
        )
    ]
)
