# SDK Setup

This document is the migration guide for adding the two vendor SDKs to the
Xcode project once we move off SPM. The repository deliberately does **not**
vendor the binary frameworks — both must be downloaded from their respective
developer centers.

## 高德 iOS SDK

Reference: <https://lbs.amap.com/api/ios-sdk/guide/create-project/dev-attention>

1. Register an Amap developer account, create an iOS app, generate an
   `AMapApiKey`. Bundle id must match the app target.
2. Add via Swift Package Manager (preferred): use the current official SPM
   mirror listed in the Amap iOS docs. If SPM is not available, drop the
   `.framework` files into `Frameworks/` and link them in target settings.
3. Required modules: `AMapFoundationKit`, `MAMapKit`, `AMapSearchKit`.
4. Initialize at app start:
   ```swift
   AMapServices.shared().apiKey = Secrets.shared.amapApiKey
   AMapServices.shared().enableHTTPS = true
   ```
5. The Web Service REST APIs (used by `AmapClient`) accept the same key. We
   ship one default test key (`ff287a156a20b1b95830b719d6c6a047`) read via
   the `AMAP_KEY` environment variable as a fallback.

## Insta360 iOS SDK

Reference: <http://onlinemanual.insta360.com/developer/zh-cn/resource/sdk>

1. Download the iOS Camera SDK package from Insta360's developer resource
   center.
2. Drop `INSCameraSDK.framework` (and any companion frameworks listed in the
   SDK README) into `Frameworks/`. Add to "Frameworks, Libraries, and
   Embedded Content" with **Embed & Sign**.
3. LOOKUP: confirm the exact framework name(s) and any required system
   dependencies (libstdc++, libc++, libz, etc.) in the SDK README.
4. Replace the `LOOKUP-*` markers in
   `Sources/LocalGravity/Camera/Insta360CameraBridge.swift` per the
   instructions in each marker.

## Info.plist permissions

See `Resources/Info.plist` for the canonical reference. Keys required:

| Key | Why |
|---|---|
| `NSCameraUsageDescription` | Often required by Insta360 SDK link |
| `NSMicrophoneUsageDescription` | AI dialog (P3) |
| `NSSpeechRecognitionUsageDescription` | STT (P3) |
| `NSLocationWhenInUseUsageDescription` | GPS recording |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Pocket / locked-screen recording |
| `NSLocalNetworkUsageDescription` | Insta360 WiFi |
| `NSBonjourServices` | Insta360 discovery |
| `UIBackgroundModes` ⊇ `location`, `audio` | Background walk loop |

## Secrets

`Resources/Secrets.example.plist` is the committed template. Copy to
`Secrets.plist` (gitignored) and populate before running on device.
