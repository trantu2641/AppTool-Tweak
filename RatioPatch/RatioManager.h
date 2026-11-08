#ifndef AppToolsRatioCommon_h
#define AppToolsRatioCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString * const ATRatioStorePath =
    @"/var/mobile/Library/Preferences/com.jtisvn.apptools.screenratio.plist";

static NSString * const ATRatioNotification =
    @"com.jtisvn.apptools.screenratio.changed";

typedef struct {
    CGFloat width;
    CGFloat height;
} ATRatio;

static inline ATRatio ATRatioMake(CGFloat width, CGFloat height) {
    ATRatio r;
    r.width = width;
    r.height = height;
    return r;
}

static inline BOOL ATRatioValid(ATRatio r) {
    return r.width > 0.0 && r.height > 0.0;
}

static inline CGFloat ATRatioValue(ATRatio r) {
    if (r.height == 0.0)
        return 0.0;

    return r.width / r.height;
}

#endif
