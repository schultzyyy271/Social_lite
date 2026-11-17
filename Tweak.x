#import <Foundation/Foundation.h>

// ---------------------------------------------------------------------------
// Key inventory (IDA xref table)
//
// storeKitHasActiveEntitlement  — primary gate; most callers go through
//                                 sub_100FCDCD0 which has dozens of xrefs.
// hasActiveSubscription         — secondary; read by sub_100035290/690,
//                                 sub_100035D1C, sub_100FA6030, sub_100FAC55C.
// storeKitPurchasedTier         — tier string consumed alongside both booleans.
// subscriptionTier              — additional tier key (sub_100FA6030/FAC55C).
// subscriptionCancelled         — cancellation flag; force NO to suppress
//                                 revocation paths in sub_100FCE1A8.
// cancelAtTimestamp             — expiry; leave at 0 / absent.
// debugTierOverride             — app's own debug-override path (sub_100FA6030).
// adminOverrideTier             — admin-override path (sub_100FA6030/FAC55C).
//                                 Writing these exploits the app's own bypass.
// ---------------------------------------------------------------------------

static NSString * const kStoreKitActive      = @"storeKitHasActiveEntitlement";
static NSString * const kHasActiveSub        = @"hasActiveSubscription";
static NSString * const kStoreKitTier        = @"storeKitPurchasedTier";
static NSString * const kSubscriptionTier    = @"subscriptionTier";
static NSString * const kSubCancelled        = @"subscriptionCancelled";
static NSString * const kCancelAt            = @"cancelAtTimestamp";
static NSString * const kDebugTier           = @"debugTierOverride";
static NSString * const kAdminTier           = @"adminOverrideTier";
static NSString * const kEntitlementChanged  = @"StoreKitEntitlementChanged";

static NSString * const kForcedTier          = @"premium";

// Keys whose bool value must always read YES.
static BOOL IsForcedYesKey(NSString *key) {
    return [key isEqualToString:kStoreKitActive] ||
           [key isEqualToString:kHasActiveSub];
}

// Keys whose bool value must always read NO.
static BOOL IsForcedNoKey(NSString *key) {
    return [key isEqualToString:kSubCancelled];
}

// Keys that must always return a non-nil string value.
static BOOL IsTierKey(NSString *key) {
    return [key isEqualToString:kStoreKitTier]     ||
           [key isEqualToString:kSubscriptionTier] ||
           [key isEqualToString:kDebugTier]        ||
           [key isEqualToString:kAdminTier];
}

// ---------------------------------------------------------------------------
// Hook: NSUserDefaults — intercept every read and write of entitlement keys.
// ---------------------------------------------------------------------------

%hook NSUserDefaults

// ----- reads -----

- (BOOL)boolForKey:(NSString *)key {
    if (IsForcedYesKey(key)) return YES;
    if (IsForcedNoKey(key))  return NO;
    return %orig;
}

- (id)objectForKey:(NSString *)key {
    if (IsTierKey(key)) {
        id v = %orig;
        return v ?: kForcedTier;
    }
    // cancelAtTimestamp: return nil/0 so no expiry is enforced.
    if ([key isEqualToString:kCancelAt]) return nil;
    return %orig;
}

- (NSInteger)integerForKey:(NSString *)key {
    if ([key isEqualToString:kCancelAt]) return 0;
    return %orig;
}

- (double)doubleForKey:(NSString *)key {
    if ([key isEqualToString:kCancelAt]) return 0.0;
    return %orig;
}

// ----- writes -----

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    if (IsForcedYesKey(key)) { %orig(YES, key); return; }
    if (IsForcedNoKey(key))  { %orig(NO,  key); return; }
    %orig;
}

- (void)setObject:(id)value forKey:(NSString *)key {
    // Suppress tier removal while subscription is active.
    if (IsTierKey(key) && (value == nil || value == (id)[NSNull null])) {
        NSLog(@"[MockEntitlementHooks] suppressing tier removal for %@", key);
        return;
    }
    // Suppress setting a cancellation timestamp.
    if ([key isEqualToString:kCancelAt]) {
        NSLog(@"[MockEntitlementHooks] suppressing cancelAtTimestamp write");
        return;
    }
    %orig;
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    if ([key isEqualToString:kCancelAt]) return;
    %orig;
}

- (void)setDouble:(double)value forKey:(NSString *)key {
    if ([key isEqualToString:kCancelAt]) return;
    %orig;
}

- (void)removeObjectForKey:(NSString *)key {
    // Don't allow the app to delete any of our forced keys.
    if (IsForcedYesKey(key) || IsTierKey(key)) {
        NSLog(@"[MockEntitlementHooks] suppressing removeObjectForKey:%@", key);
        return;
    }
    %orig;
}

%end

// ---------------------------------------------------------------------------
// Hook: RevenueCat delegate — let %orig run, then overwrite defaults.
//   IDA: -[RCDelegateShim purchases:receivedUpdatedCustomerInfo:] @ 0x10112F064
// ---------------------------------------------------------------------------

%hook _TtC11Social_liteP33_56388F9416EA7BE1764AF6EDC1F969E014RCDelegateShim

- (void)purchases:(id)purchases receivedUpdatedCustomerInfo:(id)customerInfo {
    %orig;  // let RevenueCat update its own in-memory cache normally

    NSLog(@"[MockEntitlementHooks] RCDelegateShim fired; re-asserting entitlement state");

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    // Re-assert after %orig in case sub_10112EE94's MainActor work writes NO.
    // The NSUserDefaults hooks above will also intercept those writes, but an
    // explicit re-assert here covers any async dispatch that settles later.
    [d setBool:YES forKey:kStoreKitActive];
    [d setBool:YES forKey:kHasActiveSub];
    [d setBool:NO  forKey:kSubCancelled];
    if (![d objectForKey:kStoreKitTier])
        [d setObject:kForcedTier forKey:kStoreKitTier];
    if (![d objectForKey:kSubscriptionTier])
        [d setObject:kForcedTier forKey:kSubscriptionTier];
    [d synchronize];

    [NSNotificationCenter.defaultCenter
        postNotificationName:kEntitlementChanged
                      object:nil
                    userInfo:@{kStoreKitActive: @YES,
                               kHasActiveSub:   @YES,
                               kStoreKitTier:   kForcedTier}];
}

%end

// ---------------------------------------------------------------------------
// %ctor: seed all entitlement keys before any app code reads them.
//
// debugTierOverride / adminOverrideTier exploit the app's own override path
// (sub_100FA6030, sub_100FAC55C) — if the app respects these, it grants
// access without touching the StoreKit / RevenueCat state machine at all.
// ---------------------------------------------------------------------------

%ctor {
    @autoreleasepool {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;

        [d setBool:YES forKey:kStoreKitActive];
        [d setBool:YES forKey:kHasActiveSub];
        [d setBool:NO  forKey:kSubCancelled];
        [d setObject:kForcedTier forKey:kStoreKitTier];
        [d setObject:kForcedTier forKey:kSubscriptionTier];

        // Exploit the app's own debug/admin override path.
        [d setObject:kForcedTier forKey:kDebugTier];
        [d setObject:kForcedTier forKey:kAdminTier];

        // Remove any stale cancellation timestamp.
        [d removeObjectForKey:kCancelAt];

        [d synchronize];

        NSLog(@"[MockEntitlementHooks] ctor: seeded all entitlement keys (tier=%@)", kForcedTier);
    }
}
