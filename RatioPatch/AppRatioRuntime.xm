#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "RatioStore.h"

#pragma mark - Runtime state


static CGRect ATROriginalScreenBounds =
    CGRectZero;


static ATRatio ATRCurrentRatio(void) {

    NSString *bundleID =
        [[NSBundle mainBundle] bundleIdentifier];

    if (!bundleID.length)
        return ATRatioMake(0, 0);

    ATRatio ratio;

    if ([[ATRatioStore sharedStore]
            ratioForBundleID:bundleID
                       ratio:&ratio]) {

        return ratio;
    }

    return ATRatioMake(0, 0);
}


static CGRect ATRRatioBoundsForScreen(UIScreen *screen) {

    CGRect original =
        ATROriginalScreenBounds;

    if (CGRectIsEmpty(original))
        original = screen.bounds;

    ATRatio ratio =
        ATRCurrentRatio();

    if (!ATRatioValid(ratio))
        return original;

    CGFloat screenWidth =
        CGRectGetWidth(original);

    CGFloat screenHeight =
        CGRectGetHeight(original);

    CGFloat target =
        ATRatioValue(ratio);

    if (target <= 0.0)
        return original;

    CGFloat width =
        screenWidth;

    CGFloat height =
        screenWidth / target;

    if (height > screenHeight) {

        height = screenHeight;
        width = screenHeight * target;
    }

    CGFloat x =
        (screenWidth - width) / 2.0;

    CGFloat y =
        (screenHeight - height) / 2.0;

    return CGRectMake(x, y, width, height);
}

#pragma mark - UIScreen

%hook UIScreen

- (CGRect)bounds {

    CGRect original =
        %orig;

    if (CGRectIsEmpty(ATROriginalScreenBounds)) {

        ATROriginalScreenBounds =
            original;
    }

    return ATRRatioBoundsForScreen(self);
}

- (CGRect)applicationFrame {

    CGRect original =
        %orig;

    ATRatio ratio =
        ATRCurrentRatio();

    if (!ATRatioValid(ratio))
        return original;

    return ATRRatioBoundsForScreen(self);
}

%end

#pragma mark - UIWindow

%hook UIWindow

- (void)layoutSubviews {

    %orig;

    NSString *bundleID =
        [[NSBundle mainBundle] bundleIdentifier];

    /*
     * Không động vào AppTools.
     */

    if ([bundleID isEqualToString:@"com.jtisvn.apptools"])
        return;

    ATRatio ratio =
        ATRCurrentRatio();

    if (!ATRatioValid(ratio))
        return;

    UIScreen *screen =
        self.screen ?: UIScreen.mainScreen;

    CGRect screenBounds =
        ATROriginalScreenBounds;

    if (CGRectIsEmpty(screenBounds))
        screenBounds = screen.bounds;

    CGFloat sw =
        CGRectGetWidth(screenBounds);

    CGFloat sh =
        CGRectGetHeight(screenBounds);

    CGFloat target =
        ATRatioValue(ratio);

    CGFloat width =
        sw;

    CGFloat height =
        sw / target;

    if (height > sh) {

        height = sh;
        width = sh * target;
    }

    CGRect targetFrame =
        CGRectMake(
            (sw - width) / 2.0,
            (sh - height) / 2.0,
            width,
            height
        );

    /*
     * Chỉ áp dụng cho application window.
     */

    if (self.windowLevel == UIWindowLevelNormal) {

        CGRect current =
            self.frame;

        if (fabs(current.size.width - targetFrame.size.width) > 0.5 ||
            fabs(current.size.height - targetFrame.size.height) > 0.5) {

            self.frame = targetFrame;
        }
    }
}

%end

#pragma mark - Notification

static void ATRRatioChanged(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {

    dispatch_async(dispatch_get_main_queue(), ^{

        ATROriginalScreenBounds =
            UIScreen.mainScreen.bounds;

        for (UIWindow *window
             in UIApplication.sharedApplication.windows) {

            [window setNeedsLayout];
            [window layoutIfNeeded];
        }
    });
}

__attribute__((constructor))
static void ATRRuntimeInit(void) {

    NSString *bundleID =
        [[NSBundle mainBundle] bundleIdentifier];

    if (!bundleID.length)
        return;

    if ([bundleID isEqualToString:@"com.jtisvn.apptools"])
        return;

    ATROriginalScreenBounds =
        UIScreen.mainScreen.bounds;

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        ATRRatioChanged,
        (__bridge CFStringRef)ATRatioNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
