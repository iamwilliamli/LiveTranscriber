import Foundation
import MLXLMCommon

public struct MossTranscribeDiarizeConfig: Codable {
    public var modelType: String
    public var textConfig: Qwen3TextConfig
    public var audioConfig: WhisperConfig
    public var audioTokenId: Int
    public var audioMergeSize: Int
    public var adaptorInputDim: Int?
    public var tieWordEmbeddings: Bool
    public var sampleRate: Int
    public var quantization: BaseConfiguration.Quantization?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case textConfig = "text_config"
        case audioConfig = "audio_config"
        case audioTokenId = "audio_token_id"
        case audioMergeSize = "audio_merge_size"
        case adaptorInputDim = "adaptor_input_dim"
        case tieWordEmbeddings = "tie_word_embeddings"
        case sampleRate = "sample_rate"
        case quantization
    }

    public init(
        modelType: String = "moss_transcribe_diarize",
        textConfig: Qwen3TextConfig = Qwen3TextConfig(),
        audioConfig: WhisperConfig = WhisperConfig(
            modelType: "whisper",
            numMelBins: 80,
            dModel: 1024,
            encoderLayers: 24,
            encoderAttentionHeads: 16,
            encoderFfnDim: 4096,
            maxSourcePositions: 1500
        ),
        audioTokenId: Int = 151671,
        audioMergeSize: Int = 4,
        adaptorInputDim: Int? = nil,
        tieWordEmbeddings: Bool = true,
        sampleRate: Int = 16000,
        quantization: BaseConfiguration.Quantization? = nil
    ) {
        self.modelType = modelType
        var resolvedTextConfig = textConfig
        resolvedTextConfig.tieWordEmbeddings = tieWordEmbeddings
        self.textConfig = resolvedTextConfig
        self.audioConfig = audioConfig
        self.audioTokenId = audioTokenId
        self.audioMergeSize = audioMergeSize
        self.adaptorInputDim = adaptorInputDim ?? audioConfig.dModel * audioMergeSize
        self.tieWordEmbeddings = tieWordEmbeddings
        self.sampleRate = sampleRate
        self.quantization = quantization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decodeIfPresent(String.self, forKey: .modelType) ?? "moss_transcribe_diarize"
        var decodedTextConfig = try container.decodeIfPresent(Qwen3TextConfig.self, forKey: .textConfig)
            ?? Qwen3TextConfig()
        audioConfig = try container.decodeIfPresent(WhisperConfig.self, forKey: .audioConfig)
            ?? WhisperConfig(
                modelType: "whisper",
                numMelBins: 80,
                dModel: 1024,
                encoderLayers: 24,
                encoderAttentionHeads: 16,
                encoderFfnDim: 4096,
                maxSourcePositions: 1500
            )
        audioTokenId = try container.decodeIfPresent(Int.self, forKey: .audioTokenId) ?? 151671
        audioMergeSize = try container.decodeIfPresent(Int.self, forKey: .audioMergeSize) ?? 4
        tieWordEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? true
        decodedTextConfig.tieWordEmbeddings = tieWordEmbeddings
        textConfig = decodedTextConfig
        adaptorInputDim = try container.decodeIfPresent(Int.self, forKey: .adaptorInputDim)
            ?? audioConfig.dModel * audioMergeSize
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 16000
        // MOSS MLX checkpoints use a flat quantization object and may include
        // conversion metadata such as `scope` and `excluded_prefixes`.
        // Decoding the concrete Quantization value intentionally ignores those
        // extra keys while preserving bits, group size, and mode.
        quantization = try container.decodeIfPresent(
            BaseConfiguration.Quantization.self,
            forKey: .quantization
        )
    }
}
