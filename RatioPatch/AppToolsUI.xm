#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#import "RatioStore.h"

/* AppTools 2.9.0 declares this private controller in AppTool.dylib. */
@interface ATPopupViewController : UIViewController
@end

static const NSInteger kATRatioButtonTag = 0xA709;

#pragma mark - Bundle ID discovery

static NSArray<NSString *> *ATRatioBundleIDGetters(void) {
    return @[
        @"bundleID",
        @"applicationBundleID",
        @"bundleIdentifier",
        @"selectedBundleIdentifier",
        @"currentBundleIdentifier",
        @"targetBundleIdentifier",
        @"selectedBundleID",
        @"currentBundleID"
    ];
}

static NSString *ATRatioStringFromGetter(id object, NSString *name) {
    if (!object || !name.length) return nil;

    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;

    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@') return nil;

    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return (NSString *)value;
    }
    return nil;
}

static NSString *ATRatioBundleIDFromObject(id object) {
    for (NSString *getter in ATRatioBundleIDGetters()) {
        NSString *value = ATRatioStringFromGetter(object, getter);
        if (value.length > 0) return value;
    }
    return nil;
}

/*
 * AppTools keeps the selected application's model/controller under its popup.
 * Walk only the popup's controller/view responder tree; do not query arbitrary
 * selectors or use KVC, which can crash on private objects.
 */
static NSString *ATRatioSelectedBundleID(ATPopupViewController *popup) {
    if (!popup) return nil;

    NSMutableArray *queue = [NSMutableArray arrayWithObject:popup];
    NSHashTable *visited = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];
    NSUInteger cursor = 0;

    while (cursor < queue.count && cursor < 512) {
        id object = queue[cursor++];
        if (!object || object == [NSNull null] || [visited containsObject:object]) continue;
        [visited addObject:object];

        NSString *bundleID = ATRatioBundleIDFromObject(object);
        if (bundleID.length > 0) return bundleID;

        if ([object isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = object;
            if (vc.parentViewController) [queue addObject:vc.parentViewController];
            if (vc.presentingViewController) [queue addObject:vc.presentingViewController];
            if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
            if (vc.navigationController) [queue addObject:vc.navigationController];
            if (vc.tabBarController) [queue addObject:vc.tabBarController];
            for (UIViewController *child in vc.childViewControllers) [queue addObject:child];
            if (vc.isViewLoaded) [queue addObject:vc.view];
        } else if ([object isKindOfClass:[UIView class]]) {
            UIView *view = object;
            for (UIView *subview in view.subviews) [queue addObject:subview];
            UIResponder *next = view.nextResponder;
            if (next && next != object) [queue addObject:next];
        }
    }

    return nil;
}

#pragma mark - Dialog helpers

static UIViewController *ATRatioTopController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current.presentedViewController) current = current.presentedViewController;
    return current;
}

static void ATRatioPreparePopover(UIAlertController *alert, UIViewController *presenter) {
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (!popover || !presenter.isViewLoaded) return;
    popover.sourceView = presenter.view;
    popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds),
                                    CGRectGetMidY(presenter.view.bounds), 1.0, 1.0);
    popover.permittedArrowDirections = 0;
}

static void ATRatioShowInvalidInput(UIViewController *presenter) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Giá trị không hợp lệ"
                         message:@"Chiều rộng và chiều cao phải là số lớn hơn 0."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void ATRatioShowCustomDialog(NSString *bundleID, UIViewController *presenter) {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tùy chỉnh tỉ lệ màn hình"
                         message:@"Nhập chiều rộng và chiều cao"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Chiều rộng, ví dụ 9 hoặc 16";
        field.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Chiều cao, ví dụ 19.5 hoặc 9";
        field.keyboardType = UIKeyboardTypeDecimalPad;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *widthText = [alert.textFields[0].text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        NSString *heightText = [alert.textFields[1].text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        CGFloat width = widthText.doubleValue;
        CGFloat height = heightText.doubleValue;

        if (!isfinite(width) || !isfinite(height) || width <= 0.0 || height <= 0.0) {
            ATRatioShowInvalidInput(presenter);
            return;
        }

        [[ATRatioStore sharedStore] setRatio:ATRatioMake(width, height) forBundleID:bundleID];
    }]];

    [presenter presentViewController:alert animated:YES completion:nil];
}

static void ATRatioShowMenu(NSString *bundleID, UIViewController *presenter) {
    if (bundleID.length == 0 || !presenter) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tỉ lệ màn hình"
                         message:[NSString stringWithFormat:@"Ứng dụng: %@", bundleID]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Tự động" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
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
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[ATRatioStore sharedStore] setRatio:ATRatioMake(width, height) forBundleID:bundleID];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Tùy chỉnh thủ công" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        ATRatioShowCustomDialog(bundleID, presenter);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

    ATRatioPreparePopover(alert, presenter);
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AppTools action bar

static UIView *ATRatioFindActionBar(UIView *rootView) {
    if (!rootView) return nil;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:rootView];
    NSUInteger cursor = 0;
    while (cursor < queue.count && cursor < 2048) {
        UIView *view = queue[cursor++];
        if ([NSStringFromClass(view.class) isEqualToString:@"ATActionsBarView"]) return view;
        for (UIView *subview in view.subviews) [queue addObject:subview];
    }
    return nil;
}

static void ATRatioInstallButton(ATPopupViewController *controller) {
    if (!controller.isViewLoaded || !controller.view.window) return;

    UIView *actionBar = ATRatioFindActionBar(controller.view);
    if (!actionBar || [actionBar viewWithTag:kATRatioButtonTag]) return;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kATRatioButtonTag;
    [button setTitle:@"Tỉ lệ màn hình" forState:UIControlStateNormal];
    button.accessibilityLabel = @"Tỉ lệ màn hình";
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 8.0, 0.0, 8.0);
    [button addTarget:controller action:@selector(atr_ratioButtonPressed:) forControlEvents:UIControlEventTouchUpInside];

    button.translatesAutoresizingMaskIntoConstraints = NO;
    [actionBar addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.trailingAnchor constraintEqualToAnchor:actionBar.trailingAnchor constant:-6.0],
        [button.centerYAnchor constraintEqualToAnchor:actionBar.centerYAnchor],
        [button.heightAnchor constraintLessThanOrEqualToAnchor:actionBar.heightAnchor constant:-4.0],
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:100.0]
    ]];
}

#pragma mark - SpringBoard-only AppTools UI hook

%group ATRatioAppToolsUI
%hook ATPopupViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        ATRatioInstallButton((ATPopupViewController *)self);
    });
}

%new
- (void)atr_ratioButtonPressed:(id)sender {
    NSString *bundleID = ATRatioSelectedBundleID((ATPopupViewController *)self);
    if (bundleID.length == 0) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Không xác định được ứng dụng"
                             message:@"Không đọc được Bundle ID từ bảng điều khiển AppTools."
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    ATRatioShowMenu(bundleID, ATRatioTopController(self));
}

%end
%end

__attribute__((constructor))
static void ATRatioAppToolsUIInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if ([bundleID isEqualToString:@"com.apple.springboard"] && objc_getClass("ATPopupViewController")) {
            %init(ATRatioAppToolsUI);
        }
    }
}
