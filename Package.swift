// swift-tools-version:5.9
import PackageDescription

// LocalGravity — Swift Package Manager manifest.
//
// This package mirrors the structure described in
// docs/superpowers/plans/2026-05-02-local-gravity-implementation.md "File Structure".
// On Windows / non-Mac development hosts there is no Xcode toolchain available,
// so we use SPM as the source-of-truth project layout. When migrating to a real
// Xcode project, copy `Sources/LocalGravity/**` into the `WalkTalk` target and
// `Sources/LocalGravityApp/**` into the app target's `App/` group, and move
// `Resources/Info.plist` into the app target's Info.plist setting.
let package = Package(
    name: "LocalGravity",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "LocalGravity", targets: ["LocalGravity"]),
        .executable(name: "LocalGravityApp", targets: ["LocalGravityApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LocalGravity",
            path: "Sources/LocalGravity",
            resources: [
                // Info.plist is intentionally not declared as a process resource
                // here — SPM does not allow Info.plist inside libraries. It lives
                // under Resources/ as the canonical reference for the eventual
                // .xcodeproj migration. See Resources/README.md.
            ]
        ),
        .executableTarget(
            name: "LocalGravityApp",
            dependencies: ["LocalGravity"],
            path: "Sources/LocalGravityApp"
        ),
        .testTarget(
            name: "LocalGravityTests",
            dependencies: ["LocalGravity"],
            path: "Tests/LocalGravityTests"
        )
    ]
)
