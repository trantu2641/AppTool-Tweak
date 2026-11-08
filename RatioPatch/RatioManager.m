#import "RatioManager.h"

static NSString * const ATRatioPreferencesKey = @"AppToolsScreenRatios";

@implementation ATRatioManager

+ (instancetype)sharedManager {
    static ATRatioManager *manager;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        manager = [[ATRatioManager alloc] init];
    });

    return manager;
}

#pragma mark - Storage

- (NSMutableDictionary *)storedRatios {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSDictionary *dictionary =
        [defaults dictionaryForKey:ATRatioPreferencesKey];

    if (dictionary) {
        return [dictionary mutableCopy];
    }

    return [NSMutableDictionary dictionary];
}

- (void)saveRatios:(NSDictionary *)ratios {
    [[NSUserDefaults standardUserDefaults]
        setObject:ratios
        forKey:ATRatioPreferencesKey];

    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Ratio

- (void)setRatioForBundleID:(NSString *)bundleID
                      width:(CGFloat)width
                     height:(CGFloat)height {

    if (!bundleID || bundleID.length == 0)
        return;

    if (width <= 0 || height <= 0)
        return;

    NSMutableDictionary *all = [self storedRatios];

    all[bundleID] = @{
        @"width": @(width),
        @"height": @(height),
        @"ratio": [NSString stringWithFormat:@"%.0f:%.0f",
                   width,
                   height]
    };

    [self saveRatios:all];
}

- (void)setPresetRatioForBundleID:(NSString *)bundleID
                            ratio:(NSString *)ratio {

    if (!bundleID || !ratio)
        return;

    CGFloat width = 0;
    CGFloat height = 0;

    if ([ratio isEqualToString:@"16:9"]) {
        width = 16;
        height = 9;
    }
    else if ([ratio isEqualToString:@"4:3"]) {
        width = 4;
        height = 3;
    }
    else if ([ratio isEqualToString:@"3:2"]) {
        width = 3;
        height = 2;
    }
    else if ([ratio isEqualToString:@"18:9"]) {
        width = 18;
        height = 9;
    }
    else if ([ratio isEqualToString:@"19.5:9"]) {
        width = 19.5;
        height = 9;
    }
    else if ([ratio isEqualToString:@"21:9"]) {
        width = 21;
        height = 9;
    }
    else {
        return;
    }

    [self setRatioForBundleID:bundleID
                        width:width
                       height:height];
}

- (NSDictionary *)ratioForBundleID:(NSString *)bundleID {

    if (!bundleID)
        return nil;

    NSDictionary *all =
        [[NSUserDefaults standardUserDefaults]
            dictionaryForKey:ATRatioPreferencesKey];

    return all[bundleID];
}

#pragma mark - Apply

- (void)applyRatioToApplication:(UIApplication *)application {

    if (!application)
        return;

    NSString *bundleID =
        application.bundleIdentifier;

    if (!bundleID)
        return;

    NSDictionary *ratio =
        [self ratioForBundleID:bundleID];

    if (!ratio)
        return;

    CGFloat width =
        [ratio[@"width"] doubleValue];

    CGFloat height =
        [ratio[@"height"] doubleValue];

    if (width <= 0 || height <= 0)
        return;

    for (UIWindow *window in application.windows) {

        if (!window)
            continue;

        [self applyRatioToWindow:window
                            width:width
                           height:height];
    }
}

- (void)applyRatioToWindow:(UIWindow *)window
                     width:(CGFloat)width
                    height:(CGFloat)height {

    if (!window)
        return;

    UIScreen *screen =
        window.screen ?: UIScreen.mainScreen;

    CGRect screenBounds =
        screen.bounds;

    CGFloat screenWidth =
        CGRectGetWidth(screenBounds);

    CGFloat screenHeight =
        CGRectGetHeight(screenBounds);

    if (screenWidth <= 0 || screenHeight <= 0)
        return;

    CGFloat targetRatio =
        width / height;

    CGFloat currentRatio =
        screenWidth / screenHeight;

    if (fabs(currentRatio - targetRatio) < 0.01)
        return;

    CGRect newFrame =
        window.frame;

    CGFloat newWidth =
        screenWidth;

    CGFloat newHeight =
        screenWidth / targetRatio;

    if (newHeight > screenHeight) {

        newHeight = screenHeight;
        newWidth = screenHeight * targetRatio;
    }

    newFrame.size.width =
        newWidth;

    newFrame.size.height =
        newHeight;

    newFrame.origin.x =
        (screenWidth - newWidth) / 2.0;

    newFrame.origin.y =
        (screenHeight - newHeight) / 2.0;

    [UIView performWithoutAnimation:^{
        window.frame = newFrame;
    }];
}

@end
