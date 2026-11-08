#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

static NSString *gATRatioTargetBundleID = nil;
static ATRatio gATRatioTarget = {0.0, 0.0};
static BOOL gATRatioActive = NO;
static BOOL gATRatioApplyingGeometry = NO;
static id gATRatioActiveObserver = nil;

static char kATRatioOriginalMaskKey;
static char kATRatioOriginalTranslatesKey;
static char kATRatioOriginalRootClipsKey;
static char kATRatioOriginalWindowColorKey;
static char kATRatioOriginalWindowClipsKey;

#pragma mark - Geometry

static BOOL ATRatioRectsEqual(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.75 &&
           fabs(a.origin.y - b.origin.y) < 0.75 &&
           fabs(a.size.width - b.size.width) < 0.75 &&
           fabs(a.size.height - b.size.height) < 0.75;
}

/* The selected ratios are long-side:short-side. Portrait uses the inverse. */
static CGRect ATRatioViewportFrame(UIWindow *window, ATRatio ratio) {
    CGRect bounds = window.bounds;
    CGFloat screenWidth = CGRectGetWidth(bounds);
    CGFloat screenHeight = CGRectGetHeight(bounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0 || !ATRatioValid(ratio)) {
        return bounds;
    }

    CGFloat shortOverLong = MIN(ratio.width, ratio.height) / MAX(ratio.width, ratio.height);
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
                      targetWidth, targetHeight);
}

static CGRect ATRatioFrameInSuperview(UIWindow *window, UIView *rootView, BOOL enabled) {
    CGRect frameInWindow = (enabled && ATRatioValid(gATRatioTarget))
        ? ATRatioViewportFrame(window, gATRatioTarget)
        : window.bounds;

    if (rootView.superview && rootView.superview != window) {
        return [rootView.superview convertRect:frameInWindow fromView:window];
    }
    return frameInWindow;
}

static void ATRatioSetFrame(UIView *view, CGRect frame) {
    if (!view || ATRatioRectsEqual(view.frame, frame)) return;
    BOOL previous = gATRatioApplyingGeometry;
    gATRatioApplyingGeometry = YES;
    [UIView performWithoutAnimation:^{
        view.frame = frame;
        [view setNeedsLayout];
    }];
    gATRatioApplyingGeometry = previous;
}

#pragma mark - Preserve and restore UIKit geometry

static void ATRatioRememberOriginalState(UIView *rootView, UIWindow *window) {
    if (!objc_getAssociatedObject(rootView, &kATRatioOriginalMaskKey)) {
        objc_setAssociatedObject(rootView, &kATRatioOriginalMaskKey,
                                 @(rootView.autoresizingMask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView, &kATRatioOriginalTranslatesKey,
                                 @(rootView.translatesAutoresizingMaskIntoConstraints), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rootView, &kATRatioOriginalRootClipsKey,
                                 @(rootView.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (!objc_getAssociatedObject(window, &kATRatioOriginalWindowColorKey)) {
        id color = window.backgroundColor ?: (id)[NSNull null];
        objc_setAssociatedObject(window, &kATRatioOriginalWindowColorKey,
                                 color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &kATRatioOriginalWindowClipsKey,
                                 @(window.clipsToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ATRatioRestoreWindow(UIWindow *window, UIView *rootView) {
    if (!window || !rootView) return;

    ATRatioSetFrame(rootView, ATRatioFrameInSuperview(window, rootView, NO));

    NSNumber *mask = objc_getAssociatedObject(rootView, &kATRatioOriginalMaskKey);
    NSNumber *translates = objc_getAssociatedObject(rootView, &kATRatioOriginalTranslatesKey);
    NSNumber *clips = objc_getAssociatedObject(rootView, &kATRatioOriginalRootClipsKey);
    if (mask) rootView.autoresizingMask = (UIViewAutoresizing)mask.unsignedIntegerValue;
    if (translates) rootView.translatesAutoresizingMaskIntoConstraints = translates.boolValue;
    if (clips) rootView.clipsToBounds = clips.boolValue;

    id color = objc_getAssociatedObject(window, &kATRatioOriginalWindowColorKey);
    NSNumber *windowClips = objc_getAssociatedObject(window, &kATRatioOriginalWindowClipsKey);
    if (color) window.backgroundColor = (color == (id)[NSNull null]) ? nil : color;
    if (windowClips) window.clipsToBounds = windowClips.boolValue;

    objc_setAssociatedObject(rootView, &kATRatioOriginalMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(rootView, &kATRatioOriginalTranslatesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(rootView, &kATRatioOriginalRootClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &kATRatioOriginalWindowColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(window, &kATRatioOriginalWindowClipsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Apply to the selected app's actual UIWindow root view

static void ATRatioApplyToWindow(UIWindow *window) {
    if (!window || !NSThread.isMainThread) return;

    NSString *processBundleID = NSBundle.mainBundle.bundleIdentifier;
    if (processBundleID.length == 0 ||
        ![processBundleID isEqualToString:gATRatioTargetBundleID]) return;

    UIViewController *rootController = window.rootViewController;
    UIView *rootView = rootController.viewIfLoaded;
    if (!rootController || !rootView || !rootView.superview) return;

    if (!gATRatioActive || !ATRatioValid(gATRatioTarget)) {
        if (objc_getAssociatedObject(rootView, &kATRatioOriginalMaskKey) ||
            objc_getAssociatedObject(window, &kATRatioOriginalWindowColorKey)) {
            ATRatioRestoreWindow(window, rootView);
            NSLog(@"[AppToolsRatio] Restored full-screen geometry for %@", processBundleID);
        }
        return;
    }

    ATRatioRememberOriginalState(rootView, window);
    window.backgroundColor = UIColor.blackColor;
    window.clipsToBounds = YES;
    rootView.clipsToBounds = YES;
    rootView.autoresizingMask = UIViewAutoresizingNone;
    rootView.translatesAutoresizingMaskIntoConstraints = YES;

    CGRect targetFrame = ATRatioFrameInSuperview(window, rootView, YES);
    if (!ATRatioRectsEqual(rootView.frame, targetFrame)) {
        ATRatioSetFrame(rootView, targetFrame);
        [rootView layoutIfNeeded];
        NSLog(@"[AppToolsRatio] Applied %@ to %@. Window=%@ rootFrame=%@",
              NSStringFromCGSize(CGSizeMake(gATRatioTarget.width, gATRatioTarget.height)),
              processBundleID, NSStringFromCGRect(window.bounds), NSStringFromCGRect(rootView.frame));
    }
}

static NSArray<UIWindow *> *ATRatioApplicationWindows(void) {
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

    for (UIWindow *window in ATRatioApplicationWindows()) {
        ATRatioApplyToWindow(window);
    }
}

#pragma mark - Preference reload and diagnostics

static void ATRatioReloadForCurrentProcess(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (bundleID.length == 0) return;

    if ([bundleID isEqualToString:@"com.apple.springboard"] ||
        [bundleID isEqualToString:@"com.flex2areo.apptools"]) return;

    ATRatio selected = {0.0, 0.0};
    BOOL found = [[ATRatioStore sharedStore] ratioForBundleID:bundleID ratio:&selected];
    gATRatioTargetBundleID = [bundleID copy];
    gATRatioActive = found && ATRatioValid(selected);
    gATRatioTarget = gATRatioActive ? selected : ATRatioMake(0.0, 0.0);

    NSLog(@"[AppToolsRatio] Runtime preference check: bundle=%@ found=%@ active=%@ ratio=%0.3f:%0.3f",
          bundleID, found ? @"YES" : @"NO", gATRatioActive ? @"YES" : @"NO",
          selected.width, selected.height);

    dispatch_async(dispatch_get_main_queue(), ^{ ATRatioApplyToVisibleWindows(); });
}

static void ATRatioPreferenceChanged(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[AppToolsRatio] Received screen-ratio Darwin notification");
        ATRatioReloadForCurrentProcess();
    });
}

static void ATRatioApplicationDidBecomeActive(NSNotification *notification) {
    (void)notification;
    ATRatioReloadForCurrentProcess();
}

#pragma mark - UIKit enforcement hooks

%group ATRatioTargetAppRuntime

%hook UIView

/*
 * UIKit and individual apps often reset the root controller view's frame
 * during layout. Intercept frame assignments for that one view only so the
 * selected viewport remains in effect. Other views are untouched.
 */
- (void)setFrame:(CGRect)frame {
    if (!gATRatioApplyingGeometry && gATRatioActive &&
        [NSBundle.mainBundle.bundleIdentifier isEqualToString:gATRatioTargetBundleID]) {
        UIWindow *window = self.window;
        UIViewController *rootController = window.rootViewController;
        if (window && rootController && rootController.viewIfLoaded == (UIView *)self && self.superview) {
            CGRect forcedFrame = ATRatioFrameInSuperview(window, (UIView *)self, YES);
            %orig(forcedFrame);
            return;
        }
    }
    %orig(frame);
}

%end

%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    UIWindow *window = self.viewIfLoaded.window;
    if (window && window.rootViewController == self) ATRatioApplyToWindow(window);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIWindow *window = self.viewIfLoaded.window;
    if (window && window.rootViewController == self) ATRatioApplyToWindow(window);
}

%end

%hook UIWindow

- (void)setRootViewController:(UIViewController *)rootViewController {
    %orig(rootViewController);
    dispatch_async(dispatch_get_main_queue(), ^{ ATRatioApplyToWindow((UIWindow *)self); });
}

- (void)makeKeyAndVisible {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ ATRatioApplyToWindow((UIWindow *)self); });
}

%end
%end

#pragma mark - Runtime constructor

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (bundleID.length == 0 ||
            [bundleID isEqualToString:@"com.apple.springboard"] ||
            [bundleID isEqualToString:@"com.flex2areo.apptools"]) return;

        NSLog(@"[AppToolsRatio] Target-app runtime loaded in %@", bundleID);

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

        %init(ATRatioTargetAppRuntime);
        ATRatioReloadForCurrentProcess();
    }
}
