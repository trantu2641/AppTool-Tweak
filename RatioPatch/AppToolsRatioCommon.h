#ifndef AppToolsRatioCommon_h
#define AppToolsRatioCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

/*
 * Shared preference entry stored in each target application's own
 * CFPreferences domain. The target app can therefore read its own value
 * through cfprefsd without depending on a cross-sandbox file path.
 */
static NSString * const ATRatioPreferenceKey = @"AppToolsScreenRatio";
static NSString * const ATRatioNotification = @"com.flex2areo.apptools.screenratio.changed";
static NSString * const ATRatioRegistryDomain = @"com.flex2areo.apptools";
static NSString * const ATRatioRegistryKey = @"AppToolsScreenRatioRegistry";

typedef struct {
    CGFloat width;
    CGFloat height;
} ATRatio;

static inline ATRatio ATRatioMake(CGFloat width, CGFloat height) {
    ATRatio ratio;
    ratio.width = width;
    ratio.height = height;
    return ratio;
}

static inline BOOL ATRatioValid(ATRatio ratio) {
    return isfinite(ratio.width) && isfinite(ratio.height) &&
           ratio.width > 0.0 && ratio.height > 0.0;
}

static inline CGFloat ATRatioValue(ATRatio ratio) {
    return ATRatioValid(ratio) ? ratio.width / ratio.height : 0.0;
}

#endif
