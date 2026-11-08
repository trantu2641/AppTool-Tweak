#import <Foundation/Foundation.h>
#import "AppToolsRatioCommon.h"

@interface ATRatioStore : NSObject
+ (instancetype)sharedStore;
- (void)setRatio:(ATRatio)ratio forBundleID:(NSString *)bundleID;
- (void)removeRatioForBundleID:(NSString *)bundleID;
- (BOOL)ratioForBundleID:(NSString *)bundleID ratio:(ATRatio *)ratio;
- (NSDictionary *)allRatios;
@end
