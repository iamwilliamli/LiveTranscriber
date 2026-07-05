#import "LocalLlamaBridge.h"

#import <dispatch/dispatch.h>
#import <TargetConditionals.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#import <llama/llama.h>
#pragma clang diagnostic pop

#include <algorithm>
#include <climits>
#include <memory>
#include <string>
#include <vector>

static NSString * const LocalLlamaBridgeErrorDomain = @"com.iamwilliamli.LiveTranscriber.LocalLlamaBridge";

typedef NS_ENUM(NSInteger, LocalLlamaBridgeErrorCode) {
    LocalLlamaBridgeErrorInvalidInput = 1,
    LocalLlamaBridgeErrorModelLoadFailed = 2,
    LocalLlamaBridgeErrorContextCreationFailed = 3,
    LocalLlamaBridgeErrorTemplateFailed = 4,
    LocalLlamaBridgeErrorTokenizationFailed = 5,
    LocalLlamaBridgeErrorContextExceeded = 6,
    LocalLlamaBridgeErrorDecodeFailed = 7,
    LocalLlamaBridgeErrorEmptyResponse = 8,
};

namespace {

struct LlamaModelDeleter {
    void operator()(llama_model *model) const {
        if (model != nullptr) {
            llama_model_free(model);
        }
    }
};

struct LlamaContextDeleter {
    void operator()(llama_context *context) const {
        if (context != nullptr) {
            llama_free(context);
        }
    }
};

struct LlamaSamplerDeleter {
    void operator()(llama_sampler *sampler) const {
        if (sampler != nullptr) {
            llama_sampler_free(sampler);
        }
    }
};

using LlamaModelPtr = std::unique_ptr<llama_model, LlamaModelDeleter>;
using LlamaContextPtr = std::unique_ptr<llama_context, LlamaContextDeleter>;
using LlamaSamplerPtr = std::unique_ptr<llama_sampler, LlamaSamplerDeleter>;

NSError *LTLlamaMakeError(LocalLlamaBridgeErrorCode code, NSString *message) {
    return [NSError errorWithDomain:LocalLlamaBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

std::string LTUTF8String(NSString *string) {
    const char *utf8 = string.UTF8String;
    return utf8 == nullptr ? std::string() : std::string(utf8);
}

std::string LTTrimmedLogText(const char *text) {
    std::string message(text == nullptr ? "" : text);
    const std::string whitespace = " \t\r\n";
    const size_t start = message.find_first_not_of(whitespace);
    if (start == std::string::npos) {
        return "";
    }

    const size_t end = message.find_last_not_of(whitespace);
    return message.substr(start, end - start + 1);
}

bool LTLogTextContains(const std::string &message, const char *needle) {
    return message.find(needle) != std::string::npos;
}

bool LTShouldSuppressLlamaLog(const std::string &message) {
    if (message.empty() || message == ".") {
        return true;
    }

    if (LTLogTextContains(message, "Compilation succeeded with") ||
        LTLogTextContains(message, "program_source:") ||
        LTLogTextContains(message, "duplicate 'const' declaration specifier") ||
        LTLogTextContains(message, "unused variable") ||
        LTLogTextContains(message, "unused function")) {
        return true;
    }

    return false;
}

void LTLlamaLogCallback(enum ggml_log_level level, const char *text, void *) {
    if (level != GGML_LOG_LEVEL_ERROR || text == nullptr) {
        return;
    }

    const std::string message = LTTrimmedLogText(text);
    if (LTShouldSuppressLlamaLog(message)) {
        return;
    }

    NSLog(@"[LocalLlama] %s", message.c_str());
}

void LTLlamaInitializeBackendIfNeeded() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        llama_log_set(LTLlamaLogCallback, nullptr);
        ggml_backend_load_all();
        llama_backend_init();
    });
}

int32_t LTThreadCount() {
    NSInteger processorCount = NSProcessInfo.processInfo.processorCount;
    NSInteger threadCount = std::max<NSInteger>(1, std::min<NSInteger>(6, processorCount - 2));
    return (int32_t)threadCount;
}

NSString *LTStringFromResponseBytes(const std::string &response) {
    NSString *string = [[NSString alloc] initWithBytes:response.data()
                                               length:response.size()
                                             encoding:NSUTF8StringEncoding];
    if (string != nil) {
        return string;
    }

    return [[NSString alloc] initWithBytes:response.data()
                                    length:response.size()
                                  encoding:NSISOLatin1StringEncoding];
}

bool LTAppendTokenPiece(const llama_vocab *vocab, llama_token token, std::string &response) {
    char stackBuffer[256];
    int32_t byteCount = llama_token_to_piece(vocab, token, stackBuffer, (int32_t)sizeof(stackBuffer), 0, true);
    if (byteCount >= 0) {
        response.append(stackBuffer, (size_t)byteCount);
        return true;
    }

    if (byteCount == INT32_MIN) {
        return false;
    }

    std::vector<char> dynamicBuffer((size_t)-byteCount);
    byteCount = llama_token_to_piece(vocab, token, dynamicBuffer.data(), (int32_t)dynamicBuffer.size(), 0, true);
    if (byteCount < 0) {
        return false;
    }

    response.append(dynamicBuffer.data(), (size_t)byteCount);
    return true;
}

} // namespace

@implementation LocalLlamaBridge

+ (nullable NSString *)generateTextWithModelAtPath:(NSString *)modelPath
                                      systemPrompt:(NSString *)systemPrompt
                                        userPrompt:(NSString *)userPrompt
                                         maxTokens:(NSInteger)maxTokens
                                     contextTokens:(NSInteger)contextTokens
                                       temperature:(float)temperature
                                              topP:(float)topP
                                             error:(NSError **)error {
    if (modelPath.length == 0 || systemPrompt.length == 0 || userPrompt.length == 0) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorInvalidInput, @"The local summary request is invalid.");
        }
        return nil;
    }

    LTLlamaInitializeBackendIfNeeded();

    const int32_t requestedContextTokens = (int32_t)std::max<NSInteger>(1024, std::min<NSInteger>(contextTokens, 8192));
    const int32_t requestedMaxTokens = (int32_t)std::max<NSInteger>(64, std::min<NSInteger>(maxTokens, 1024));
    const float clampedTemperature = std::max(0.0f, std::min(temperature, 1.5f));
    const float clampedTopP = std::max(0.05f, std::min(topP, 1.0f));

    llama_model_params modelParams = llama_model_default_params();
#if TARGET_OS_SIMULATOR
    modelParams.n_gpu_layers = 0;
#else
    modelParams.n_gpu_layers = 99;
#endif

    std::string modelPathString = LTUTF8String(modelPath);
    LlamaModelPtr model(llama_model_load_from_file(modelPathString.c_str(), modelParams));
    if (model == nullptr) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorModelLoadFailed, @"llama.cpp could not load the Qwen GGUF model.");
        }
        return nil;
    }

    const llama_vocab *vocab = llama_model_get_vocab(model.get());
    if (vocab == nullptr) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorModelLoadFailed, @"llama.cpp could not read the Qwen tokenizer.");
        }
        return nil;
    }

    std::string systemPromptString = LTUTF8String(systemPrompt);
    std::string userPromptString = LTUTF8String(userPrompt);
    llama_chat_message messages[] = {
        {"system", systemPromptString.c_str()},
        {"user", userPromptString.c_str()},
    };

    const char *chatTemplate = llama_model_chat_template(model.get(), nullptr);
    int32_t formattedByteCount = llama_chat_apply_template(chatTemplate, messages, 2, true, nullptr, 0);
    if (formattedByteCount < 0) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorTemplateFailed, @"llama.cpp could not apply the Qwen chat template.");
        }
        return nil;
    }

    std::vector<char> formattedPrompt((size_t)formattedByteCount + 1);
    formattedByteCount = llama_chat_apply_template(chatTemplate, messages, 2, true, formattedPrompt.data(), (int32_t)formattedPrompt.size());
    if (formattedByteCount < 0) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorTemplateFailed, @"llama.cpp could not apply the Qwen chat template.");
        }
        return nil;
    }

    std::string prompt(formattedPrompt.data(), (size_t)formattedByteCount);
    int32_t promptTokenCount = -llama_tokenize(
        vocab,
        prompt.c_str(),
        (int32_t)prompt.size(),
        nullptr,
        0,
        true,
        true
    );
    if (promptTokenCount <= 0) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorTokenizationFailed, @"llama.cpp could not tokenize the summary prompt.");
        }
        return nil;
    }

    if (promptTokenCount + requestedMaxTokens > requestedContextTokens) {
        if (error != nullptr) {
            NSString *message = [NSString stringWithFormat:@"The transcript is too long for the local Qwen context (%d prompt tokens, %d context tokens).", promptTokenCount, requestedContextTokens];
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorContextExceeded, message);
        }
        return nil;
    }

    std::vector<llama_token> promptTokens((size_t)promptTokenCount);
    int32_t actualPromptTokenCount = llama_tokenize(
        vocab,
        prompt.c_str(),
        (int32_t)prompt.size(),
        promptTokens.data(),
        (int32_t)promptTokens.size(),
        true,
        true
    );
    if (actualPromptTokenCount < 0) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorTokenizationFailed, @"llama.cpp could not tokenize the summary prompt.");
        }
        return nil;
    }

    llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = (uint32_t)requestedContextTokens;
    contextParams.n_batch = (uint32_t)requestedContextTokens;
    contextParams.n_threads = LTThreadCount();
    contextParams.n_threads_batch = LTThreadCount();
    contextParams.no_perf = true;

    LlamaContextPtr context(llama_init_from_model(model.get(), contextParams));
    if (context == nullptr) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorContextCreationFailed, @"llama.cpp could not create a Qwen context.");
        }
        return nil;
    }

    llama_sampler_chain_params samplerParams = llama_sampler_chain_default_params();
    samplerParams.no_perf = true;
    LlamaSamplerPtr sampler(llama_sampler_chain_init(samplerParams));
    if (sampler == nullptr) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorContextCreationFailed, @"llama.cpp could not create a sampler.");
        }
        return nil;
    }

    llama_sampler_chain_add(sampler.get(), llama_sampler_init_min_p(0.05f, 1));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_top_p(clampedTopP, 1));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_temp(clampedTemperature));
    llama_sampler_chain_add(sampler.get(), llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    std::string response;
    llama_batch batch = llama_batch_get_one(promptTokens.data(), actualPromptTokenCount);

    for (int32_t generatedTokenCount = 0; generatedTokenCount < requestedMaxTokens; generatedTokenCount++) {
        int32_t decodeResult = llama_decode(context.get(), batch);
        if (decodeResult != 0) {
            if (error != nullptr) {
                NSString *message = [NSString stringWithFormat:@"llama.cpp decode failed (%d).", decodeResult];
                *error = LTLlamaMakeError(LocalLlamaBridgeErrorDecodeFailed, message);
            }
            return nil;
        }

        llama_token token = llama_sampler_sample(sampler.get(), context.get(), -1);
        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        if (!LTAppendTokenPiece(vocab, token, response)) {
            if (error != nullptr) {
                *error = LTLlamaMakeError(LocalLlamaBridgeErrorDecodeFailed, @"llama.cpp could not detokenize the generated text.");
            }
            return nil;
        }

        batch = llama_batch_get_one(&token, 1);
    }

    NSString *output = LTStringFromResponseBytes(response);
    if (output.length == 0) {
        if (error != nullptr) {
            *error = LTLlamaMakeError(LocalLlamaBridgeErrorEmptyResponse, @"Qwen did not generate a usable response.");
        }
        return nil;
    }

    return output;
}

@end
