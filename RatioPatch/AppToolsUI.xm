#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "RatioStore.h"

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

static NSString * const kATRatioTitle = @"Tỉ lệ màn hình";
static char kATRatioPopupAssociation;
static char kATRatioApplyingAssociation;
static __weak ATPopupViewController *gATRatioVisiblePopup = nil;

#pragma mark - Exact source-tile identification

static NSString *ATRatioFoldTitle(NSString *title) {
    if (![title isKindOfClass:[NSString class]]) return @"";
    NSString *folded = [title stringByFoldingWithOptions:(NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch)
                                                   locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    return [[folded stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

/*
 * Do not select by row index. AppTools can reuse action-bar instances for
 * different layouts, which caused the old index-0 hook to rename Ghim chạy nền.
 * Match only the notification tile's own title, independent of its position.
 */
static BOOL ATRatioIsNotificationTileTitle(NSString *title) {
    NSString *value = ATRatioFoldTitle(title);
    if (value.length == 0) return NO;

    return [value isEqualToString:@"thong bao tin nhan"] ||
           [value isEqualToString:@"message notification"] ||
           [value isEqualToString:@"notification message"] ||
           [value isEqualToString:@"disable message notification"] ||
           [value isEqualToString:@"disable notification"] ||
           [value isEqualToString:@"disablenotification"];
}

/*
 * Secondary identity check using AppTools' own DisableNotification artwork.
 * This lets the patch identify the same tile if the displayed title is
 * localized differently, while still leaving AllowBackground/Ghim chạy nền
 * completely untouched.
 */
static BOOL ATRatioImageMatchesNotificationIcon(UIImage *candidate) {
    if (!candidate) return NO;
    static NSArray<NSData *> *referencePNG = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSData *> *images = [NSMutableArray array];
        NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.flex2areo.apptools"];
        if (!bundle) {
            for (NSBundle *loaded in NSBundle.allBundles) {
                if ([loaded.bundleIdentifier isEqualToString:@"com.flex2areo.apptools"]) {
                    bundle = loaded;
                    break;
                }
            }
        }
        for (NSString *theme in @[@"Theme_New", @"Theme_Old"]) {
            NSString *path = [bundle pathForResource:@"DisableNotification"
                                              ofType:@"png"
                                         inDirectory:theme];
            UIImage *reference = path ? [UIImage imageWithContentsOfFile:path] : nil;
            NSData *data = reference ? UIImagePNGRepresentation(reference) : nil;
            if (data) [images addObject:data];
        }
        referencePNG = [images copy];
    });

    NSData *candidateData = UIImagePNGRepresentation(candidate);
    if (!candidateData) return NO;
    for (NSData *referenceData in referencePNG) {
        if ([candidateData isEqualToData:referenceData]) return YES;
    }
    return NO;
}

static BOOL ATRatioIsNotificationTile(NSString *title, UIImage *image) {
    return ATRatioIsNotificationTileTitle(title) || ATRatioImageMatchesNotificationIcon(image);
}

#pragma mark - AppTools popup lookup

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

    return gATRatioVisiblePopup;
}

static UIViewController *ATRatioTopController(UIViewController *controller) {
    UIViewController *current = controller;
    NSUInteger depth = 0;
    while (current.presentedViewController && depth++ < 20) {
        current = current.presentedViewController;
    }
    return current;
}

#pragma mark - Ratio menu

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

static void ATRatioConfigurePopover(UIAlertController *alert, UIViewController *presenter) {
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (!popover || !presenter.isViewLoaded) return;
    popover.sourceView = presenter.view;
    popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds),
                                    CGRectGetMidY(presenter.view.bounds), 1.0, 1.0);
    popover.permittedArrowDirections = 0;
}

static void ATRatioShowMenu(NSString *bundleID, UIViewController *presenter);

static void ATRatioShowCustomInput(NSString *bundleID, UIViewController *presenter) {
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

    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault
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
                [error addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
                [presenter presentViewController:error animated:YES completion:nil];
                return;
            }

            [[ATRatioStore sharedStore] setRatio:ATRatioMake(width, height) forBundleID:bundleID];
        }]];

    [presenter presentViewController:alert animated:YES completion:nil];
}

static void ATRatioShowMenu(NSString *bundleID, UIViewController *presenter) {
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0 || !presenter) {
        NSLog(@"[AppToolsRatio] Cannot show ratio menu: missing selected app Bundle ID or presenter");
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Tỉ lệ màn hình"
                         message:[NSString stringWithFormat:@"Ứng dụng: %@", bundleID]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Tự động" style:UIAlertActionStyleDefault
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
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) {
                [[ATRatioStore sharedStore] setRatio:ATRatioMake(width, height) forBundleID:bundleID];
            }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Tùy chỉnh thủ công" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            ATRatioShowCustomInput(bundleID, presenter);
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];

    ATRatioConfigurePopover(alert, presenter);
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Replacement action

static void (^ATRatioMakeTileHandler(ATActionsBarView *bar,
                                     ATPopupViewController *popup,
                                     NSString *bundleAtCreation))(void) {
    __weak ATActionsBarView *weakBar = bar;
    __weak ATPopupViewController *weakPopup = popup;
    NSString *capturedBundleID = [bundleAtCreation copy];

    return [^{
        dispatch_async(dispatch_get_main_queue(), ^{
            ATPopupViewController *activePopup = weakPopup;
            if (!activePopup) activePopup = ATRatioPopupForBar(weakBar);
            if (!activePopup) activePopup = gATRatioVisiblePopup;

            NSString *bundleID = [activePopup.bundleID copy];
            if (bundleID.length == 0) bundleID = capturedBundleID;
            if (bundleID.length == 0 || !activePopup) {
                NSLog(@"[AppToolsRatio] Ratio tile tapped, but selected app Bundle ID is unavailable");
                return;
            }

            UIViewController *presenter = ATRatioTopController(activePopup);
            if (!presenter.viewIfLoaded.window && gATRatioVisiblePopup) {
                presenter = ATRatioTopController(gATRatioVisiblePopup);
            }
            NSLog(@"[AppToolsRatio] Ratio tile action opened for %@", bundleID);
            ATRatioShowMenu(bundleID, presenter);
        });
    } copy];
}

static BOOL ATRatioReplaceRegisteredNotificationTile(ATActionsBarView *bar) {
    if (!bar || [objc_getAssociatedObject(bar, &kATRatioApplyingAssociation) boolValue]) return NO;

    NSArray *titles = bar.itemTitles;
    NSArray *oldImages = bar.itemImages;
    NSArray *oldHandlers = bar.itemHandlers;
    if (![titles isKindOfClass:[NSArray class]]) return NO;

    for (NSUInteger index = 0; index < titles.count; index++) {
        NSString *title = [titles[index] isKindOfClass:[NSString class]] ? titles[index] : nil;
        UIImage *candidateImage = index < oldImages.count && [oldImages[index] isKindOfClass:[UIImage class]]
            ? oldImages[index] : nil;
        if (!ATRatioIsNotificationTile(title, candidateImage)) continue;

        if (index >= oldImages.count || index >= oldHandlers.count) {
            NSLog(@"[AppToolsRatio] Found notification title at %lu, but image/handler arrays are not aligned",
                  (unsigned long)index);
            return NO;
        }

        ATPopupViewController *popup = ATRatioPopupForBar(bar);
        NSString *bundleID = [popup.bundleID copy];
        void (^ratioHandler)(void) = ATRatioMakeTileHandler(bar, popup, bundleID);

        NSMutableArray *images = [oldImages mutableCopy];
        NSMutableArray *handlers = [oldHandlers mutableCopy];
        images[index] = ATRatioCreateIcon() ?: images[index];
        handlers[index] = [ratioHandler copy];

        objc_setAssociatedObject(bar, &kATRatioApplyingAssociation, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar setTitle:kATRatioTitle forItemAtIndex:(NSInteger)index];
        [bar setDetail:@"" forItemAtIndex:(NSInteger)index];
        [bar setItemImages:images];
        [bar setItemHandlers:handlers];
        objc_setAssociatedObject(bar, &kATRatioApplyingAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        NSLog(@"[AppToolsRatio] Replaced exact notification tile at index %lu in row %@ (bundle=%@)",
              (unsigned long)index, bar.rowStorageKey ?: @"<unknown>", bundleID ?: @"<not-ready>");
        return YES;
    }

    return NO;
}

#pragma mark - AppTools hooks

%group ATRatioExactNotificationTile

%hook ATPopupViewController

- (void)viewDidLoad {
    %orig;
    gATRatioVisiblePopup = (ATPopupViewController *)self;
}

- (void)viewWillAppear:(BOOL)animated {
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
    ATActionsBarView *bar = %orig;
    if (bar) {
        objc_setAssociatedObject(bar, &kATRatioPopupAssociation,
            [NSValue valueWithNonretainedObject:self], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        /* No forced row-key assignment and no tile-index assumptions. */
        if ([rowStorageKey isKindOfClass:[NSString class]]) {
            NSLog(@"[AppToolsRatio] Captured AppTools action bar %@ for %@", rowStorageKey, self.bundleID);
        }
    }
    return bar;
}

%end

%hook ATActionsBarView

/*
 * Critical path: substitute the callback before AppTools stores it in its
 * action-bar model. The original notification handler is never passed to %orig.
 * Only the exact notification title is eligible; Ghim chạy nền is untouched.
 */
- (void)addItemWithTitle:(NSString *)title
                  detail:(NSString *)detail
                   image:(UIImage *)image
                 handler:(void (^)(void))handler {
    if (ATRatioIsNotificationTile(title, image)) {
        ATPopupViewController *popup = ATRatioPopupForBar((ATActionsBarView *)self);
        NSString *bundleID = [popup.bundleID copy];
        void (^ratioHandler)(void) = ATRatioMakeTileHandler((ATActionsBarView *)self, popup, bundleID);
        NSLog(@"[AppToolsRatio] Matched notification tile title '%@'; replacing title and handler", title);
        %orig(kATRatioTitle, @"", ATRatioCreateIcon() ?: image, ratioHandler);
        return;
    }

    %orig(title, detail, image, handler);
}

/* Cached-row fallback: search by the exact notification title, never by index. */
- (void)rebuildArrangedSubviews {
    if (![objc_getAssociatedObject(self, &kATRatioApplyingAssociation) boolValue]) {
        ATRatioReplaceRegisteredNotificationTile((ATActionsBarView *)self);
    }
    %orig;
}

- (void)finishAddingItems {
    %orig;
    if (![objc_getAssociatedObject(self, &kATRatioApplyingAssociation) boolValue] &&
        ATRatioReplaceRegisteredNotificationTile((ATActionsBarView *)self)) {
        objc_setAssociatedObject(self, &kATRatioApplyingAssociation, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self rebuildArrangedSubviews];
        objc_setAssociatedObject(self, &kATRatioApplyingAssociation, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end
%end

#pragma mark - Hook installation

static BOOL gATRatioUIHooksInstalled = NO;
static NSUInteger gATRatioUIInstallAttempts = 0;

static void ATRatioTryInstallUIHooks(void) {
    if (gATRatioUIHooksInstalled) return;

    Class popupClass = objc_getClass("ATPopupViewController");
    Class barClass = objc_getClass("ATActionsBarView");
    BOOL popupReady = popupClass &&
        class_getInstanceMethod(popupClass, @selector(liveActionsBarWithRowStorageKey:));
    BOOL barReady = barClass &&
        class_getInstanceMethod(barClass, @selector(addItemWithTitle:detail:image:handler:)) &&
        class_getInstanceMethod(barClass, @selector(rebuildArrangedSubviews)) &&
        class_getInstanceMethod(barClass, @selector(finishAddingItems));

    if (popupReady && barReady) {
        %init(ATRatioExactNotificationTile);
        gATRatioUIHooksInstalled = YES;
        NSLog(@"[AppToolsRatio] Exact notification-tile hooks installed");
        return;
    }

    if (gATRatioUIInstallAttempts++ < 240) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ATRatioTryInstallUIHooks(); });
    } else {
        NSLog(@"[AppToolsRatio] Cannot install tile hooks (ATPopup=%p ATActionsBar=%p)",
              popupClass, barClass);
    }
}

__attribute__((constructor))
static void ATRatioExactTileInit(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;
        NSLog(@"[AppToolsRatio] Exact-tile replacement loaded in SpringBoard");
        dispatch_async(dispatch_get_main_queue(), ^{ ATRatioTryInstallUIHooks(); });
    }
}
