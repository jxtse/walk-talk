# Resources

This directory holds assets that, in the eventual `.xcodeproj` migration, will
move into the app target's bundle. For SPM development on non-Mac hosts:

- `Info.plist` — canonical permissions / capabilities reference. When the
  project becomes an Xcode project this file goes into Build Settings →
  "Info.plist File" of the app target.
- `bgm/` — background music placeholder for the keepsake video (P5 / A6).
- `sample_frames/` — bundled fixture images for `MockCameraBridge` (P1-T3).
- `Secrets.example.plist` — committed template for runtime keys; copy to
  `Secrets.plist` (gitignored) and fill in real values.

The Insta360 iOS SDK binary is **not** vendored. See
`docs/superpowers/decisions/A2-insta360-ios-sdk.md` and the LOOKUP markers in
`Sources/LocalGravity/Camera/Insta360CameraBridge.swift` for what to drop in
when the SDK is available on a Mac.
