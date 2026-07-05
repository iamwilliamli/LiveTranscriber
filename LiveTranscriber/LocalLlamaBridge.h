#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LocalLlamaBridge : NSObject

+ (nullable NSString *)generateTextWithModelAtPath:(NSString *)modelPath
                                      systemPrompt:(NSString *)systemPrompt
                                        userPrompt:(NSString *)userPrompt
                                         maxTokens:(NSInteger)maxTokens
                                     contextTokens:(NSInteger)contextTokens
                                       temperature:(float)temperature
                                              topP:(float)topP
                                             error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(generateText(withModelAtPath:systemPrompt:userPrompt:maxTokens:contextTokens:temperature:topP:));

@end

NS_ASSUME_NONNULL_END
