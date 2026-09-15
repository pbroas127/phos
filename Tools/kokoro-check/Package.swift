// swift-tools-version: 6.2
// Runs the natural voices the same way Wick does, on a Mac, to catch bad audio and memory use before a build ships.
import PackageDescription

let package = Package(
    name: "KokoroCheck",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../Packages/kokoro-ios"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
    ],
    targets: [
        .executableTarget(
            name: "KokoroCheck",
            dependencies: [
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
