#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/*
 * App-specific viewport runtime.
 *
 * The process reads its own Bundle ID's ratio from ATRatioStore. AppTools
 * publishes a Darwin notification when the value changes. The UIViewController
 * hook is installed once from %ctor for eligible UIKit app processes; the hook
 * body does nothing unless the current process has a saved ratio.
 *
 * This implementation does not hook UIScreen.bounds,
 * UIScreen.applicationFrame, or UIWindow.layoutSubviews.
 */

static NSString *gATRatioTargetBundleID = nil;
static ATRatio gATRatioTarget = {0.0, 0.0};
static BOOL gATRatioActive = NO;
static id gATRatioActiveObserver = nil;

static char kATRatioOriginalFrameKey;
static char kATRatioOriginalAutoresizingMaskKey;
static char kATRatioOriginalClipsKey;
static char kATRatioOriginalWindowBackgroundKey;
static char kATRatioOriginalWindowClipsKey;

#pragma mark - Geometry

static BOOL ATRatioRectsEqual(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.75 &&
           fabs(a.origin.y - b.origin.y) < 0.75 &&
           fabs(a.size.width - b.size.width) < 0.75 &&
           fabs(a.size.height - b.size.height) < 0.75;
}

/* Presets are expressed as long-side:short-side (16:9, 4:3, ...). */
static CGRect ATRatioViewportFrame(UIWindow *window, ATRatio ratio) {
    CGRect bounds = window.bounds;
    CGFloat screenWidth = CGRectGetWidth(bounds);
    CGFloat screenHeight = CGRectGetHeight(bounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0 ||
        !ATRatioValid(ratio)) {
        return bounds;
    }

    CGFloat shortOverLong = MIN(ratio.width, ratio.height) /
                            MAX(ratio.width, ratio.height);
    BOOL portrait = screenHeight >= screenWidth;

    CGFloat targetWidth = screenWidth;
    CGFloat targetHeight = screenHeight;

    if (portrait) {
        targetHeight = targetWidth / shortOverLong;
        if (targetHeight > screenHeight) {
            targetHeight = screenHeight;
            targetWidth = targetHeight * shortOverLong;
        }
    } else {
        targetWidth = targetHeight / shortOverLong;
        if (targetWidth > screenWidth) {
            targetWidth = screenWidth;
            targetHeight = targetWidth * shortOverLong;
        }
    }

    return CGRectMake(CGRectGetMinX(bounds) + (screenWidth - targetWidth) * 0.5,
                      CGRectGetMinY(bounds) + (screenHeight - targetHeight) * 0.5,
                      targetWidth,
                      targetHeight);
}

#pragma mark - Save and restore original view geometry

static void ATRatioRememberOriginalGeometry(UIView *rootView, UIWindow *window) {
    if (!objc_getAssociatedObject(rootView, &kATRatioOriginalFrameKey)) {
        objc_setAssociatedObject(rootView,
                                 &kATRatioOriginalFrameKey,
                                 [NSValue valueWithCGRect:rootView.frame],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView,
                                 &kATRatioOriginalAutoresizingMaskKey,
                                 @(rootView.autoresizingMask),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView,
                                 &kATRatioOriginalClipsKey,
                                 @(rootView.clipsToBounds),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!objc_getAssociatedObject(window, &kATRatioOriginalWindowBackgroundKey)) {
        id background = window.backgroundColor ?: (id)[NSNull null];
        objc_setAssociatedObject(window,
                                 &kATRatioOriginalWindowBackgroundKey,
                                 background,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window,
                                 &kATRatioOriginalWindowClipsKey,
                                 @(window.clipsToBounds),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ATRatioRestoreOriginalGeometry(UIView *rootView, UIWindow *window) {
    NSValue *originalFrame = objc_getAssociatedObject(rootView, &kATRatioOriginalFrameKey);
    NSNumber *originalMask = objc_getAssociatedObject(rootView, &kATRatioOriginalAutoresizingMaskKey);
    NSNumber *originalClips = objc_getAssociatedObject(rootView, &kATRatioOriginalClipsKey);

    if (originalFrame) {
        rootView.frame = originalFrame.CGRectValue;
        if (originalMask) {
            rootView.autoresizingMask = (UIViewAutoresizing)originalMask.unsignedIntegerValue;
        }
        if (originalClips) rootView.clipsToBounds = originalClips.boolValue;
        [rootView setNeedsLayout];

        objc_setAssociatedObject(rootView, &kATRatioOriginalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView, &kATRatioOriginalAutoresizingMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView, &kATRatioOriginalClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    id originalBackground = objc_getAssociatedObject(window, &kATRatioOriginalWindowBackgroundKey);
    NSNumber *originalWindowClips = objc_getAssociatedObject(window, &kATRatioOriginalWindowClipsKey);
    if (originalBackground) {
        window.backgroundColor = (originalBackground == (id)[NSNull null]) ? nil : originalBackground;
        if (originalWindowClips) window.clipsToBounds = originalWindowClips.boolValue;
        objc_setAssociatedObject(window, &kATRatioOriginalWindowBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &kATRatioOriginalWindowClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - Apply to this app's root controller only

static void ATRatioApplyToRootController(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;

    UIWindow *window = controller.view.window;
    if (!window || window.rootViewController != controller) return;

    NSString *processBundleID = NSBundle.mainBundle.bundleIdentifier;
    if (processBundleID.length == 0 ||
        ![processBundleID isEqualToString:gATRatioTargetBundleID]) {
        return;
    }

    UIView *rootView = controller.view;
    if (!rootView.superview) return;

    if (!gATRatioActive || !ATRatioValid(gATRatioTarget)) {
        ATRatioRestoreOriginalGeometry(rootView, window);
        return;
    }

    ATRatioRememberOriginalGeometry(rootView, window);

    CGRect frameInWindow = ATRatioViewportFrame(window, gATRatioTarget);
    CGRect targetFrame = frameInWindow;
    if (rootView.superview != window) {
        targetFrame = [rootView.superview convertRect:frameInWindow fromView:window];
    }

    window.backgroundColor = UIColor.blackColor;
    window.clipsToBounds = YES;
    rootView.clipsToBounds = YES;
    rootView.autoresizingMask = UIViewAutoresizingNone;

    if (!ATRatioRectsEqual(rootView.frame, targetFrame)) {
        [UIView performWithoutAnimation:^{
            rootView.frame = targetFrame;
            [rootView setNeedsLayout];
        }];
    }
}

static void ATRatioApplyToVisibleWindows(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ATRatioApplyToVisibleWindows();
        });
        return;
    }

    UIApplication *application = UIApplication.sharedApplication;
    for (UIWindow *window in application.windows) {
        UIViewController *rootController = window.rootViewController;
        if (rootController && rootController.isViewLoaded) {
            ATRatioApplyToRootController(rootController);
        }
    }
}

#pragma mark - Logos group declaration

/*
 * IMPORTANT: Define the Logos group before the %ctor that initializes it.
 * Logos %init cannot be called from a plain C helper function.
 */
%group ATRatioSelectedTargetApp
%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    ATRatioApplyToRootController(self);
}

%end
%end

#pragma mark - Read the current process's preference domain

static void ATRatioReloadForCurrentProcess(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (bundleID.length == 0) return;

    /* Never change SpringBoard or AppTools' own interface. */
    if ([bundleID isEqualToString:@"com.apple.springboard"] ||
        [bundleID isEqualToString:@"com.flex2areo.apptools"]) {
        return;
    }

    ATRatio selected = {0.0, 0.0};
    BOOL hasRatio = [[ATRatioStore sharedStore] ratioForBundleID:bundleID ratio:&selected];

    if (hasRatio && ATRatioValid(selected)) {
        gATRatioTargetBundleID = [bundleID copy];
        gATRatioTarget = selected;
        gATRatioActive = YES;
    } else {
        gATRatioActive = NO;
        gATRatioTarget.width = 0.0;
        gATRatioTarget.height = 0.0;
        gATRatioTargetBundleID = [bundleID copy];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        ATRatioApplyToVisibleWindows();
    });
}

static void ATRatioPreferenceChanged(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        ATRatioReloadForCurrentProcess();
    });
}

static void ATRatioApplicationDidBecomeActive(NSNotification *notification) {
    (void)notification;
    ATRatioReloadForCurrentProcess();
}

#pragma mark - Logos constructor

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (bundleID.length == 0) return;

        /* Never install the target-app hook in SpringBoard or AppTools itself. */
        if ([bundleID isEqualToString:@"com.apple.springboard"] ||
            [bundleID isEqualToString:@"com.flex2areo.apptools"]) {
            return;
        }

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ATRatioPreferenceChanged,
            (__bridge CFStringRef)ATRatioNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        if (gATRatioActiveObserver == nil) {
            gATRatioActiveObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *notification) {
                ATRatioApplicationDidBecomeActive(notification);
            }];
        }

        /*
         * Install the hook once at constructor time. The hook body is inert
         * until this process has a valid saved ratio. This keeps %init inside
         * a Logos block and allows later Darwin notifications to activate it.
         */
        ATRatioReloadForCurrentProcess();
        %init(ATRatioSelectedTargetApp);
    }
}
