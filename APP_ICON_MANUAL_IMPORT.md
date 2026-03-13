# App Icon Manual Import

Use this if you are providing custom icon assets outside of Xcode's template.

## Required Steps
1. Prepare icon set from a 1024x1024 source image (no alpha for App Store icon).
2. Open `BackgroundRemover/Assets.xcassets/AppIcon.appiconset` in Xcode.
3. Drag each icon size into the matching slot.
4. Verify no empty required slots remain.
5. Build and run on iPhone and iPad targets.

## Optional Validation
- Archive once to confirm no missing icon warnings.
- Check App Store Connect upload validation for icon compliance.
