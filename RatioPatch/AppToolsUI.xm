#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/*
 * AppTools 2.9.0 - replace the existing Message Notification tile.
 *
 * Binary metadata verified against the user's uploaded ratio3 package:
 *   ATPopupViewController
 *     liveActionsBarWithRowStorageKey:
 *     bundleID
 *   ATActionsBarView
 *     rowStorageKey / setRowStorageKey:
 *     addItemWithTitle:detail:image:handler:
 *     finishAddingItems
 *     itemTitles, itemDetails, itemImages, itemHandlers
 *     setTitle:forItemAtIndex:
 *     setDetail:forItemAtIndex:
 *     setItemImages:
 *     setItemHandlers:
 *     rebuildArrangedSubviews
 *
 * The user's screenshot identifies the first item of
 * ATBarLayout_app_row2 as the “Thông báo tin nhắn” bubble tile.
 * We REPLACE that item in-place: same row, same index, same item count.
 * Its old notification handler is overwritten, so the old tile action is
 * no longer reachable from the AppTools panel.
 */

@interface ATActionsBarView : UIView
@property(nonatomic, copy) NSString *rowStorageKey;
@property(nonatomic, copy) NSArray *itemTitles;
@property(nonatomic, copy) NSArray *itemDetails;
- (NSArray *)itemImages;
- (NSArray *)itemHandlers;
- (void)setTitle:(NSString *)title forItemAtIndex:(NSInteger)index;
- (void)setDetail:(NSString *)detail forItemAtIndex:(NSInteger)index;
- (void)setItemImages:(NSMutableArray *)images;
- (void)setItemHandlers:(NSMutableArray *)handlers;
- (void)finishAddingItems;
- (void)rebuildArrangedSubviews;
@end

@interface ATPopupViewController : UIViewController
@property(nonatomic, copy) NSString *bundleID;
- (ATActionsBarView *)liveActionsBarWithRowStorageKey:(NSString *)rowStorageKey;
@end

static NSString * const kATRatioRowKey = @"ATBarLayout_app_row2";
static NSString * const kATRatioTitle = @"Tỉ lệ màn hình";
static char kATRatioPopupAssociationKey;
static char kATRatioRowKeyAssociationKey;
static char kATRatioPatchedAssociationKey;
static char kATRatioApplyingAssociationKey;

#pragma mark - Icon

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

#pragma mark - Replace the notification tile in-place

static ATPopupViewController *ATRatioPopupForBar(ATActionsBarView *bar) {
    NSValue *box = objc_getAssociatedObject(bar, &kATRatioPopupAssociationKey);
    id popup = box ? [box nonretainedObjectValue] : nil;
    if ([popup isKindOfClass:objc_getClass("ATPopupViewController")]) {
        return popup;
    }
    return nil;
}

static BOOL ATRatioReplaceNotificationTile(ATActionsBarView *bar,
                                            ATPopupViewController *popup) {
    if (!bar) return NO;

    NSString *rowKey = bar.rowStorageKey;
    if (rowKey.length == 0) {
        rowKey = objc_getAssociatedObject(bar, &kATRatioRowKeyAssociationKey);
    }
    if (![rowKey isEqualToString:kATRatioRowKey]) return NO;

    if (objc_getAssociatedObject(bar, &kATRatioApplyingAssociationKey)) return NO;

    NSArray *titles = bar.itemTitles;
    NSArray *currentImages = bar.itemImages;
    NSArray *currentHandlers = bar.itemHandlers;
    if (titles.count == 0 || currentImages.count < titles.count || currentHandlers.count < titles.count) {
        NSLog(@"[AppToolsRatio] app_row2 not ready: titles=%lu images=%lu handlers=%lu",
              (unsigned long)titles.count,
              (unsigned long)currentImages.count,
              (unsigned long)currentHandlers.count);
        return NO;
    }

    /* The supplied AppTools 2.9.0 screen shows Message Notification at app_row2[0]. */
    NSUInteger targetIndex = 0;
    NSString *oldTitle = [titles[targetIndex] isKindOfClass:[NSString class]]
        ? titles[targetIndex] : @"";

    if ([oldTitle isEqualToString:kATRatioTitle]) {
        objc_setAssociatedObject(bar,
                                 &kATRatioPatchedAssociationKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }

    if (!popup) popup = ATRatioPopupForBar(bar);
    if (!popup) {
        NSLog(@"[AppToolsRatio] row2 found but popup controller is not attached yet");
        return NO;
    }

    NSString *bundleID = popup.bundleID;
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
        NSLog(@"[AppToolsRatio] popup has no selected application Bundle ID");
        return NO;
    }

    UIImage *ratioIcon = ATRatioCreateIcon();
    if (!ratioIcon) return NO;

    __weak ATPopupViewController *weakPopup = popup;
    NSString *capturedBundleID = [bundleID copy];
    void (^ratioHandler)(void) = ^{
        __strong ATPopupViewController *activePopup = weakPopup;
        if (!activePopup) return;

        NSString *targetBundleID = activePopup.bundleID;
        if (![targetBundleID isKindOfClass:[NSString class]] || targetBundleID.length == 0) {
            targetBundleID = capturedBundleID;
        }
        if (targetBundleID.length == 0) return;

        UIViewController *presenter = activePopup;
        while (presenter.presentedViewController) {
            presenter = presenter.presentedViewController;
        }
        ATRatioShowMenu(targetBundleID, presenter);
    };

    NSMutableArray *images = [currentImages mutableCopy];
    NSMutableArray *handlers = [currentHandlers mutableCopy];
    if (targetIndex >= images.count || targetIndex >= handlers.count) return NO;

    objc_setAssociatedObject(bar,
                             &kATRatioApplyingAssociationKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    /* Replace title, detail, icon and handler at the same slot. */
    [bar setTitle:kATRatioTitle forItemAtIndex:(NSInteger)targetIndex];
    [bar setDetail:@"" forItemAtIndex:(NSInteger)targetIndex];
    images[targetIndex] = ratioIcon;
    handlers[targetIndex] = [ratioHandler copy];
    [bar setItemImages:images];
    [bar setItemHandlers:handlers];
    [bar rebuildArrangedSubviews];

    objc_setAssociatedObject(bar,
                             &kATRatioPatchedAssociationKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar,
                             &kATRatioApplyingAssociationKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"[AppToolsRatio] Replaced app_row2[%lu] '%@' with '%@' for %@",
          (unsigned long)targetIndex,
          oldTitle,
          kATRatioTitle,
          bundleID);
    return YES;
}

static void ATRatioScheduleReplace(ATActionsBarView *bar,
                                   ATPopupViewController *popup) {
    if (!bar) return;

    if (popup) {
        objc_setAssociatedObject(bar,
                                 &kATRatioPopupAssociationKey,
                                 [NSValue valueWithNonretainedObject:popup],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(bar,
                             &kATRatioRowKeyAssociationKey,
                             kATRatioRowKey,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);

    __weak ATActionsBarView *weakBar = bar;
    __weak ATPopupViewController *weakPopup = popup;
    const NSTimeInterval delays[] = {0.0, 0.10, 0.30, 0.65, 1.10};

    for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ATActionsBarView *activeBar = weakBar;
            if (!activeBar) return;
            if (objc_getAssociatedObject(activeBar, &kATRatioPatchedAssociationKey)) return;

            ATPopupViewController *activePopup = weakPopup;
            if (!activePopup) activePopup = ATRatioPopupForBar(activeBar);
            ATRatioReplaceNotificationTile(activeBar, activePopup);
        });
    }
}

#pragma mark - Hooks on AppTools' actual row lifecycle

%group ATRatioAppToolsUI

%hook ATPopupViewController

- (ATActionsBarView *)liveActionsBarWithRowStorageKey:(NSString *)rowStorageKey {
    ATActionsBarView *bar = %orig;
    if (bar && [rowStorageKey isEqualToString:kATRatioRowKey]) {
        NSLog(@"[AppToolsRatio] AppTools requested %@ for %@", rowStorageKey, self.bundleID);
        ATRatioScheduleReplace(bar, (ATPopupViewController *)self);
    }
    return bar;
}

%end

%hook ATActionsBarView

- (void)setRowStorageKey:(NSString *)rowStorageKey {
    %orig;
    if ([rowStorageKey isEqualToString:kATRatioRowKey]) {
        NSLog(@"[AppToolsRatio] app_row2 row key assigned");
        ATRatioScheduleReplace((ATActionsBarView *)self, ATRatioPopupForBar((ATActionsBarView *)self));
    }
}

- (void)finishAddingItems {
    %orig;
    NSString *rowKey = self.rowStorageKey;
    if ([rowKey isEqualToString:kATRatioRowKey] ||
        [objc_getAssociatedObject(self, &kATRatioRowKeyAssociationKey) isEqualToString:kATRatioRowKey]) {
        NSLog(@"[AppToolsRatio] app_row2 finished registering items");
        ATRatioScheduleReplace((ATActionsBarView *)self, ATRatioPopupForBar((ATActionsBarView *)self));
    }
}

%end
%end

#pragma mark - Delayed hook installation

static BOOL gATRatioUIHooksInstalled = NO;
static NSUInteger gATRatioUIInstallAttempts = 0;

static void ATRatioTryInstallUIHooks(void) {
    if (gATRatioUIHooksInstalled) return;

    Class popupClass = objc_getClass("ATPopupViewController");
    Class barClass = objc_getClass("ATActionsBarView");
    if (popupClass && barClass) {
        %init(ATRatioAppToolsUI);
        gATRatioUIHooksInstalled = YES;
        NSLog(@"[AppToolsRatio] UI hooks installed: %@ / %@",
              NSStringFromClass(popupClass), NSStringFromClass(barClass));
        return;
    }

    if (gATRatioUIInstallAttempts++ < 240) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ATRatioTryInstallUIHooks();
        });
    } else {
        NSLog(@"[AppToolsRatio] Cannot install UI hooks. ATPopup=%p ATActionsBar=%p",
              popupClass, barClass);
    }
}

__attribute__((constructor))
static void ATRatioAppToolsUIInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

        NSLog(@"[AppToolsRatio] UI replacement dylib loaded in SpringBoard");
        dispatch_async(dispatch_get_main_queue(), ^{
            ATRatioTryInstallUIHooks();
        });
    }
}
