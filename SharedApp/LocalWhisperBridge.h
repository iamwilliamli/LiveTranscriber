#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LocalWhisperBridgeSegment : NSObject

@property (nonatomic, readonly) NSTimeInterval startSeconds;
@property (nonatomic, readonly) NSTimeInterval endSeconds;
@property (nonatomic, copy, readonly) NSString *text;

- (instancetype)initWithStartSeconds:(NSTimeInterval)startSeconds
                          endSeconds:(NSTimeInterval)endSeconds
                                text:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

typedef void (^LocalWhisperBridgeProgressHandler)(double progress);
typedef BOOL (^LocalWhisperBridgeCancellationHandler)(void);

@interface LocalWhisperBridge : NSObject

+ (nullable NSArray<LocalWhisperBridgeSegment *> *)transcribeSamples:(NSData *)samples
                                                           modelPath:(NSString *)modelPath
                                                        languageCode:(NSString *)languageCode
                                                    useCoreMLEncoder:(BOOL)useCoreMLEncoder
                                                     progressHandler:(nullable LocalWhisperBridgeProgressHandler)progressHandler
                                                 cancellationHandler:(nullable LocalWhisperBridgeCancellationHandler)cancellationHandler
                                                               error:(NSError **)error
    NS_SWIFT_NAME(transcribeSamples(_:modelPath:languageCode:useCoreMLEncoder:progressHandler:cancellationHandler:));

@end

NS_ASSUME_NONNULL_END
