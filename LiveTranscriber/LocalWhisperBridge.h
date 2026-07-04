#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LocalWhisperBridgeSegment : NSObject

@property (nonatomic, readonly) NSTimeInterval startSeconds;
@property (nonatomic, copy, readonly) NSString *text;

- (instancetype)initWithStartSeconds:(NSTimeInterval)startSeconds text:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface LocalWhisperBridge : NSObject

+ (nullable NSArray<LocalWhisperBridgeSegment *> *)transcribeSamples:(NSData *)samples
                                                           modelPath:(NSString *)modelPath
                                                        languageCode:(NSString *)languageCode
                                                               error:(NSError **)error
    NS_SWIFT_NAME(transcribeSamples(_:modelPath:languageCode:));

@end

NS_ASSUME_NONNULL_END
