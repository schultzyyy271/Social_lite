#import <Foundation/Foundation.h>

static NSString * const HasActiveSubscriptionKey = @"hasActiveSubscription";
static NSString * const PurchasedTierKey = @"storeKitPurchasedTier";
static NSString * const EntitlementChanged = @"StoreKitEntitlementChanged";

/// Mock of sub_100BF72A4: persist a StoreKit-derived entitlement and notify listeners.
void MockEvaluateStoreKitTransaction(BOOL active, NSString *tier) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:active forKey:HasActiveSubscriptionKey];
    if (active && tier.length > 0) {
        [defaults setObject:tier forKey:PurchasedTierKey];
    } else {
        [defaults removeObjectForKey:PurchasedTierKey];
    }
    [defaults synchronize];
    [NSNotificationCenter.defaultCenter postNotificationName:EntitlementChanged
                                                       object:nil
                                                     userInfo:@{HasActiveSubscriptionKey: @(active),
                                                                PurchasedTierKey: tier ?: NSNull.null}];
}

/// Mock of the observed RevenueCat customer-info forwarding path.
void MockHandleRevenueCatCustomerInfo(BOOL active, NSString *tier) {
    MockEvaluateStoreKitTransaction(active, tier);
}

/// Read the locally persisted mock state. This is not a universal feature-access check.
NSDictionary<NSString *, id> *MockReadEntitlementState(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return @{HasActiveSubscriptionKey: @([defaults boolForKey:HasActiveSubscriptionKey]),
             PurchasedTierKey: [defaults objectForKey:PurchasedTierKey] ?: NSNull.null};
}

// Demo main() available via: clang -DMOCK_ENTITLEMENTS_DEMO MockEntitlements.m -framework Foundation -o demo
#ifdef MOCK_ENTITLEMENTS_DEMO
int main(void) {
    @autoreleasepool {
        id observer = [NSNotificationCenter.defaultCenter
            addObserverForName:EntitlementChanged object:nil queue:nil
            usingBlock:^(NSNotification *note) { NSLog(@"Changed: %@", note.userInfo); }];
        MockHandleRevenueCatCustomerInfo(YES, @"premium");
        NSLog(@"State after active update: %@", MockReadEntitlementState());
        MockEvaluateStoreKitTransaction(NO, nil);
        NSLog(@"State after inactive update: %@", MockReadEntitlementState());
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    return 0;
}
#endif

