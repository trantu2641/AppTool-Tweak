#import "RatioStore.h"

@implementation ATRatioStore

+ (instancetype)sharedStore {
    static ATRatioStore *store = nil;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        store = [[ATRatioStore alloc] init];
    });

    return store;
}

#pragma mark - Internal

- (NSMutableDictionary *)load {
    NSDictionary *dictionary =
        [NSDictionary dictionaryWithContentsOfFile:ATRatioStorePath];

    if (!dictionary)
        return [NSMutableDictionary dictionary];

    return [dictionary mutableCopy];
}

- (void)save:(NSDictionary *)dictionary {

    NSString *directory =
        [ATRatioStorePath stringByDeletingLastPathComponent];

    [[NSFileManager defaultManager]
        createDirectoryAtPath:directory
        withIntermediateDirectories:YES
        attributes:nil
        error:nil];

    [dictionary writeToFile:ATRatioStorePath
                 atomically:YES];
}

#pragma mark - Public

- (void)setRatio:(ATRatio)ratio
      forBundleID:(NSString *)bundleID {

    if (!bundleID.length)
        return;

    if (!ATRatioValid(ratio))
        return;

    NSMutableDictionary *all = [self load];

    all[bundleID] = @{
        @"width": @(ratio.width),
        @"height": @(ratio.height)
    };

    [self save:all];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)ATRatioNotification,
        NULL,
        NULL,
        YES
    );
}

- (void)removeRatioForBundleID:(NSString *)bundleID {

    if (!bundleID.length)
        return;

    NSMutableDictionary *all = [self load];

    [all removeObjectForKey:bundleID];

    [self save:all];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)ATRatioNotification,
        NULL,
        NULL,
        YES
    );
}

- (BOOL)ratioForBundleID:(NSString *)bundleID
                    ratio:(ATRatio *)ratio {

    if (!bundleID.length || !ratio)
        return NO;

    NSDictionary *all = [self load];

    NSDictionary *entry =
        all[bundleID];

    if (!entry)
        return NO;

    CGFloat width =
        [entry[@"width"] doubleValue];

    CGFloat height =
        [entry[@"height"] doubleValue];

    ATRatio result =
        ATRatioMake(width, height);

    if (!ATRatioValid(result))
        return NO;

    *ratio = result;

    return YES;
}

- (NSDictionary *)allRatios {
    return [self load];
}

@end
