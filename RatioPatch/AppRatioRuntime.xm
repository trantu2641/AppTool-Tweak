#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/*
 * Safe, per-app viewport runtime.
 *
 * The dylib may be loaded into UIKit apps because the original AppTools
 * MobileSubstrate filter includes com.apple.UIKit.  Do NOT hook UIKit classes
 * unless this process has a valid ratio saved for its own Bundle ID.
 * This avoids touching unrelated apps at launch.
 *
 * Only UIViewController -viewDidLayoutSubviews is hooked, and only after a
 * saved ratio is found.  There are deliberately no global hooks on UIView,
 * UIWindow, UIScreen, setFrame:, or layoutSubviews.
 */

static NSString *gATRatioTargetBundleID = nil;
static ATRatio gATRatioTarget = {0.0, 0.0};
static BOOL gATRatioActive = NO;
static BOOL gATRatioHooksInstalled = NO;
static BOOL gATRatioApplyingGeometry = NO;
static id gATRatioActiveObserver = nil;

static char kATRatioOriginalFrameKey;
static char kATRatioOriginalRootClipsKey;
static char kATRatioOriginalWindowColorKey;
static char kATRatioOriginalWindowClipsKey;

#pragma mark - Geometry

static BOOL ATRatioRectsApproximatelyEqual(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.75 &&
           fabs(a.origin.y - b.origin.y) < 0.75 &&
           fabs(a.size.width - b.size.width) < 0.75 &&
           fabs(a.size.height - b.size.height) < 0.75;
}

/* Presets are expressed as long-side:short-side, independent of orientation. */
static CGRect ATRatioViewportInWindow(UIWindow *window, ATRatio ratio) {
    CGRect bounds = window.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0 || !ATRatioValid(ratio)) return bounds;

    CGFloat shortOverLong = MIN(ratio.width, ratio.height) / MAX(ratio.width, ratio.height);
    BOOL portrait = height >= width;
    CGFloat targetWidth = width;
    CGFloat targetHeight = height;

    if (portrait) {
        targetHeight = targetWidth / shortOverLong;
        if (targetHeight > height) {
            targetHeight = height;
            targetWidth = targetHeight * shortOverLong;
        }
    } else {
        targetWidth = targetHeight / shortOverLong;
        if (targetWidth > width) {
            targetWidth = width;
            targetHeight = targetWidth * shortOverLong;
        }
    }

    return CGRectMake(CGRectGetMinX(bounds) + (width - targetWidth) * 0.5,
                      CGRectGetMinY(bounds) + (height - targetHeight) * 0.5,
                      targetWidth, targetHeight);
}

static CGRect ATRatioFrameInSuperview(UIWindow *window, UIView *rootView, ATRatio ratio) {
    CGRect frameInWindow = ATRatioViewportInWindow(window, ratio);
    if (rootView.superview && rootView.superview != window) {
        return [rootView.superview convertRect:frameInWindow fromView:window];
    }
    return frameInWindow;
}

#pragma mark - Preserve and restore original geometry

static void ATRatioRememberGeometry(UIView *rootView, UIWindow *window) {
    if (!objc_getAssociatedObject(rootView, &kATRatioOriginalFrameKey)) {
        objc_setAssociatedObject(rootView,
                                 &kATRatioOriginalFrameKey,
                                 [NSValue valueWithCGRect:rootView.frame],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView,
                                 &kATRatioOriginalRootClipsKey,
                                 @(rootView.clipsToBounds),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!objc_getAssociatedObject(window, &kATRatioOriginalWindowColorKey)) {
        id originalColor = window.backgroundColor ?: (id)[NSNull null];
        objc_setAssociatedObject(window,
                                 &kATRatioOriginalWindowColorKey,
                                 originalColor,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window,
                                 &kATRatioOriginalWindowClipsKey,
                                 @(window.clipsToBounds),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ATRatioSetFrameWithoutAnimation(UIView *view, CGRect frame) {
    if (!view || ATRatioRectsApproximatelyEqual(view.frame, frame)) return;

    BOOL previous = gATRatioApplyingGeometry;
    gATRatioApplyingGeometry = YES;
    [UIView performWithoutAnimation:^{
        view.frame = frame;
        [view setNeedsLayout];
    }];
    gATRatioApplyingGeometry = previous;
}

static void ATRatioRestoreController(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;

    UIView *rootView = controller.view;
    UIWindow *window = rootView.window;
    if (!window || window.rootViewController != controller) return;

    NSValue *originalFrame = objc_getAssociatedObject(rootView, &kATRatioOriginalFrameKey);
    NSNumber *originalRootClips = objc_getAssociatedObject(rootView, &kATRatioOriginalRootClipsKey);
    if (originalFrame) {
        ATRatioSetFrameWithoutAnimation(rootView, originalFrame.CGRectValue);
        if (originalRootClips) rootView.clipsToBounds = originalRootClips.boolValue;
        objc_setAssociatedObject(rootView, &kATRatioOriginalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView, &kATRatioOriginalRootClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    id originalColor = objc_getAssociatedObject(window, &kATRatioOriginalWindowColorKey);
    NSNumber *originalWindowClips = objc_getAssociatedObject(window, &kATRatioOriginalWindowClipsKey);
    if (originalColor) {
        window.backgroundColor = (originalColor == (id)[NSNull null]) ? nil : originalColor;
        if (originalWindowClips) window.clipsToBounds = originalWindowClips.boolValue;
        objc_setAssociatedObject(window, &kATRatioOriginalWindowColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &kATRatioOriginalWindowClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - Apply only to the selected app's root controller

static void ATRatioApplyToRootController(UIViewController *controller) {
    if (!gATRatioActive || !ATRatioValid(gATRatioTarget) || !controller || !controller.isViewLoaded) return;

    NSString *processBundleID = NSBundle.mainBundle.bundleIdentifier;
    if (![processBundleID isEqualToString:gATRatioTargetBundleID]) return;

    UIView *rootView = controller.view;
    UIWindow *window = rootView.window;
    if (!window || window.rootViewController != controller || !rootView.superview) return;

    ATRatioRememberGeometry(rootView, window);

    /* Letterbox only this app's root content. Do not alter the device screen. */
    window.backgroundColor = UIColor.blackColor;
    window.clipsToBounds = YES;
    rootView.clipsToBounds = YES;

    CGRect targetFrame = ATRatioFrameInSuperview(window, rootView, gATRatioTarget);
    if (!ATRatioRectsApproximatelyEqual(rootView.frame, targetFrame)) {
        ATRatioSetFrameWithoutAnimation(rootView, targetFrame);
        NSLog(@"[AppToolsRatio] Applied %.3f:%.3f to %@ (root=%@)",
              gATRatioTarget.width, gATRatioTarget.height,
              processBundleID, NSStringFromCGRect(rootView.frame));
    }
}

static NSArray<UIWindow *> *ATRatioVisibleWindows(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (!application) return @[];

    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIWindow *window in application.windows) {
        if ([window isKindOfClass:[UIWindow class]] && ![windows containsObject:window]) {
            [windows addObject:window];
        }
    }

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window && ![windows containsObject:window]) [windows addObject:window];
            }
        }
    }
    return windows;
}

static void ATRatioApplyToVisibleWindows(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ ATRatioApplyToVisibleWindows(); });
        return;
    }

    NSString *processBundleID = NSBundle.mainBundle.bundleIdentifier;
    if (![processBundleID isEqualToString:gATRatioTargetBundleID]) return;

    for (UIWindow *window in ATRatioVisibleWindows()) {
        UIViewController *rootController = window.rootViewController;
        if (rootController) ATRatioApplyToRootController(rootController);
    }
}

static void ATRatioRestoreVisibleWindows(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ ATRatioRestoreVisibleWindows(); });
        return;
    }

    NSString *processBundleID = NSBundle.mainBundle.bundleIdentifier;
    if (![processBundleID isEqualToString:gATRatioTargetBundleID]) return;

    for (UIWindow *window in ATRatioVisibleWindows()) {
        UIViewController *rootController = window.rootViewController;
        if (rootController) ATRatioRestoreController(rootController);
    }
}

#pragma mark - Conditional Logos hook

%group ATRatioSelectedTargetApp
%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (self.isViewLoaded && self.view.window && self.view.window.rootViewController == self) {
        ATRatioApplyToRootController(self);
    }
}

%end
%end

#pragma mark - Preference refresh

static void ATRatioReloadForCurrentProcess(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (bundleID.length == 0 ||
        [bundleID isEqualToString:@"com.apple.springboard"] ||
        [bundleID isEqualToString:@"com.flex2areo.apptools"]) return;

    ATRatio selected = {0.0, 0.0};
    BOOL hasRatio = [[ATRatioStore sharedStore] ratioForBundleID:bundleID ratio:&selected] && ATRatioValid(selected);
    NSLog(@"[AppToolsRatio] Runtime config: app=%@ hasRatio=%@ ratio=%0.3f:%0.3f",
          bundleID, hasRatio ? @"YES" : @"NO", selected.width, selected.height);

    if (hasRatio) {
        gATRatioTargetBundleID = [bundleID copy];
        gATRatioTarget = selected;
        gATRatioActive = YES;

        /* Crucial safety guard: install UIKit hooks only for configured apps. */
        if (!gATRatioHooksInstalled) {
            %init(ATRatioSelectedTargetApp);
            gATRatioHooksInstalled = YES;
            NSLog(@"[AppToolsRatio] Installed the single root-controller layout hook in %@", bundleID);
        }

        dispatch_async(dispatch_get_main_queue(), ^{ ATRatioApplyToVisibleWindows(); });
    } else {
        BOOL wasActive = gATRatioActive;
        gATRatioActive = NO;
        gATRatioTarget = ATRatioMake(0.0, 0.0);
        gATRatioTargetBundleID = [bundleID copy];
        if (wasActive) {
            NSLog(@"[AppToolsRatio] Clearing ratio for %@ and restoring original root geometry", bundleID);
            dispatch_async(dispatch_get_main_queue(), ^{ ATRatioRestoreVisibleWindows(); });
        }
        /* If no ratio was ever set, NO UIKit hook is installed in this app. */
    }
}

static void ATRatioPreferenceChanged(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{ ATRatioReloadForCurrentProcess(); });
}

static void ATRatioApplicationDidBecomeActive(NSNotification *notification) {
    (void)notification;
    ATRatioReloadForCurrentProcess();
}

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (bundleID.length == 0 ||
            [bundleID isEqualToString:@"com.apple.springboard"] ||
            [bundleID isEqualToString:@"com.flex2areo.apptools"]) return;

        /*
         * The lightweight Darwin observer is registered in UIKit processes,
         * but no UIView/UIViewController/UIWindow methods are hooked until a
         * valid per-app ratio exists. This also supports changes while app is
         * already running.
         */
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ATRatioPreferenceChanged,
            (__bridge CFStringRef)ATRatioNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        gATRatioActiveObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *notification) {
            ATRatioApplicationDidBecomeActive(notification);
        }];

        dispatch_async(dispatch_get_main_queue(), ^{ ATRatioReloadForCurrentProcess(); });
    }
}
