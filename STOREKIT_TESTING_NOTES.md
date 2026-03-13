# StoreKit Testing Notes

## Local Simulator Setup
1. Open the Xcode scheme for `BackgroundRemover`.
2. Edit Scheme → Run → Options.
3. Select `BackgroundRemover/BackgroundRemover.storekit` under **StoreKit Configuration**.
4. Run on an iOS 17+ simulator.

## Test Cases
- Purchase success path for `backgroundremover.premium.unlock`.
- User-cancelled purchase path.
- Pending transaction path.
- Restore purchases path.
- App relaunch with existing entitlement.

## Expected App Behavior
- Product loads on launch and paywall shows unlock button with local test price.
- Successful purchase unlocks premium immediately.
- Premium state persists across launches via entitlement refresh.
- Restore rehydrates premium state.
- Free-use counter should no longer decrease after unlock.
