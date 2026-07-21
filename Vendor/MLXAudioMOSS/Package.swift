// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MLXAudioMOSS",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MLXAudioCore", targets: ["MLXAudioCore"]),
        .library(name: "MLXAudioSTT", targets: ["MLXAudioSTT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.30.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.1.6")),
        // LiveTranscriber downloads model files itself and opens the local
        // directory directly, so the standard Hub client is sufficient.
        .package(url: "https://github.com/huggingface/swift-huggingface.git", .upToNextMajor(from: "0.9.0")),
    ],
    targets: [
        .target(
            name: "MLXAudioCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/MLXAudioCore",
            sources: [
                "AudioUtils.swift",
                "DSP.swift",
                "ModelUtils.swift",
            ]
        ),
        .target(
            name: "MLXAudioSTT",
            dependencies: [
                "MLXAudioCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            path: "Sources/MLXAudioSTT",
            sources: [
                "Generation.swift",
                "Models/GLMASR/STTOutput.swift",
                "Models/MossTranscribeDiarize/MossTranscribeDiarize.swift",
                "Models/MossTranscribeDiarize/MossTranscribeDiarizeConfig.swift",
                "Models/Qwen3ASR/Qwen3ASR.swift",
                "Models/Qwen3ASR/Qwen3ASRConfig.swift",
                "Models/Whisper/WhisperAudio.swift",
                "Models/Whisper/WhisperConfig.swift",
                "Models/Whisper/WhisperLayers.swift",
                "Streaming/StreamingTypes.swift",
            ]
        ),
    ]
)
