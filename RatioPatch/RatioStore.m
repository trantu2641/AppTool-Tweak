#import "RatioStore.h"
#import <CoreFoundation/CoreFoundation.h>

@implementation ATRatioStore

+ (instancetype)sharedStore {
    static ATRatioStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[ATRatioStore alloc] init];
    });
    return store;
}

#pragma mark - CFPreferences helpers

- (CFStringRef)appIDForBundleID:(NSString *)bundleID {
    return (__bridge CFStringRef)bundleID;
}

- (NSMutableDictionary *)loadRegistry {
    CFPropertyListRef value = CFPreferencesCopyValue(
        (__bridge CFStringRef)ATRatioRegistryKey,
        (__bridge CFStringRef)ATRatioRegistryDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );

    id object = value ? CFBridgingRelease(value) : nil;
    if ([object isKindOfClass:[NSDictionary class]]) {
        return [object mutableCopy];
    }
    return [NSMutableDictionary dictionary];
}

- (void)saveRegistry:(NSDictionary *)registry {
    CFPreferencesSetValue(
        (__bridge CFStringRef)ATRatioRegistryKey,
        (__bridge CFPropertyListRef)registry,
        (__bridge CFStringRef)ATRatioRegistryDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    CFPreferencesSynchronize(
        (__bridge CFStringRef)ATRatioRegistryDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
}

- (void)postRatioChangedNotification {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)ATRatioNotification,
        NULL,
        NULL,
        YES
    );
}

#pragma mark - Public API

- (void)setRatio:(ATRatio)ratio forBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) return;
    if (!ATRatioValid(ratio)) return;

    NSDictionary *entry = @{
        @"width": @(ratio.width),
        @"height": @(ratio.height)
    };

    /*
     * Write to the selected target application's own preference domain.
     * The target runtime reads this same domain from inside that app.
     */
    CFStringRef appID = [self appIDForBundleID:bundleID];
    CFPreferencesSetValue(
        (__bridge CFStringRef)ATRatioPreferenceKey,
        (__bridge CFPropertyListRef)entry,
        appID,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    Boolean synchronized = CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef verifyValue = CFPreferencesCopyValue(
        (__bridge CFStringRef)ATRatioPreferenceKey,
        appID,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    id verified = verifyValue ? CFBridgingRelease(verifyValue) : nil;
    NSLog(@"[AppToolsRatio] Saved ratio for %@: %0.3f:%0.3f sync=%@ verified=%@",
          bundleID, ratio.width, ratio.height,
          synchronized ? @"YES" : @"NO",
          [verified isKindOfClass:[NSDictionary class]] ? @"YES" : @"NO");

    NSMutableDictionary *registry = [self loadRegistry];
    registry[bundleID] = entry;
    [self saveRegistry:registry];

    [self postRatioChangedNotification];
}

- (void)removeRatioForBundleID:(NSString *)bundleID {
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) return;

    CFStringRef appID = [self appIDForBundleID:bundleID];
    CFPreferencesSetValue(
        (__bridge CFStringRef)ATRatioPreferenceKey,
        NULL,
        appID,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    NSMutableDictionary *registry = [self loadRegistry];
    [registry removeObjectForKey:bundleID];
    [self saveRegistry:registry];

    [self postRatioChangedNotification];
}

- (BOOL)ratioForBundleID:(NSString *)bundleID ratio:(ATRatio *)ratio {
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0 || ratio == NULL) {
        return NO;
    }

    CFStringRef appID = [self appIDForBundleID:bundleID];
    Boolean synchronized = CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    CFPropertyListRef value = CFPreferencesCopyValue(
        (__bridge CFStringRef)ATRatioPreferenceKey,
        appID,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );

    id object = value ? CFBridgingRelease(value) : nil;
    if (![object isKindOfClass:[NSDictionary class]]) {
        /*
         * Cross-app app-domain preferences may be hidden by iOS sandboxing.
         * The same value is also stored in AppTools' own shared registry,
         * keyed by the target Bundle ID. Try that stable tweak-owned domain
         * before treating the selection as absent.
         */
        NSDictionary *registry = [self loadRegistry];
        id fallback = registry[bundleID];
        if ([fallback isKindOfClass:[NSDictionary class]]) {
            object = fallback;
            NSLog(@"[AppToolsRatio] Loaded %@ from the shared AppTools registry fallback", bundleID);
        } else {
            NSLog(@"[AppToolsRatio] No ratio preference for %@ (sync=%@, registry fallback absent)",
                  bundleID, synchronized ? @"YES" : @"NO");
            return NO;
        }
    }

    NSDictionary *entry = (NSDictionary *)object;
    CGFloat width = [entry[@"width"] doubleValue];
    CGFloat height = [entry[@"height"] doubleValue];
    ATRatio result = ATRatioMake(width, height);

    if (!ATRatioValid(result)) {
        NSLog(@"[AppToolsRatio] Invalid stored ratio for %@", bundleID);
        return NO;
    }
    *ratio = result;
    NSLog(@"[AppToolsRatio] Read ratio for %@: %0.3f:%0.3f", bundleID, result.width, result.height);
    return YES;
}

- (NSDictionary *)allRatios {
    return [[self loadRegistry] copy];
}

@end
