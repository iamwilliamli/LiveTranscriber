#import "LocalWhisperBridge.h"

#import <dlfcn.h>
#import <limits.h>
#import <stdbool.h>
#import <stdint.h>

static NSString * const LocalWhisperBridgeErrorDomain = @"com.iamwilliamli.LiveTranscriber.LocalWhisperBridge";

typedef NS_ENUM(NSInteger, LocalWhisperBridgeErrorCode) {
    LocalWhisperBridgeErrorRuntimeUnavailable = 1,
    LocalWhisperBridgeErrorMissingSymbol = 2,
    LocalWhisperBridgeErrorInvalidSamples = 3,
    LocalWhisperBridgeErrorContextCreationFailed = 4,
    LocalWhisperBridgeErrorTranscriptionFailed = 5,
};

struct whisper_context;
struct whisper_state;
struct whisper_token_data;
struct whisper_grammar_element;

typedef int32_t whisper_token;

struct whisper_ahead {
    int n_text_layer;
    int n_head;
};

struct whisper_aheads {
    size_t n_heads;
    const struct whisper_ahead * heads;
};

struct whisper_context_params {
    bool use_gpu;
    bool flash_attn;
    int gpu_device;
    bool dtw_token_timestamps;
    int dtw_aheads_preset;
    int dtw_n_top;
    struct whisper_aheads dtw_aheads;
    size_t dtw_mem_size;
};

struct whisper_vad_params {
    float threshold;
    int min_speech_duration_ms;
    int min_silence_duration_ms;
    float max_speech_duration_s;
    int speech_pad_ms;
    float samples_overlap;
};

typedef void (*lt_whisper_new_segment_callback)(struct whisper_context * ctx, struct whisper_state * state, int n_new, void * user_data);
typedef void (*lt_whisper_progress_callback)(struct whisper_context * ctx, struct whisper_state * state, int progress, void * user_data);
typedef bool (*lt_whisper_encoder_begin_callback)(struct whisper_context * ctx, struct whisper_state * state, void * user_data);
typedef bool (*lt_ggml_abort_callback)(void * user_data);
typedef void (*lt_whisper_logits_filter_callback)(
    struct whisper_context * ctx,
    struct whisper_state * state,
    const struct whisper_token_data * tokens,
    int n_tokens,
    float * logits,
    void * user_data
);

struct whisper_full_params {
    int strategy;
    int n_threads;
    int n_max_text_ctx;
    int offset_ms;
    int duration_ms;
    bool translate;
    bool no_context;
    bool no_timestamps;
    bool single_segment;
    bool print_special;
    bool print_progress;
    bool print_realtime;
    bool print_timestamps;
    bool token_timestamps;
    float thold_pt;
    float thold_ptsum;
    int max_len;
    bool split_on_word;
    int max_tokens;
    bool debug_mode;
    int audio_ctx;
    bool tdrz_enable;
    const char * suppress_regex;
    const char * initial_prompt;
    bool carry_initial_prompt;
    const whisper_token * prompt_tokens;
    int prompt_n_tokens;
    const char * language;
    bool detect_language;
    bool suppress_blank;
    bool suppress_nst;
    float temperature;
    float max_initial_ts;
    float length_penalty;
    float temperature_inc;
    float entropy_thold;
    float logprob_thold;
    float no_speech_thold;
    struct {
        int best_of;
    } greedy;
    struct {
        int beam_size;
        float patience;
    } beam_search;
    lt_whisper_new_segment_callback new_segment_callback;
    void * new_segment_callback_user_data;
    lt_whisper_progress_callback progress_callback;
    void * progress_callback_user_data;
    lt_whisper_encoder_begin_callback encoder_begin_callback;
    void * encoder_begin_callback_user_data;
    lt_ggml_abort_callback abort_callback;
    void * abort_callback_user_data;
    lt_whisper_logits_filter_callback logits_filter_callback;
    void * logits_filter_callback_user_data;
    const struct whisper_grammar_element ** grammar_rules;
    size_t n_grammar_rules;
    size_t i_start_rule;
    float grammar_penalty;
    bool vad;
    const char * vad_model_path;
    struct whisper_vad_params vad_params;
};

typedef struct whisper_context_params (*lt_whisper_context_default_params)(void);
typedef struct whisper_context * (*lt_whisper_init_from_file_with_params)(const char * path_model, struct whisper_context_params params);
typedef void (*lt_whisper_free)(struct whisper_context * ctx);
typedef struct whisper_full_params (*lt_whisper_full_default_params)(int strategy);
typedef int (*lt_whisper_full)(struct whisper_context * ctx, struct whisper_full_params params, const float * samples, int n_samples);
typedef int (*lt_whisper_full_n_segments)(struct whisper_context * ctx);
typedef int64_t (*lt_whisper_full_get_segment_t0)(struct whisper_context * ctx, int i_segment);
typedef const char * (*lt_whisper_full_get_segment_text)(struct whisper_context * ctx, int i_segment);

typedef struct {
    void *handle;
    lt_whisper_context_default_params context_default_params;
    lt_whisper_init_from_file_with_params init_from_file_with_params;
    lt_whisper_free free_context;
    lt_whisper_full_default_params full_default_params;
    lt_whisper_full full;
    lt_whisper_full_n_segments full_n_segments;
    lt_whisper_full_get_segment_t0 full_get_segment_t0;
    lt_whisper_full_get_segment_text full_get_segment_text;
} LTWhisperRuntime;

@implementation LocalWhisperBridgeSegment

- (instancetype)initWithStartSeconds:(NSTimeInterval)startSeconds text:(NSString *)text {
    self = [super init];
    if (self) {
        _startSeconds = startSeconds;
        _text = [text copy];
    }
    return self;
}

@end

static NSError *LTWhisperMakeError(LocalWhisperBridgeErrorCode code, NSString *message) {
    return [NSError errorWithDomain:LocalWhisperBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL LTWhisperHasRequiredSymbols(void *handle) {
    return dlsym(handle, "whisper_full") != NULL &&
        dlsym(handle, "whisper_init_from_file_with_params") != NULL;
}

static void *LTWhisperOpenRuntimeHandle(void) {
    void *processHandle = dlopen(NULL, RTLD_NOW);
    if (processHandle != NULL && LTWhisperHasRequiredSymbols(processHandle)) {
        return processHandle;
    }

    NSMutableArray<NSString *> *candidatePaths = [NSMutableArray array];
    NSString *privateFrameworksPath = NSBundle.mainBundle.privateFrameworksPath;
    if (privateFrameworksPath.length > 0) {
        [candidatePaths addObject:[privateFrameworksPath stringByAppendingPathComponent:@"whisper.framework/whisper"]];
        [candidatePaths addObject:[privateFrameworksPath stringByAppendingPathComponent:@"Whisper.framework/Whisper"]];
        [candidatePaths addObject:[privateFrameworksPath stringByAppendingPathComponent:@"libwhisper.dylib"]];
    }
    NSString *executablePath = NSBundle.mainBundle.executablePath;
    if (executablePath.length > 0) {
        [candidatePaths addObject:executablePath];
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *path in candidatePaths) {
        if (![fileManager fileExistsAtPath:path]) {
            continue;
        }

        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW);
        if (handle != NULL && LTWhisperHasRequiredSymbols(handle)) {
            return handle;
        }
    }

    return NULL;
}

static BOOL LTWhisperLoadSymbol(void *handle, const char *name, void **destination, NSError **error) {
    void *symbol = dlsym(handle, name);
    if (symbol == NULL) {
        if (error != NULL) {
            NSString *message = [NSString stringWithFormat:@"whisper.cpp is missing the required symbol: %s.", name];
            *error = LTWhisperMakeError(LocalWhisperBridgeErrorMissingSymbol, message);
        }
        return NO;
    }

    *destination = symbol;
    return YES;
}

static BOOL LTWhisperLoadRuntime(LTWhisperRuntime *runtime, NSError **error) {
    static LTWhisperRuntime cachedRuntime;
    static BOOL hasCachedRuntime = NO;
    static NSError *cachedError = nil;

    @synchronized ([LocalWhisperBridge class]) {
        if (hasCachedRuntime) {
            *runtime = cachedRuntime;
            return YES;
        }
        if (cachedError != nil) {
            if (error != NULL) {
                *error = cachedError;
            }
            return NO;
        }

        void *handle = LTWhisperOpenRuntimeHandle();
        if (handle == NULL) {
            cachedError = LTWhisperMakeError(
                LocalWhisperBridgeErrorRuntimeUnavailable,
                @"whisper.cpp is not embedded in this build."
            );
            if (error != NULL) {
                *error = cachedError;
            }
            return NO;
        }

        LTWhisperRuntime loadedRuntime = {0};
        loadedRuntime.handle = handle;
        if (!LTWhisperLoadSymbol(handle, "whisper_context_default_params", (void **)&loadedRuntime.context_default_params, error) ||
            !LTWhisperLoadSymbol(handle, "whisper_init_from_file_with_params", (void **)&loadedRuntime.init_from_file_with_params, error) ||
            !LTWhisperLoadSymbol(handle, "whisper_free", (void **)&loadedRuntime.free_context, error) ||
            !LTWhisperLoadSymbol(handle, "whisper_full_default_params", (void **)&loadedRuntime.full_default_params, error) ||
            !LTWhisperLoadSymbol(handle, "whisper_full", (void **)&loadedRuntime.full, error) ||
            !LTWhisperLoadSymbol(handle, "whisper_full_n_segments", (void **)&loadedRuntime.full_n_segments, error) ||
            !LTWhisperLoadSymbol(handle, "whisper_full_get_segment_t0", (void **)&loadedRuntime.full_get_segment_t0, error) ||
            !LTWhisperLoadSymbol(handle, "whisper_full_get_segment_text", (void **)&loadedRuntime.full_get_segment_text, error)) {
            if (error != NULL && *error != nil) {
                cachedError = *error;
            }
            return NO;
        }

        cachedRuntime = loadedRuntime;
        hasCachedRuntime = YES;
        *runtime = cachedRuntime;
        return YES;
    }
}

@implementation LocalWhisperBridge

+ (NSArray<LocalWhisperBridgeSegment *> *)transcribeSamples:(NSData *)samples
                                                 modelPath:(NSString *)modelPath
                                              languageCode:(NSString *)languageCode
                                                     error:(NSError **)error {
    if (samples.length == 0 || samples.length % sizeof(float) != 0) {
        if (error != NULL) {
            *error = LTWhisperMakeError(LocalWhisperBridgeErrorInvalidSamples, @"The local Whisper audio buffer is invalid.");
        }
        return nil;
    }

    NSUInteger sampleCount = samples.length / sizeof(float);
    if (sampleCount > INT_MAX) {
        if (error != NULL) {
            *error = LTWhisperMakeError(LocalWhisperBridgeErrorInvalidSamples, @"The local Whisper audio buffer is too large.");
        }
        return nil;
    }

    LTWhisperRuntime runtime = {0};
    if (!LTWhisperLoadRuntime(&runtime, error)) {
        return nil;
    }

    struct whisper_context_params contextParams = runtime.context_default_params();
    contextParams.use_gpu = true;

    struct whisper_context *context = runtime.init_from_file_with_params(modelPath.fileSystemRepresentation, contextParams);
    if (context == NULL) {
        if (error != NULL) {
            *error = LTWhisperMakeError(LocalWhisperBridgeErrorContextCreationFailed, @"Local Whisper could not load the selected model.");
        }
        return nil;
    }

    struct whisper_full_params params = runtime.full_default_params(0);
    NSInteger activeProcessorCount = NSProcessInfo.processInfo.activeProcessorCount;
    params.n_threads = (int)MAX(2, MIN(activeProcessorCount - 1, 4));
    params.translate = false;
    params.no_timestamps = false;
    params.single_segment = false;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.language = languageCode.length > 0 ? languageCode.UTF8String : "auto";
    params.detect_language = languageCode.length == 0 || [languageCode isEqualToString:@"auto"];

    int result = runtime.full(context, params, samples.bytes, (int)sampleCount);
    if (result != 0) {
        runtime.free_context(context);
        if (error != NULL) {
            *error = LTWhisperMakeError(LocalWhisperBridgeErrorTranscriptionFailed, @"Local Whisper transcription failed.");
        }
        return nil;
    }

    int segmentCount = MAX(runtime.full_n_segments(context), 0);
    NSMutableArray<LocalWhisperBridgeSegment *> *segments = [NSMutableArray arrayWithCapacity:(NSUInteger)segmentCount];
    NSCharacterSet *trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (int index = 0; index < segmentCount; index++) {
        const char *textPointer = runtime.full_get_segment_text(context, index);
        if (textPointer == NULL) {
            continue;
        }

        NSString *text = [[NSString stringWithUTF8String:textPointer] stringByTrimmingCharactersInSet:trimSet];
        if (text.length == 0) {
            continue;
        }

        int64_t centiseconds = runtime.full_get_segment_t0(context, index);
        [segments addObject:[[LocalWhisperBridgeSegment alloc] initWithStartSeconds:MAX((NSTimeInterval)centiseconds / 100.0, 0)
                                                                               text:text]];
    }

    runtime.free_context(context);
    return segments;
}

@end
