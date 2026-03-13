# Background Removal Testing Notes

## Simulator vs Real Device
Background removal in this app uses Apple-native Vision subject extraction APIs.
These APIs can be limited or unstable in iOS Simulator depending on host machine/runtime capabilities.

If Simulator logs include errors like:
- `CSU exception: Failed to create espresso context`
- `E5RT is not supported`
- `Could not perform the Vision request`

then background extraction should be considered **simulator-limited** for that environment.

## Expected App Behavior
- On Simulator runtime limitation, the app should show:
  - "Background removal may be unavailable in Simulator. Please test on a real device."
- On true extraction failure (valid runtime, unclear subject), the app should show:
  - "We couldn't isolate a clear subject in this image. Try a photo with one person or object in the foreground."
- On other processing failures, the app should show:
  - "Background removal failed. Please try again."

## Recommended Real-Device Validation (iPhone/iPad)
1. Run the app on a physical iOS 17+ device.
2. Test with:
   - single-person portrait,
   - selfie (close-up face/upper body),
   - object on clean background,
   - cluttered background scene.
3. Verify **Original / Cutout** preview toggles correctly.
4. Save as PNG and verify transparency in Photos/share target.
