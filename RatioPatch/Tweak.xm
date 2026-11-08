#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "RatioManager.h"

#pragma mark -
#pragma mark AppTools private classes

@interface ATActionButton : NSObject

@property(nonatomic, copy) NSString *title;

@end


@interface ATActionSheet : UIViewController

@end


#pragma mark -
#pragma mark Runtime helpers

static NSString *ATRCurrentBundleIdentifier(void) {

    NSString *bundleID =
        [[NSBundle mainBundle] bundleIdentifier];

    if (bundleID)
        return bundleID;

    return @"";
}


static void ATRShowRatioMenu(NSString *bundleID) {

    if (!bundleID || bundleID.length == 0)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{

        UIAlertController *alert =
            [UIAlertController
                alertControllerWithTitle:@"Tỉ lệ màn hình"
                                 message:nil
                          preferredStyle:UIAlertControllerStyleActionSheet];

        NSArray *ratios = @[
            @"Tự động",
            @"16:9",
            @"4:3",
            @"3:2",
            @"18:9",
            @"19.5:9",
            @"21:9",
            @"Tùy chỉnh thủ công"
        ];

        for (NSString *ratio in ratios) {

            UIAlertAction *action =
                [UIAlertAction
                    actionWithTitle:ratio
                             style:UIAlertActionStyleDefault
                           handler:^(UIAlertAction *a) {

                if ([ratio isEqualToString:@"Tự động"]) {

                    NSMutableDictionary *all =
                        [[[NSUserDefaults standardUserDefaults]
                            dictionaryForKey:@"AppToolsScreenRatios"]
                            mutableCopy];

                    if (!all)
                        all = [NSMutableDictionary dictionary];

                    [all removeObjectForKey:bundleID];

                    [[NSUserDefaults standardUserDefaults]
                        setObject:all
                           forKey:@"AppToolsScreenRatios"];

                    [[NSUserDefaults standardUserDefaults]
                        synchronize];

                    return;
                }

                if ([ratio isEqualToString:@"Tùy chỉnh thủ công"]) {

                    UIAlertController *custom =
                        [UIAlertController
                            alertControllerWithTitle:@"Tỉ lệ màn hình"
                                             message:@"Nhập chiều rộng và chiều cao"
                                      preferredStyle:UIAlertControllerStyleAlert];

                    [custom addTextFieldWithConfigurationHandler:
                        ^(UITextField *field) {
                            field.placeholder = @"Chiều rộng";
                            field.keyboardType =
                                UIKeyboardTypeDecimalPad;
                        }];

                    [custom addTextFieldWithConfigurationHandler:
                        ^(UITextField *field) {
                            field.placeholder = @"Chiều cao";
                            field.keyboardType =
                                UIKeyboardTypeDecimalPad;
                        }];

                    [custom addAction:
                        [UIAlertAction
                            actionWithTitle:@"Hủy"
                                     style:UIAlertActionStyleCancel
                                   handler:nil]];

                    [custom addAction:
                        [UIAlertAction
                            actionWithTitle:@"Lưu"
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *save) {

                        CGFloat width =
                            [custom.textFields[0].text doubleValue];

                        CGFloat height =
                            [custom.textFields[1].text doubleValue];

                        if (width <= 0 || height <= 0)
                            return;

                        [[ATRatioManager sharedManager]
                            setRatioForBundleID:bundleID
                                          width:width
                                         height:height];

                        [[ATRatioManager sharedManager]
                            applyRatioToApplication:UIApplication.sharedApplication];
                    }]];

                    UIViewController *vc =
                        UIApplication.sharedApplication.keyWindow.rootViewController;

                    while (vc.presentedViewController)
                        vc = vc.presentedViewController;

                    [vc presentViewController:custom
                                     animated:YES
                                   completion:nil];

                    return;
                }

                [[ATRatioManager sharedManager]
                    setPresetRatioForBundleID:bundleID
                                         ratio:ratio];

                [[ATRatioManager sharedManager]
                    applyRatioToApplication:UIApplication.sharedApplication];
            }];

            [alert addAction:action];
        }

        [alert addAction:
            [UIAlertAction
                actionWithTitle:@"Hủy"
                         style:UIAlertActionStyleCancel
                       handler:nil]];

        UIViewController *vc =
            UIApplication.sharedApplication.keyWindow.rootViewController;

        while (vc.presentedViewController)
            vc = vc.presentedViewController;

        [vc presentViewController:alert
                         animated:YES
                       completion:nil];
    });
}


#pragma mark -
#pragma mark AppTools Action Button

%hook ATActionButton

- (void)setTitle:(NSString *)title {

    %orig;

    /*
     * Không thay đổi các nút gốc của AppTools.
     *
     * Việc thêm action sẽ được xử lý ở action sheet,
     * tránh phá layout / logic button có sẵn.
     */
}

%end


#pragma mark -
#pragma mark Action Sheet

%hook ATActionSheet

- (void)viewDidAppear:(BOOL)animated {

    %orig;

    /*
     * Chỉ thêm action một lần cho mỗi instance.
     */

    static char kRatioAdded;

    if (objc_getAssociatedObject(self, &kRatioAdded))
        return;

    objc_setAssociatedObject(
        self,
        &kRatioAdded,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    /*
     * Không biết chắc selector nội bộ của 2.9.0
     * do binary đã strip symbol.
     *
     * Ta dùng một nút nổi nhỏ ở vùng action bar
     * làm fallback để tính năng vẫn truy cập được.
     */

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame =
        CGRectMake(0, 0, 44, 44);

    [button setTitle:@"↕"
            forState:UIControlStateNormal];

    button.accessibilityLabel =
        @"Tỉ lệ màn hình";

    [button addTarget:self
               action:@selector(atr_ratioPressed:)
     forControlEvents:UIControlEventTouchUpInside];

    button.tag = 2900195;

    [self.view addSubview:button];

    button.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [button.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor
                           constant:-12],

        [button.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
                           constant:8],

        [button.widthAnchor
            constraintEqualToConstant:44],

        [button.heightAnchor
            constraintEqualToConstant:44]
    ]];
}


%new

- (void)atr_ratioPressed:(id)sender {

    NSString *bundleID =
        ATRCurrentBundleIdentifier();

    if (bundleID.length == 0) {

        bundleID =
            [[NSUserDefaults standardUserDefaults]
                stringForKey:@"AppToolsCurrentBundleID"];
    }

    if (bundleID.length == 0)
        return;

    ATRShowRatioMenu(bundleID);
}

%end


#pragma mark -
#pragma mark Application

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {

    %orig;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.15 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{

            [[ATRatioManager sharedManager]
                applyRatioToApplication:application];
        }
    );
}

%end


#pragma mark -
#pragma mark Window resize

%hook UIWindow

- (void)layoutSubviews {

    %orig;

    NSString *bundleID =
        [[NSBundle mainBundle] bundleIdentifier];

    if (!bundleID)
        return;

    NSDictionary *ratio =
        [[ATRatioManager sharedManager]
            ratioForBundleID:bundleID];

    if (!ratio)
        return;

    /*
     * Không gọi lại liên tục trong layout.
     * Chỉ áp dụng nếu tỷ lệ hiện tại khác tỷ lệ yêu cầu.
     */

    CGFloat width =
        [ratio[@"width"] doubleValue];

    CGFloat height =
        [ratio[@"height"] doubleValue];

    if (width <= 0 || height <= 0)
        return;

    UIScreen *screen =
        self.screen ?: UIScreen.mainScreen;

    CGRect bounds =
        screen.bounds;

    CGFloat sw =
        CGRectGetWidth(bounds);

    CGFloat sh =
        CGRectGetHeight(bounds);

    CGFloat targetRatio =
        width / height;

    CGFloat currentRatio =
        CGRectGetWidth(self.bounds) /
        MAX(CGRectGetHeight(self.bounds), 1);

    if (fabs(currentRatio - targetRatio) < 0.01)
        return;

    CGFloat newWidth = sw;
    CGFloat newHeight = sw / targetRatio;

    if (newHeight > sh) {

        newHeight = sh;
        newWidth = sh * targetRatio;
    }

    CGRect frame = self.frame;

    frame.size.width = newWidth;
    frame.size.height = newHeight;

    frame.origin.x =
        (sw - newWidth) / 2.0;

    frame.origin.y =
        (sh - newHeight) / 2.0;

    self.frame = frame;
}

%end
