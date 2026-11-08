#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/*
 * AppTools 2.9.0 UI integration.
 *
 * Verified in the original AppTool.dylib Objective-C metadata:
 * ATPopupViewController:
 *   - viewDidLayoutSubviews
 *   - bundleID
 *   - liveActionsBarWithRowStorageKey:
 * ATActionsBarView:
 *   - rowStorageKey
 *   - itemTitles / itemDetails / itemImages / itemHandlers
 *   - setTitle:forItemAtIndex:
 *   - setDetail:forItemAtIndex:
 *   - setItemImages:
 *   - setItemHandlers:
 *   - rebuildArrangedSubviews
 *
 * This patch does not create a floating UIButton and does not hook
 * UIScreen or UIWindow. It replaces the first existing tile in app_row2
 * (the tile shown as "Thông báo tin nhắn" in the supplied screenshot).
 */

@interface ATActionsBarView : UIView
@property(nonatomic, readonly, copy) NSString *rowStorageKey;
@property(nonatomic, readonly, copy) NSMutableArray *itemTitles;
@property(nonatomic, readonly, copy) NSMutableArray *itemDetails;
@property(nonatomic, readonly, copy) NSMutableArray *itemImages;
@property(nonatomic, readonly, copy) NSMutableArray *itemHandlers;
- (void)setTitle:(NSString *)title forItemAtIndex:(NSInteger)index;
- (void)setDetail:(NSString *)detail forItemAtIndex:(NSInteger)index;
- (void)setItemImages:(NSMutableArray *)images;
- (void)setItemHandlers:(NSMutableArray *)handlers;
- (void)rebuildArrangedSubviews;
@end

@interface ATPopupViewController : UIViewController
@property(nonatomic, readonly, copy) NSString *bundleID;
- (ATActionsBarView *)liveActionsBarWithRowStorageKey:(NSString *)rowStorageKey;
@end

static NSString * const kATRatioRowKey = @"ATBarLayout_app_row2";
static NSString * const kATRatioTitle = @"Tỉ lệ màn hình";
static char kATRatioInstalledOnPopupKey;
static BOOL gATRatioHooksInstalled = NO;
static NSUInteger gATRatioHookInstallAttempts = 0;

#pragma mark - Tile icon

static UIImage *ATRatioCreateIcon(void) {
    CGSize size = CGSizeMake(64.0, 64.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }

    UIColor *cyan = [UIColor colorWithRed:0.08 green:0.66 blue:0.96 alpha:1.0];
    CGContextSetStrokeColorWithColor(context, cyan.CGColor);
    CGContextSetLineWidth(context, 3.2);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    UIBezierPath *screen = [UIBezierPath bezierPathWithRoundedRect:
        CGRectMake(10.0, 6.0, 44.0, 52.0) cornerRadius:9.0];
    screen.lineWidth = 3.2;
    [screen stroke];

    UIBezierPath *guides = [UIBezierPath bezierPath];
    guides.lineWidth = 2.8;
    [guides moveToPoint:CGPointMake(18.0, 22.0)];
    [guides addLineToPoint:CGPointMake(46.0, 22.0)];
    [guides moveToPoint:CGPointMake(18.0, 42.0)];
    [guides addLineToPoint:CGPointMake(46.0, 42.0)];
    [guides moveToPoint:CGPointMake(32.0, 14.0)];
    [guides addLineToPoint:CGPointMake(32.0, 50.0)];
    [guides stroke];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

#pragma mark - Menu

static UIViewController *ATRatioTopController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current.presentedViewController) {
        current = current.presentedViewController;
    }
    return current;
}

static void ATRatioConfigurePopover(UIAlertController *alert,
                                    UIViewController *presenter) {
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (!popover || !presenter.isViewLoaded) return;
    popover.sourceView = presenter.view;
    popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds),
                                    CGRectGetMidY(presenter.view.bounds),
                                    1.0, 1.0);
    popover.permittedArrowDirections = 0;
}

static void ATRatioShowMenu(NSString *bundleID, UIViewController *presenter);

static void ATRatioShowCustomInput(NSString *bundleID,
                                   UIViewController *presenter) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tùy chỉnh tỉ lệ màn hình"
                         message:@"Nhập chiều rộng và chiều cao"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Chiều rộng, ví dụ 16 hoặc 19,5";
        field.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Chiều cao, ví dụ 9";
        field.keyboardType = UIKeyboardTypeDecimalPad;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        NSString *widthText = [alert.textFields[0].text
            stringByReplacingOccurrencesOfString:@"," withString:@"."];
        NSString *heightText = [alert.textFields[1].text
            stringByReplacingOccurrencesOfString:@"," withString:@"."];
        CGFloat width = widthText.doubleValue;
        CGFloat height = heightText.doubleValue;

        if (!isfinite(width) || !isfinite(height) || width <= 0.0 || height <= 0.0) {
            UIAlertController *error = [UIAlertController
                alertControllerWithTitle:@"Giá trị không hợp lệ"
                                 message:@"Chiều rộng và chiều cao phải là số lớn hơn 0."
                          preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"Đóng"
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil]];
            [presenter presentViewController:error animated:YES completion:nil];
            return;
        }

        [[ATRatioStore sharedStore]
            setRatio:ATRatioMake(width, height)
            forBundleID:bundleID];
    }]];

    [presenter presentViewController:alert animated:YES completion:nil];
}

static void ATRatioShowMenu(NSString *bundleID, UIViewController *presenter) {
    if (bundleID.length == 0 || !presenter) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tỉ lệ màn hình"
                         message:[NSString stringWithFormat:@"Ứng dụng: %@", bundleID]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Tự động"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        [[ATRatioStore sharedStore] removeRatioForBundleID:bundleID];
    }]];

    NSArray<NSDictionary *> *presets = @[
        @{ @"title": @"16:9",   @"width": @16.0,  @"height": @9.0 },
        @{ @"title": @"4:3",    @"width": @4.0,   @"height": @3.0 },
        @{ @"title": @"3:2",    @"width": @3.0,   @"height": @2.0 },
        @{ @"title": @"18:9",   @"width": @18.0,  @"height": @9.0 },
        @{ @"title": @"19,5:9", @"width": @19.5,  @"height": @9.0 },
        @{ @"title": @"21:9",   @"width": @21.0,  @"height": @9.0 }
    ];

    for (NSDictionary *preset in presets) {
        NSString *title = preset[@"title"];
        CGFloat width = [preset[@"width"] doubleValue];
        CGFloat height = [preset[@"height"] doubleValue];
        [alert addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [[ATRatioStore sharedStore]
                setRatio:ATRatioMake(width, height)
                forBundleID:bundleID];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Tùy chỉnh thủ công"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        ATRatioShowCustomInput(bundleID, presenter);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    ATRatioConfigurePopover(alert, presenter);
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Find AppTools app_row2

static ATActionsBarView *ATRatioFindAppRow2(ATPopupViewController *popup) {
    if (!popup) return nil;

    /* Preferred, documented-by-runtime accessor from ATPopupViewController. */
    ATActionsBarView *bar = nil;
    @try {
        bar = [popup liveActionsBarWithRowStorageKey:kATRatioRowKey];
    } @catch (NSException *exception) {
        NSLog(@"[AppToolsRatio] liveActionsBar lookup exception: %@", exception);
    }
    if (bar) {
        NSString *resolvedKey = bar.rowStorageKey;
        if (resolvedKey.length == 0 || [resolvedKey isEqualToString:kATRatioRowKey]) {
            return bar;
        }
    }

    /* Fallback: locate the existing row in the popup's view hierarchy. */
    if (!popup.isViewLoaded) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:popup.view];
    NSUInteger cursor = 0;
    while (cursor < queue.count && cursor < 4096) {
        UIView *view = queue[cursor++];
        if ([NSStringFromClass(view.class) isEqualToString:@"ATActionsBarView"]) {
            ATActionsBarView *candidate = (ATActionsBarView *)view;
            if ([candidate.rowStorageKey isEqualToString:kATRatioRowKey]) {
                return candidate;
            }
        }
        [queue addObjectsFromArray:view.subviews ?: @[]];
    }
    return nil;
}

#pragma mark - Replace the existing "Thông báo tin nhắn" tile

static BOOL ATRatioReplaceFirstTile(ATPopupViewController *popup) {
    if (!popup) return NO;

    ATActionsBarView *bar = ATRatioFindAppRow2(popup);
    if (!bar) {
        NSLog(@"[AppToolsRatio] app_row2 not ready for %@", popup.bundleID);
        return NO;
    }

    NSArray *titles = bar.itemTitles;
    NSMutableArray *images = [bar.itemImages mutableCopy];
    NSMutableArray *handlers = [bar.itemHandlers mutableCopy];
    NSArray *details = bar.itemDetails;

    if (titles.count == 0 || images.count == 0 || handlers.count == 0) {
        NSLog(@"[AppToolsRatio] app_row2 arrays not ready. titles=%lu images=%lu handlers=%lu details=%lu",
              (unsigned long)titles.count,
              (unsigned long)images.count,
              (unsigned long)handlers.count,
              (unsigned long)details.count);
        return NO;
    }

    NSString *oldTitle = [titles.firstObject isKindOfClass:[NSString class]]
        ? titles.firstObject : @"";
    if ([oldTitle isEqualToString:kATRatioTitle]) return YES;

    __weak ATPopupViewController *weakPopup = popup;
    void (^ratioHandler)(void) = ^{
        __strong ATPopupViewController *strongPopup = weakPopup;
        if (!strongPopup) return;
        NSString *bundleID = strongPopup.bundleID;
        if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
            NSLog(@"[AppToolsRatio] selected app Bundle ID is empty");
            return;
        }
        UIViewController *presenter = ATRatioTopController(strongPopup);
        ATRatioShowMenu(bundleID, presenter);
    };

    UIImage *icon = ATRatioCreateIcon();
    if (!icon) return NO;

    /* Keep the original row size and position: change only item index 0. */
    [bar setTitle:kATRatioTitle forItemAtIndex:0];
    [bar setDetail:nil forItemAtIndex:0];
    images[0] = icon;
    handlers[0] = [ratioHandler copy];
    [bar setItemImages:images];
    [bar setItemHandlers:handlers];
    [bar rebuildArrangedSubviews];

    NSLog(@"[AppToolsRatio] Replaced app_row2 item '%@' with '%@' for %@",
          oldTitle, kATRatioTitle, popup.bundleID);
    return YES;
}

#pragma mark - SpringBoard hook

%group ATRatioAppToolsUI
%hook ATPopupViewController

- (void)viewDidLayoutSubviews {
    %orig;

    if (objc_getAssociatedObject(self, &kATRatioInstalledOnPopupKey)) return;

    __weak ATPopupViewController *weakPopup = (ATPopupViewController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong ATPopupViewController *popup = weakPopup;
        if (!popup) return;

        if (ATRatioReplaceFirstTile(popup)) {
            objc_setAssociatedObject(popup,
                                     &kATRatioInstalledOnPopupKey,
                                     @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

%end
%end

#pragma mark - Delayed installation and diagnostics

static void ATRatioTryInstallHooks(void) {
    if (gATRatioHooksInstalled) return;

    Class popupClass = objc_getClass("ATPopupViewController");
    Class barClass = objc_getClass("ATActionsBarView");

    if (popupClass && barClass) {
        %init(ATRatioAppToolsUI);
        gATRatioHooksInstalled = YES;
        NSLog(@"[AppToolsRatio] UI hook installed. popup=%@ bar=%@",
              NSStringFromClass(popupClass), NSStringFromClass(barClass));
        return;
    }

    if (gATRatioHookInstallAttempts++ < 240) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ATRatioTryInstallHooks();
        });
    } else {
        NSLog(@"[AppToolsRatio] UI hook not installed. popup=%p bar=%p",
              popupClass, barClass);
    }
}

__attribute__((constructor))
static void ATRatioAppToolsUIInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

        NSLog(@"[AppToolsRatio] UI patch dylib loaded in SpringBoard");
        dispatch_async(dispatch_get_main_queue(), ^{
            ATRatioTryInstallHooks();
        });
    }
}
