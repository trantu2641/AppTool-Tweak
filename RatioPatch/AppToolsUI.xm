#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/* AppTools 2.9.0 private interfaces confirmed from AppTool.dylib metadata. */
@interface ATActionsBarView : UIView
@property(nonatomic, copy) NSString *rowStorageKey;
@property(nonatomic, copy) NSArray *itemTitles;
- (NSArray *)itemImages;
- (NSArray *)itemHandlers;
- (void)setItemImages:(NSMutableArray *)images;
- (void)setItemHandlers:(NSMutableArray *)handlers;
- (void)setTitle:(NSString *)title forItemAtIndex:(NSInteger)index;
- (void)setDetail:(NSString *)detail forItemAtIndex:(NSInteger)index;
- (void)rebuildArrangedSubviews;
- (void)addItemWithTitle:(NSString *)title
                  detail:(NSString *)detail
                   image:(UIImage *)image
                 handler:(void (^)(void))handler;
- (void)finishAddingItems;
@end

@interface ATPopupViewController : UIViewController
@property(nonatomic, copy) NSString *bundleID;
- (ATActionsBarView *)liveActionsBarWithRowStorageKey:(NSString *)rowStorageKey;
@end

static NSString * const kATRatioRowKey = @"ATBarLayout_app_row2";
static NSString * const kATRatioTitle = @"Tỉ lệ màn hình";
static char kATRatioRowKeyAssociation;
static char kATRatioPopupAssociation;
static char kATRatioItemCountAssociation;
static char kATRatioDidReplaceAssociation;
static char kATRatioApplyingAssociation;
static char kATRatioDidRebuildAssociation;

/* Context set while AppTools builds a row. */
static ATPopupViewController *gATRatioBuildingPopup = nil;
static NSString *gATRatioBuildingRowKey = nil;
static ATPopupViewController *gATRatioVisiblePopup = nil;

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

#pragma mark - Popup lookup

static ATPopupViewController *ATRatioPopupForBar(ATActionsBarView *bar) {
    Class popupClass = objc_getClass("ATPopupViewController");
    UIResponder *responder = bar;
    NSUInteger depth = 0;
    while (responder && depth++ < 80) {
        if (popupClass && [responder isKindOfClass:popupClass]) {
            return (ATPopupViewController *)responder;
        }
        responder = responder.nextResponder;
    }

    NSValue *stored = objc_getAssociatedObject(bar, &kATRatioPopupAssociation);
    id popup = stored ? [stored nonretainedObjectValue] : nil;
    if (popupClass && [popup isKindOfClass:popupClass]) {
        return (ATPopupViewController *)popup;
    }
    return gATRatioVisiblePopup ?: gATRatioBuildingPopup;
}

static UIViewController *ATRatioTopController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current.presentedViewController) {
        current = current.presentedViewController;
    }
    return current;
}

#pragma mark - Ratio menu

static void ATRatioConfigurePopover(UIAlertController *alert,
                                    UIViewController *presenter) {
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (!popover || !presenter.isViewLoaded) return;
    popover.sourceView = presenter.view;
    popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds),
                                    CGRectGetMidY(presenter.view.bounds), 1.0, 1.0);
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
    if (bundleID.length == 0 || !presenter) {
        NSLog(@"[AppToolsRatio] Cannot show ratio menu: missing Bundle ID or presenter");
        return;
    }

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


#pragma mark - Registered item replacement fallback

static BOOL ATRatioReplaceRegisteredTile(ATActionsBarView *bar,
                                         ATPopupViewController *popup,
                                         BOOL rebuildIfNeeded) {
    if (!bar) return NO;

    NSString *rowKey = bar.rowStorageKey;
    if (rowKey.length == 0) rowKey = objc_getAssociatedObject(bar, &kATRatioRowKeyAssociation);
    if (![rowKey isEqualToString:kATRatioRowKey]) return NO;
    if ([objc_getAssociatedObject(bar, &kATRatioApplyingAssociation) boolValue]) return NO;

    NSArray *titles = bar.itemTitles;
    NSArray *currentImages = bar.itemImages;
    NSArray *currentHandlers = bar.itemHandlers;
    if (titles.count == 0 || currentImages.count < titles.count || currentHandlers.count < titles.count) {
        NSLog(@"[AppToolsRatio] app_row2 models not ready: titles=%lu images=%lu handlers=%lu",
              (unsigned long)titles.count, (unsigned long)currentImages.count,
              (unsigned long)currentHandlers.count);
        return NO;
    }

    NSUInteger targetIndex = 0;
    NSString *oldTitle = [titles[targetIndex] isKindOfClass:[NSString class]]
        ? titles[targetIndex] : @"";
    if ([oldTitle isEqualToString:kATRatioTitle]) {
        objc_setAssociatedObject(bar, &kATRatioDidReplaceAssociation,
                                 @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (rebuildIfNeeded &&
            ![objc_getAssociatedObject(bar, &kATRatioDidRebuildAssociation) boolValue]) {
            objc_setAssociatedObject(bar, &kATRatioApplyingAssociation,
                                     @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [bar rebuildArrangedSubviews];
            objc_setAssociatedObject(bar, &kATRatioApplyingAssociation,
                                     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(bar, &kATRatioDidRebuildAssociation,
                                     @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return NO;
    }

    if (!popup) popup = ATRatioPopupForBar(bar);
    if (!popup) popup = gATRatioVisiblePopup ?: gATRatioBuildingPopup;
    NSString *bundleIDAtCreation = [popup.bundleID copy];
    __weak ATPopupViewController *weakPopup = popup;
    __weak ATActionsBarView *weakBar = bar;

    void (^ratioHandler)(void) = ^{
        ATPopupViewController *activePopup = weakPopup;
        if (!activePopup) activePopup = ATRatioPopupForBar(weakBar);
        if (!activePopup) activePopup = gATRatioVisiblePopup;
        NSString *bundleID = activePopup.bundleID;
        if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
            bundleID = bundleIDAtCreation;
        }
        if (!activePopup || bundleID.length == 0) {
            NSLog(@"[AppToolsRatio] Tỉ lệ button tapped, but no selected app Bundle ID");
            return;
        }
        ATRatioShowMenu(bundleID, ATRatioTopController(activePopup));
    };

    NSMutableArray *images = [currentImages mutableCopy];
    NSMutableArray *handlers = [currentHandlers mutableCopy];
    if (targetIndex >= images.count || targetIndex >= handlers.count) return NO;

    objc_setAssociatedObject(bar, &kATRatioApplyingAssociation,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    /* The screenshot identifies this exact cell as the first tile in app_row2. */
    [bar setTitle:kATRatioTitle forItemAtIndex:(NSInteger)targetIndex];
    [bar setDetail:@"" forItemAtIndex:(NSInteger)targetIndex];
    images[targetIndex] = ATRatioCreateIcon() ?: images[targetIndex];
    handlers[targetIndex] = [ratioHandler copy];
    [bar setItemImages:images];
    [bar setItemHandlers:handlers];

    objc_setAssociatedObject(bar, &kATRatioDidReplaceAssociation,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[AppToolsRatio] Replaced existing app_row2[0] '%@' with '%@' (bundle=%@)",
          oldTitle, kATRatioTitle, bundleIDAtCreation ?: @"<not-set-yet>");

    if (rebuildIfNeeded) {
        /* The applying flag makes the rebuild hook pass straight to %orig. */
        [bar rebuildArrangedSubviews];
        objc_setAssociatedObject(bar, &kATRatioDidRebuildAssociation,
                                 @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(bar, &kATRatioApplyingAssociation,
                             nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

#pragma mark - Replace the notification tile inside AppTools' own panel

%group ATRatioCreateTimeUI

%hook ATPopupViewController

- (void)viewDidLoad {
    %orig;
    gATRatioVisiblePopup = (ATPopupViewController *)self;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (gATRatioVisiblePopup == (ATPopupViewController *)self) {
        gATRatioVisiblePopup = nil;
    }
}

- (void)viewDidLayoutSubviews {
    %orig;

    /*
     * This is the panel that contains the feature grid shown in the user's
     * screenshot. Ask AppTools for its real app_row2 bar after layout, rather
     * than assuming the bar was populated during liveActionsBar... itself.
     */
    gATRatioVisiblePopup = (ATPopupViewController *)self;
    ATActionsBarView *bar = [self liveActionsBarWithRowStorageKey:kATRatioRowKey];
    if (bar) {
        objc_setAssociatedObject(bar, &kATRatioRowKeyAssociation,
                                 kATRatioRowKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(bar, &kATRatioPopupAssociation,
                                 [NSValue valueWithNonretainedObject:self],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ATRatioReplaceRegisteredTile(bar, (ATPopupViewController *)self, YES);
    }
}

- (ATActionsBarView *)liveActionsBarWithRowStorageKey:(NSString *)rowStorageKey {
    ATPopupViewController *previousPopup = gATRatioBuildingPopup;
    NSString *previousRowKey = gATRatioBuildingRowKey;
    gATRatioBuildingPopup = (ATPopupViewController *)self;
    gATRatioBuildingRowKey = [rowStorageKey copy];

    ATActionsBarView *bar = %orig;
    if (bar) {
        objc_setAssociatedObject(bar, &kATRatioRowKeyAssociation,
                                 rowStorageKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(bar, &kATRatioPopupAssociation,
                                 [NSValue valueWithNonretainedObject:self],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([rowStorageKey isEqualToString:kATRatioRowKey]) {
            NSLog(@"[AppToolsRatio] AppTools returned app_row2 bar for %@", self.bundleID);
            ATRatioReplaceRegisteredTile(bar, (ATPopupViewController *)self, NO);
        }
    }

    gATRatioBuildingPopup = previousPopup;
    gATRatioBuildingRowKey = previousRowKey;
    return bar;
}

%end

%hook ATActionsBarView

- (void)setRowStorageKey:(NSString *)rowStorageKey {
    %orig;
    objc_setAssociatedObject(self, &kATRatioRowKeyAssociation,
                             rowStorageKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(self, &kATRatioItemCountAssociation,
                             @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (gATRatioBuildingPopup) {
        objc_setAssociatedObject(self, &kATRatioPopupAssociation,
                                 [NSValue valueWithNonretainedObject:gATRatioBuildingPopup],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([rowStorageKey isEqualToString:kATRatioRowKey]) {
        NSLog(@"[AppToolsRatio] AppTools assigned app_row2 to %@", self);
    }
}

/*
 * First chance: replace the arguments before AppTools stores/builds the tile.
 */
- (void)addItemWithTitle:(NSString *)title
                  detail:(NSString *)detail
                   image:(UIImage *)image
                 handler:(void (^)(void))handler {
    NSString *rowKey = self.rowStorageKey;
    if (rowKey.length == 0) {
        rowKey = objc_getAssociatedObject(self, &kATRatioRowKeyAssociation);
    }
    if (rowKey.length == 0 && gATRatioBuildingRowKey.length > 0) {
        rowKey = gATRatioBuildingRowKey;
    }

    NSNumber *counter = objc_getAssociatedObject(self, &kATRatioItemCountAssociation);
    NSUInteger registeredIndex = counter ? counter.unsignedIntegerValue : 0;
    NSUInteger titlesIndex = self.itemTitles.count;
    NSUInteger itemIndex = MAX(registeredIndex, titlesIndex);
    objc_setAssociatedObject(self, &kATRatioItemCountAssociation,
                             @(itemIndex + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (![rowKey isEqualToString:kATRatioRowKey]) {
        %orig(title, detail, image, handler);
        return;
    }

    NSLog(@"[AppToolsRatio] app_row2 addItem[%lu]: %@",
          (unsigned long)itemIndex, title);

    if (itemIndex == 0 &&
        ![title isEqualToString:kATRatioTitle] &&
        ![objc_getAssociatedObject(self, &kATRatioDidReplaceAssociation) boolValue]) {
        ATActionsBarView *bar = (ATActionsBarView *)self;
        ATPopupViewController *popup = ATRatioPopupForBar(bar);
        if (!popup) popup = gATRatioBuildingPopup ?: gATRatioVisiblePopup;
        NSString *bundleIDAtCreation = [popup.bundleID copy];
        __weak ATPopupViewController *weakPopup = popup;
        __weak ATActionsBarView *weakBar = bar;

        void (^ratioHandler)(void) = ^{
            ATPopupViewController *activePopup = weakPopup;
            if (!activePopup) activePopup = ATRatioPopupForBar(weakBar);
            if (!activePopup) activePopup = gATRatioVisiblePopup;
            NSString *bundleID = activePopup.bundleID;
            if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
                bundleID = bundleIDAtCreation;
            }
            if (!activePopup || bundleID.length == 0) {
                NSLog(@"[AppToolsRatio] Tile tapped, but active app Bundle ID is unavailable");
                return;
            }
            ATRatioShowMenu(bundleID, ATRatioTopController(activePopup));
        };

        NSLog(@"[AppToolsRatio] Replacing app_row2[0] '%@' with '%@' at creation",
              title, kATRatioTitle);
        %orig(kATRatioTitle, @"", ATRatioCreateIcon() ?: image, ratioHandler);
        objc_setAssociatedObject(self, &kATRatioDidReplaceAssociation,
                                 @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    %orig(title, detail, image, handler);
}

/*
 * Second chance: replace the registered model immediately before AppTools
 * rebuilds the visible grid. This covers bars populated before rowStorageKey
 * was attached or returned from AppTools' cache.
 */
- (void)rebuildArrangedSubviews {
    if (![objc_getAssociatedObject(self, &kATRatioApplyingAssociation) boolValue]) {
        ATPopupViewController *popup = ATRatioPopupForBar((ATActionsBarView *)self);
        if (!popup) popup = gATRatioVisiblePopup ?: gATRatioBuildingPopup;
        ATRatioReplaceRegisteredTile((ATActionsBarView *)self, popup, NO);
    }
    %orig;
}

/* Final fallback after the row has finished registering all of its items. */
- (void)finishAddingItems {
    %orig;
    NSString *rowKey = self.rowStorageKey;
    if (rowKey.length == 0) rowKey = objc_getAssociatedObject(self, &kATRatioRowKeyAssociation);
    if ([rowKey isEqualToString:kATRatioRowKey]) {
        ATPopupViewController *popup = ATRatioPopupForBar((ATActionsBarView *)self);
        if (!popup) popup = gATRatioVisiblePopup ?: gATRatioBuildingPopup;
        BOOL changed = ATRatioReplaceRegisteredTile((ATActionsBarView *)self, popup, YES);
        NSLog(@"[AppToolsRatio] app_row2 finished; post-build replacement=%@, items=%lu",
              changed ? @"YES" : @"NO", (unsigned long)self.itemTitles.count);
    }
}

%end
%end

#pragma mark - Hook installation

static BOOL gATRatioCreateTimeHooksInstalled = NO;
static NSUInteger gATRatioCreateTimeAttempts = 0;

static void ATRatioTryInstallCreateTimeHooks(void) {
    if (gATRatioCreateTimeHooksInstalled) return;

    Class popupClass = objc_getClass("ATPopupViewController");
    Class barClass = objc_getClass("ATActionsBarView");
    BOOL popupReady = popupClass &&
        class_getInstanceMethod(popupClass, @selector(liveActionsBarWithRowStorageKey:)) &&
        class_getInstanceMethod(popupClass, @selector(viewDidLayoutSubviews));
    BOOL barReady = barClass &&
        class_getInstanceMethod(barClass, @selector(addItemWithTitle:detail:image:handler:)) &&
        class_getInstanceMethod(barClass, @selector(rebuildArrangedSubviews)) &&
        class_getInstanceMethod(barClass, @selector(finishAddingItems));

    if (popupReady && barReady) {
        %init(ATRatioCreateTimeUI);
        gATRatioCreateTimeHooksInstalled = YES;
        NSLog(@"[AppToolsRatio] Installed AppTools panel hooks: %@ / %@",
              NSStringFromClass(popupClass), NSStringFromClass(barClass));
        return;
    }

    if (gATRatioCreateTimeAttempts++ < 240) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ATRatioTryInstallCreateTimeHooks();
        });
    } else {
        NSLog(@"[AppToolsRatio] Hook targets not ready. ATPopup=%p ATActionsBar=%p",
              popupClass, barClass);
    }
}

__attribute__((constructor))
static void ATRatioCreateTimeInit(void) {
    @autoreleasepool {
        /* The bundle filter already limits this dylib to AppTools host processes. */
        NSLog(@"[AppToolsRatio] UI replacement dylib constructor ran; bundle=%@",
              NSBundle.mainBundle.bundleIdentifier ?: @"<nil>");
        dispatch_async(dispatch_get_main_queue(), ^{
            ATRatioTryInstallCreateTimeHooks();
        });
    }
}
