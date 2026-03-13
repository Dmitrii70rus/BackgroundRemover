# Release Checklist

## Product & StoreKit
- [ ] Create App Store Connect app record and bundle ID.
- [ ] Add non-consumable IAP product: `backgroundremover.premium.unlock`.
- [ ] Set product display name, description, and pricing.
- [ ] Submit IAP for review with screenshots.

## Project Configuration
- [ ] Confirm deployment target is iOS 17.0+.
- [ ] Confirm Info.plist photo usage descriptions are present.
- [ ] Confirm StoreKit configuration file is selected for local testing in scheme.

## Functional QA
- [ ] Select photo from library.
- [ ] Remove background on at least 3 different photos.
- [ ] Verify preview compare (Original/Cutout).
- [ ] Verify cutout transparency checkerboard preview.
- [ ] Save PNG and confirm transparency in Photos/files target app.
- [ ] Share PNG to at least one external app.
- [ ] Verify free limit blocks on 4th attempt for non-premium.
- [ ] Verify premium unlock removes limit.
- [ ] Verify restore purchases succeeds after reinstall/sign-out scenario.

## Compliance
- [ ] Verify metadata text and screenshots.
- [ ] Verify privacy policy URL is live.
- [ ] Confirm app does not claim unsupported capabilities.
- [ ] Verify no crash on denied photo permissions.

## Build & Submission
- [ ] Archive release build.
- [ ] Validate build in Organizer.
- [ ] Upload build to App Store Connect.
- [ ] Attach build to app version and submit for review.
