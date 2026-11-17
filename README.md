# Theos RevenueCat entitlement hook

This is an iOS Theos/Logos tweak, not a standalone dylib mock. `Tweak.x` hooks the Objective-C RevenueCat delegate method identified in the active IDA database:

`-[ _TtC11Social_liteP33_56388F9416EA7BE1764AF6EDC1F969E014RCDelegateShim purchases:receivedUpdatedCustomerInfo:]`

The tweak calls `%orig`, seeds selected `NSUserDefaults` entitlement keys, forces reads of those keys to remain active, and logs callback arrival. It is version-specific and is not guaranteed to control the app's complete feature-access path.

## Build

On a macOS host configured with Theos and an iOS SDK:

```sh
make package
```
Install the package on a test device. The current Makefile targets the `Social_lite` executable via `INSTALL_TARGET_PROCESSES = Social_lite`. If the installed app reports a different executable name, update that setting before building. The app bundle identifier is not required for this process-name setting.

## Verification

Inspect the device log for:

```text
[MockEntitlementHooks] ctor: seeded all entitlement keys
[MockEntitlementHooks] RCDelegateShim fired
```

If the constructor message is absent, injection or package targeting is incorrect. If the constructor appears but the callback message does not, the Swift class or selector no longer matches the target binary. If both appear but access remains locked, the app is using another entitlement path.

## Scope and limitations

IDA identifies `-[RCDelegateShim purchases:receivedUpdatedCustomerInfo:]` at `0x10112F064`; its ABI is `(self, _cmd, purchases, customerInfo)`. The method forwards both objects to Swift `sub_10112EE94`, which schedules MainActor work. This hook does not hook or decode the Swift task.

Do not hook `sub_100BF72A4` by its current address: IDA shows a Swift async-iterator state-machine routine with compiler-managed context, not a stable C-callable ABI. The observed transaction write is to `storeKitHasActiveEntitlement` (at `0x100BF77DC`) and `storeKitPurchasedTier`; the user-provided `hasActiveSubscription` evidence refers to other client-side routines. These paths are not proof of a universal paid-feature gate.

`MockEntitlements.m` is an isolated behavior demo and is intentionally excluded from the tweak target.
