#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/* Private AppTools 2.9.0 interfaces confirmed from AppTool.dylib metadata. */
@interface ATActionsBarView : UIView
@property(nonatomic, copy) NSString *rowStorageKey;
@property(nonatomic, copy) NSArray *registeredTitles;
@property(nonatomic, copy) NSArray *itemTitles;
- (BOOL)currentlyDisplaysItemWithTitle:(NSString *)title;
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

static NSString * const kATRatioFeatureTitle = @"Tỉ lệ màn hình";
static NSString * const kATRatioFeatureRow = @"ATBarLayout_app_row0";
static char kATRatioFeatureInstalledKey;

#pragma mark - Icon

/* Draw the icon in the same cyan line-art style as AppTools' Theme_New icons.
 * No external asset path or Root.plist entry is required. */
static UIImage *ATRatioCreateFeatureIcon(void) {
    const CGSize size = CGSizeMake(64.0, 64.0);
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

    /* Display frame */
    UIBezierPath *frame = [UIBezierPath bezierPathWithRoundedRect:
        CGRectMake(10.0, 7.0, 44.0, 50.0) cornerRadius:9.0];
    frame.lineWidth = 3.2;
    [frame stroke];

    /* Horizontal and vertical guides suggest adjustable screen proportions. */
    UIBezierPath *guides = [UIBezierPath bezierPath];
    guides.lineWidth = 3.0;
    [guides moveToPoint:CGPointMake(18.0, 23.0)];
    [guides addLineToPoint:CGPointMake(46.0, 23.0)];
    [guides moveToPoint:CGPointMake(18.0, 41.0)];
    [guides addLineToPoint:CGPointMake(46.0, 41.0)];
    [guides moveToPoint:CGPointMake(32.0, 14.0)];
    [guides addLineToPoint:CGPointMake(32.0, 50.0)];
    [guides stroke];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

#pragma mark - Presentation helpers

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

static void ATRatioShowInvalidInput(UIViewController *presenter) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Giá trị không hợp lệ"
                         message:@"Chiều rộng và chiều cao phải là số lớn hơn 0."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void ATRatioShowCustomDialog(NSString *bundleID,
                                    UIViewController *presenter) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tùy chỉnh tỉ lệ màn hình"
                         message:@"Nhập chiều rộng và chiều cao"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Chiều rộng, ví dụ 16";
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
            ATRatioShowInvalidInput(presenter);
            return;
        }

        [[ATRatioStore sharedStore]
            setRatio:ATRatioMake(width, height)
            forBundleID:bundleID];
    }]];

    [presenter presentViewController:alert animated:YES completion:nil];
}

static void ATRatioShowMenu(NSString *bundleID,
                            UIViewController *presenter) {
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
        ATRatioShowCustomDialog(bundleID, presenter);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    ATRatioConfigurePopover(alert, presenter);
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Add the feature to the existing AppTools app-feature row

static BOOL ATRatioBarAlreadyHasFeature(ATActionsBarView *bar) {
    if (!bar) return NO;

    if ([bar currentlyDisplaysItemWithTitle:kATRatioFeatureTitle]) return YES;
    if ([bar.itemTitles containsObject:kATRatioFeatureTitle]) return YES;
    if ([bar.registeredTitles containsObject:kATRatioFeatureTitle]) return YES;

    return NO;
}

static BOOL ATRatioInstallFeature(ATPopupViewController *popup) {
    if (!popup || !popup.isViewLoaded) return NO;

    /*
     * Use AppTools' own API to insert a normal feature tile.
     * Do not add a free-floating UIButton to the first actions bar.
     * app_row0 is the app-specific feature group containing Customize DPI,
     * backup/restore documents and related per-app tools.
     */
    ATActionsBarView *bar =
        [popup liveActionsBarWithRowStorageKey:kATRatioFeatureRow];

    if (!bar) return NO;
    if (ATRatioBarAlreadyHasFeature(bar)) return YES;

    __weak ATPopupViewController *weakPopup = popup;
    UIImage *icon = ATRatioCreateFeatureIcon();
    if (!icon) return NO;

    [bar addItemWithTitle:kATRatioFeatureTitle
                   detail:nil
                    image:icon
                  handler:^{
        __strong ATPopupViewController *strongPopup = weakPopup;
        if (!strongPopup) return;

        NSString *bundleID = strongPopup.bundleID;
        if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
            UIAlertController *error = [UIAlertController
                alertControllerWithTitle:@"Không xác định được ứng dụng"
                                 message:@"AppTools không cung cấp Bundle ID của ứng dụng đang chọn."
                          preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"Đóng"
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil]];
            [strongPopup presentViewController:error animated:YES completion:nil];
            return;
        }

        ATRatioShowMenu(bundleID, ATRatioTopController(strongPopup));
    }];

    /* AppTools uses this finalizer after registering its built-in feature items. */
    [bar finishAddingItems];
    return YES;
}

#pragma mark - SpringBoard-only hook

%group ATRatioAppToolsUI
%hook ATPopupViewController

- (void)viewDidLayoutSubviews {
    %orig;

    if (objc_getAssociatedObject(self, &kATRatioFeatureInstalledKey)) return;

    __weak ATPopupViewController *weakPopup = (ATPopupViewController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong ATPopupViewController *popup = weakPopup;
        if (!popup) return;

        if (ATRatioInstallFeature(popup)) {
            objc_setAssociatedObject(popup,
                                     &kATRatioFeatureInstalledKey,
                                     @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

%end
%end

__attribute__((constructor))
static void ATRatioAppToolsUIInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if ([bundleID isEqualToString:@"com.apple.springboard"] &&
            objc_getClass("ATPopupViewController") &&
            objc_getClass("ATActionsBarView")) {
            %init(ATRatioAppToolsUI);
        }
    }
}
