#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

/* Private AppTools 2.9.0 interfaces verified from the supplied AppTool.dylib. */
@interface ATActionsBarView : UIView
@property(nonatomic, copy) NSString *rowStorageKey;
@property(nonatomic, copy) NSArray *itemTitles;
@property(nonatomic, copy) NSArray *registeredTitles;
- (void)addItemWithTitle:(NSString *)title
                  detail:(NSString *)detail
                   image:(UIImage *)image
                 handler:(void (^)(void))handler;
@end

@interface ATPopupViewController : UIViewController
@property(nonatomic, copy) NSString *bundleID;
@end

static NSString * const kATRatioRowKey = @"ATBarLayout_app_row2";
static NSString * const kATRatioTitle = @"Tỉ lệ màn hình";
static ATPopupViewController *gATCurrentPopup = nil; // cleared when the popup disappears
static BOOL gATRatioHooksInstalled = NO;
static NSUInteger gATRatioInstallAttempts = 0;

#pragma mark - Ratio icon

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

#pragma mark - Popup lookup and ratio menu

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

    return gATCurrentPopup;
}

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
                                    CGRectGetMidY(presenter.view.bounds), 1.0, 1.0);
    popover.permittedArrowDirections = 0;
}

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
                                 message:@"Chiều rộng và chiều cao phải lớn hơn 0."
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
        ATRatioShowCustomInput(bundleID, presenter);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    ATRatioConfigurePopover(alert, presenter);
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Replace the existing first tile in app_row2

%group ATRatioAppToolsUI

%hook ATPopupViewController

- (void)viewDidLoad {
    %orig;
    gATCurrentPopup = (ATPopupViewController *)self;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gATCurrentPopup = (ATPopupViewController *)self;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (gATCurrentPopup == (ATPopupViewController *)self) {
        gATCurrentPopup = nil;
    }
}

%end

%hook ATActionsBarView

- (void)addItemWithTitle:(NSString *)title
                  detail:(NSString *)detail
                   image:(UIImage *)image
                 handler:(void (^)(void))handler {

    NSString *rowKey = self.rowStorageKey;
    NSArray *existingTitles = self.itemTitles;
    NSUInteger itemIndex = existingTitles.count;

    /*
     * In the supplied AppTools 2.9.0 panel, app_row2 starts with
     * "Thông báo tin nhắn". Replace that existing tile rather than adding
     * a new button at the edge or overlapping another tile.
     */
    if ([rowKey isEqualToString:kATRatioRowKey] && itemIndex == 0) {
        ATPopupViewController *popup = ATRatioPopupForBar(self);
        if (!popup) popup = gATCurrentPopup;

        NSString *bundleID = [popup.bundleID copy];
        __weak ATPopupViewController *weakPopup = popup;
        __weak ATActionsBarView *weakBar = self;
        UIImage *ratioIcon = ATRatioCreateIcon();

        void (^ratioHandler)(void) = ^{
            ATPopupViewController *activePopup = weakPopup;
            if (!activePopup) {
                activePopup = ATRatioPopupForBar(weakBar);
            }
            if (!activePopup) activePopup = gATCurrentPopup;

            NSString *targetBundleID = bundleID.length ? bundleID : activePopup.bundleID;
            if (targetBundleID.length == 0 || !activePopup) {
                NSLog(@"[AppToolsRatio] Could not resolve the selected app Bundle ID.");
                return;
            }

            ATRatioShowMenu(targetBundleID, ATRatioTopController(activePopup));
        };

        NSLog(@"[AppToolsRatio] Replacing app_row2 item '%@' with Screen Ratio.", title);
        %orig(kATRatioTitle, nil, ratioIcon ?: image, ratioHandler);
        return;
    }

    %orig(title, detail, image, handler);
}

%end
%end

#pragma mark - Delayed Logos installation (AppTool.dylib may load first/after us)

static void ATRatioAttemptInstallHooks(void) {
    if (gATRatioHooksInstalled) return;

    if (objc_getClass("ATPopupViewController") && objc_getClass("ATActionsBarView")) {
        %init(ATRatioAppToolsUI);
        gATRatioHooksInstalled = YES;
        NSLog(@"[AppToolsRatio] App-specific ratio tile hook installed.");
        return;
    }

    if (gATRatioInstallAttempts++ < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ATRatioAttemptInstallHooks();
        });
    } else {
        NSLog(@"[AppToolsRatio] AppTools classes were not found in SpringBoard; tile hook not installed.");
    }
}

__attribute__((constructor))
static void ATRatioAppToolsUIInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            ATRatioAttemptInstallHooks();
        });
    }
}
