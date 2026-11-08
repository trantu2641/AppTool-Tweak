#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/*
 * Target-app runtime.
 *
 * The original AppTools package already loads AppTool.dylib into SpringBoard
 * and UIKit processes. This companion runtime uses the same loader coverage,
 * but initializes its hook only in the process whose Bundle ID has a saved
 * ratio. It does NOT hook UIScreen.bounds, UIScreen.applicationFrame,
 * UIWindow.layoutSubviews, or SpringBoard's view controllers.
 *
 * The selected app is displayed inside a centered, aspect-ratio-constrained
 * root view. This changes the app's content viewport, not the physical panel's
 * native resolution.
 */

static NSString *gATRatioTargetBundleID = nil;
static ATRatio gATRatioTarget = {0.0, 0.0};
static BOOL gATRatioRuntimeActive = NO;

static BOOL ATRatioRectsApproximatelyEqual(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.75 &&
           fabs(a.origin.y - b.origin.y) < 0.75 &&
           fabs(a.size.width - b.size.width) < 0.75 &&
           fabs(a.size.height - b.size.height) < 0.75;
}

static CGRect ATRatioViewportInWindow(UIWindow *window, ATRatio ratio) {
    CGRect bounds = window.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 0.0 || height <= 0.0 || ratio.width <= 0.0 || ratio.height <= 0.0) {
        return bounds;
    }

    /* Presets are expressed as long-side:short-side, independent of orientation. */
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

    CGFloat x = CGRectGetMinX(bounds) + (width - targetWidth) * 0.5;
    CGFloat y = CGRectGetMinY(bounds) + (height - targetHeight) * 0.5;
    return CGRectMake(x, y, targetWidth, targetHeight);
}

static void ATRatioApplyToRootController(UIViewController *controller) {
    if (!gATRatioRuntimeActive || !controller || !controller.isViewLoaded) return;

    UIWindow *window = controller.view.window;
    if (!window || window.rootViewController != controller) return;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:gATRatioTargetBundleID]) return;
    if (controller.view.superview == nil) return;

    CGRect viewportInWindow = ATRatioViewportInWindow(window, gATRatioTarget);
    CGRect targetFrame = viewportInWindow;
    if (controller.view.superview != window) {
        targetFrame = [controller.view.superview convertRect:viewportInWindow fromView:window];
    }

    UIView *rootView = controller.view;
    rootView.clipsToBounds = YES;
    window.backgroundColor = UIColor.blackColor;

    if (!ATRatioRectsApproximatelyEqual(rootView.frame, targetFrame)) {
        [UIView performWithoutAnimation:^{
            rootView.frame = targetFrame;
        }];
    }
}

%group ATRatioSelectedTargetApp
%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    ATRatioApplyToRootController(self);
}

%end
%end

__attribute__((constructor))
static void ATRatioTargetRuntimeInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (bundleID.length == 0) return;

        /* Never install the target-app hook inside SpringBoard or AppTools UI. */
        if ([bundleID isEqualToString:@"com.apple.springboard"] ||
            [bundleID isEqualToString:@"com.flex2areo.apptools"]) {
            return;
        }

        ATRatio selected = {0.0, 0.0};
        if (![[ATRatioStore sharedStore] ratioForBundleID:bundleID ratio:&selected]) {
            return;
        }
        if (selected.width <= 0.0 || selected.height <= 0.0) return;

        gATRatioTargetBundleID = [bundleID copy];
        gATRatioTarget = selected;
        gATRatioRuntimeActive = YES;

        /* Install only in the matching app process, and only when configured. */
        %init(ATRatioSelectedTargetApp);
    }
}
