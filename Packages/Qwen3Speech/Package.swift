// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LiveTranscriberSpeechRuntime",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0")
    ],
    products: [
        .library(name: "AudioCommon", targets: ["AudioCommon"]),
        .library(name: "Qwen3ASR", targets: ["Qwen3ASR"]),
        .library(name: "SpeechVAD", targets: ["SpeechVAD"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6")
    ],
    targets: [
        .target(
            name: "AudioCommon",
            dependencies: [
                .product(name: "Hub", package: "swift-transformers")
            ]
        ),
        .target(
            name: "MLXCommon",
            dependencies: [
                "AudioCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift")
            ]
        ),
        .target(
            name: "SpeechVAD",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift")
            ]
        ),
        .target(
            name: "Qwen3ASR",
            dependencies: [
                "AudioCommon",
                "MLXCommon",
                "SpeechVAD",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift")
            ]
        ),
        .testTarget(
            name: "AudioCommonCompatibilityTests",
            dependencies: ["AudioCommon"]
        )
    ]
)
