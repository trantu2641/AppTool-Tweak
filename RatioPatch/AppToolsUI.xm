#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "RatioStore.h"

#pragma mark - Helpers

static NSString *ATRGetSelectedBundleID(void) {

    NSArray<NSString *> *candidateSelectors = @[
        @"bundleIdentifier",
        @"selectedBundleIdentifier",
        @"currentBundleIdentifier",
        @"targetBundleIdentifier",
        @"bundleID",
        @"selectedBundleID",
        @"currentBundleID"
    ];

    for (NSString *selectorName in candidateSelectors) {

        SEL selector =
            NSSelectorFromString(selectorName);

        for (id object in @[
            UIApplication.sharedApplication.keyWindow.rootViewController ?: [NSNull null]
        ]) {

            if (object == [NSNull null])
                continue;

            if ([object respondsToSelector:selector]) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

                id value =
                    [object performSelector:selector];

#pragma clang diagnostic pop

                if ([value isKindOfClass:[NSString class]] &&
                    [value length] > 0) {

                    return value;
                }
            }
        }
    }

    return nil;
}


static UIViewController *ATTopViewController(void) {

    UIWindow *window =
        UIApplication.sharedApplication.keyWindow;

    if (!window)
        return nil;

    UIViewController *vc =
        window.rootViewController;

    while (vc.presentedViewController)
        vc = vc.presentedViewController;

    return vc;
}


static void ATRShowCustomRatio(NSString *bundleID) {

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"Tùy chỉnh tỉ lệ màn hình"
                             message:@"Nhập chiều rộng và chiều cao"
                      preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {

        field.placeholder = @"Chiều rộng";
        field.keyboardType =
            UIKeyboardTypeDecimalPad;
    }];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {

        field.placeholder = @"Chiều cao";
        field.keyboardType =
            UIKeyboardTypeDecimalPad;
    }];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"Hủy"
                     style:UIAlertActionStyleCancel
                   handler:nil]];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"Áp dụng"
                     style:UIAlertActionStyleDefault
                   handler:^(UIAlertAction *action) {

        CGFloat width =
            [alert.textFields[0].text doubleValue];

        CGFloat height =
            [alert.textFields[1].text doubleValue];

        if (width <= 0.0 || height <= 0.0) {

            UIAlertController *error =
                [UIAlertController
                    alertControllerWithTitle:@"Lỗi"
                                     message:@"Chiều rộng và chiều cao phải lớn hơn 0."
                              preferredStyle:UIAlertControllerStyleAlert];

            [error addAction:
                [UIAlertAction
                    actionWithTitle:@"OK"
                             style:UIAlertActionStyleDefault
                           handler:nil]];

            [ATTopViewController()
                presentViewController:error
                             animated:YES
                           completion:nil];

            return;
        }

        ATRatio ratio =
            ATRatioMake(width, height);

        [[ATRatioStore sharedStore]
            setRatio:ratio
            forBundleID:bundleID];

    }]];

    [ATTopViewController()
        presentViewController:alert
                     animated:YES
                   completion:nil];
}


static void ATRShowRatioMenu(NSString *bundleID) {

    if (!bundleID.length)
        return;

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:@"Tỉ lệ màn hình"
                             message:nil
                      preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary *> *items = @[
        @{
            @"title": @"Tự động",
            @"width": @0,
            @"height": @0
        },

        @{
            @"title": @"16:9",
            @"width": @16,
            @"height": @9
        },

        @{
            @"title": @"4:3",
            @"width": @4,
            @"height": @3
        },

        @{
            @"title": @"3:2",
            @"width": @3,
            @"height": @2
        },

        @{
            @"title": @"18:9",
            @"width": @18,
            @"height": @9
        },

        @{
            @"title": @"19,5:9",
            @"width": @19.5,
            @"height": @9
        },

        @{
            @"title": @"21:9",
            @"width": @21,
            @"height": @9
        }
    ];

    for (NSDictionary *item in items) {

        NSString *title =
            item[@"title"];

        UIAlertAction *action =
            [UIAlertAction
                actionWithTitle:title
                         style:UIAlertActionStyleDefault
                       handler:^(UIAlertAction *action) {

            CGFloat width =
                [item[@"width"] doubleValue];

            CGFloat height =
                [item[@"height"] doubleValue];

            if (width == 0.0 || height == 0.0) {

                [[ATRatioStore sharedStore]
                    removeRatioForBundleID:bundleID];

                return;
            }

            ATRatio ratio =
                ATRatioMake(width, height);

            [[ATRatioStore sharedStore]
                setRatio:ratio
                forBundleID:bundleID];
        }];

        [alert addAction:action];
    }

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"Tùy chỉnh thủ công"
                     style:UIAlertActionStyleDefault
                   handler:^(UIAlertAction *action) {

        ATRShowCustomRatio(bundleID);
    }]];

    [alert addAction:
        [UIAlertAction
            actionWithTitle:@"Hủy"
                     style:UIAlertActionStyleCancel
                   handler:nil]];

    [ATTopViewController()
        presentViewController:alert
                     animated:YES
                   completion:nil];
}

#pragma mark - Action item discovery


static void ATRInstallRatioButton(UIViewController *controller) {

    if (!controller)
        return;

    UIView *root =
        controller.view;

    if (!root)
        return;

    UIView *existing =
        [root viewWithTag:0xA709];

    if (existing)
        return;

    /*
     * Tìm ATActionsBarView.
     */

    UIView *actionBar = nil;

    NSMutableArray<UIView *> *queue =
        [NSMutableArray arrayWithObject:root];

    while (queue.count > 0) {

        UIView *view =
            queue.firstObject;

        [queue removeObjectAtIndex:0];

        NSString *name =
            NSStringFromClass([view class]);

        if ([name isEqualToString:@"ATActionsBarView"]) {

            actionBar = view;
            break;
        }

        for (UIView *subview in view.subviews) {

            [queue addObject:subview];
        }
    }

    if (!actionBar)
        return;

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.tag = 0xA709;

    [button setTitle:@"Tỉ lệ màn hình"
            forState:UIControlStateNormal];

    button.accessibilityLabel =
        @"Tỉ lệ màn hình";

    button.titleLabel.font =
        [UIFont systemFontOfSize:14.0
                           weight:UIFontWeightMedium];

    [button addTarget:controller
               action:@selector(atr_ratioButtonPressed:)
     forControlEvents:UIControlEventTouchUpInside];

    /*
     * Dùng kích thước tự co giãn.
     */

    button.translatesAutoresizingMaskIntoConstraints = NO;

    [actionBar addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.heightAnchor
            constraintEqualToAnchor:actionBar.heightAnchor],

        [button.widthAnchor
            constraintGreaterThanOrEqualToConstant:110.0],

        [button.trailingAnchor
            constraintEqualToAnchor:actionBar.trailingAnchor
                           constant:-8.0],

        [button.centerYAnchor
            constraintEqualToAnchor:actionBar.centerYAnchor]
    ]];
}

#pragma mark - UIViewController

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {

    %orig;

    NSString *className =
        NSStringFromClass([self class]);

    /*
     * Chỉ hoạt động với các controller thuộc
     * giao diện AppTools/action sheet.
     */

    if ([className containsString:@"ATAction"] ||
        [className containsString:@"ATPopup"] ||
        [className containsString:@"AppTool"]) {

        dispatch_async(dispatch_get_main_queue(), ^{

            ATRInstallRatioButton(self);
        });
    }
}

%new

- (void)atr_ratioButtonPressed:(id)sender {

    NSString *bundleID =
        ATRGetSelectedBundleID();

    if (!bundleID.length) {

        UIAlertController *error =
            [UIAlertController
                alertControllerWithTitle:@"Không xác định được ứng dụng"
                                 message:@"Không lấy được Bundle ID của ứng dụng đang chọn."
                          preferredStyle:UIAlertControllerStyleAlert];

        [error addAction:
            [UIAlertAction
                actionWithTitle:@"OK"
                         style:UIAlertActionStyleDefault
                       handler:nil]];

        [self presentViewController:error
                           animated:YES
                         completion:nil];

        return;
    }

    ATRShowRatioMenu(bundleID);
}

%end
