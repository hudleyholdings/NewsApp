// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NewsApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NewsApp", targets: ["NewsApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "NewsApp",
            dependencies: [
                "SwiftSoup"
            ],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "NewsAppTests",
            dependencies: ["NewsApp"]
        )
    ]
)
