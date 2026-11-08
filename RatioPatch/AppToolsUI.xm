#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/* AppTools 2.9.0 private interfaces confirmed from AppTool.dylib metadata. */
@interface ATActionsBarView : UIView
@property(nonatomic, copy) NSString *rowStorageKey;
@property(nonatomic, copy) NSArray *itemTitles;
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

#pragma mark - Replace the tile while AppTools registers it

%group ATRatioCreateTimeUI

%hook ATPopupViewController

- (void)viewDidLoad {
    %orig;
    gATRatioVisiblePopup = (ATPopupViewController *)self;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gATRatioVisiblePopup = (ATPopupViewController *)self;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (gATRatioVisiblePopup == (ATPopupViewController *)self) {
        gATRatioVisiblePopup = nil;
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
    NSLog(@"[AppToolsRatio] bar row key set: %@", rowStorageKey);
}

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

    NSLog(@"[AppToolsRatio] registering app_row2[%lu]: %@",
          (unsigned long)itemIndex, title);

    if (itemIndex != 0 ||
        [objc_getAssociatedObject(self, &kATRatioDidReplaceAssociation) boolValue]) {
        %orig(title, detail, image, handler);
        return;
    }

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

        NSString *targetBundleID = activePopup.bundleID;
        if (![targetBundleID isKindOfClass:[NSString class]] || targetBundleID.length == 0) {
            targetBundleID = bundleIDAtCreation;
        }
        if (targetBundleID.length == 0 || !activePopup) {
            NSLog(@"[AppToolsRatio] Ratio tile tapped but selected app Bundle ID is unavailable");
            return;
        }

        UIViewController *presenter = ATRatioTopController(activePopup);
        ATRatioShowMenu(targetBundleID, presenter);
    };

    UIImage *ratioIcon = ATRatioCreateIcon();
    objc_setAssociatedObject(self, &kATRatioDidReplaceAssociation,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSLog(@"[AppToolsRatio] Replacing app_row2[0] '%@' with '%@' (bundle=%@)",
          title, kATRatioTitle, bundleIDAtCreation ?: @"<not-set-yet>");

    /* Replace the item before AppTools creates its button/view and stores the handler. */
    %orig(kATRatioTitle, @"", ratioIcon ?: image, ratioHandler);
}

- (void)finishAddingItems {
    %orig;
    NSString *rowKey = self.rowStorageKey;
    if (rowKey.length == 0) rowKey = objc_getAssociatedObject(self, &kATRatioRowKeyAssociation);
    if ([rowKey isEqualToString:kATRatioRowKey]) {
        BOOL didReplace = [objc_getAssociatedObject(self, &kATRatioDidReplaceAssociation) boolValue];
        NSLog(@"[AppToolsRatio] app_row2 finished. replacement=%@ titles=%lu",
              didReplace ? @"YES" : @"NO", (unsigned long)self.itemTitles.count);
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
    if (popupClass && barClass) {
        %init(ATRatioCreateTimeUI);
        gATRatioCreateTimeHooksInstalled = YES;
        NSLog(@"[AppToolsRatio] Creation-time hooks installed: %@ / %@",
              NSStringFromClass(popupClass), NSStringFromClass(barClass));
        return;
    }

    if (gATRatioCreateTimeAttempts++ < 240) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ATRatioTryInstallCreateTimeHooks();
        });
    } else {
        NSLog(@"[AppToolsRatio] Cannot install hooks. ATPopup=%p ATActionsBar=%p",
              popupClass, barClass);
    }
}

__attribute__((constructor))
static void ATRatioCreateTimeInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

        NSLog(@"[AppToolsRatio] Create-time UI patch loaded in SpringBoard");
        dispatch_async(dispatch_get_main_queue(), ^{
            ATRatioTryInstallCreateTimeHooks();
        });
    }
}
