#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ATRatioManager : NSObject

+ (instancetype)sharedManager;

- (void)setRatioForBundleID:(NSString *)bundleID
                      width:(CGFloat)width
                     height:(CGFloat)height;

- (void)setPresetRatioForBundleID:(NSString *)bundleID
                            ratio:(NSString *)ratio;

- (NSDictionary *)ratioForBundleID:(NSString *)bundleID;

- (void)applyRatioToApplication:(UIApplication *)application;

- (void)applyRatioToWindow:(UIWindow *)window
                 width:(CGFloat)width
                height:(CGFloat)height;

@end
