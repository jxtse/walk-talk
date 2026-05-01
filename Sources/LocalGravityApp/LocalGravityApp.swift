// Sources/LocalGravityApp/LocalGravityApp.swift
//
// SwiftUI @main entry. Mirrors `WalkTalk/App/WalkTalkApp.swift` from the plan.
import SwiftUI
import LocalGravity

@main
struct LocalGravityApp: App {
    init() {
        // LOOKUP-AMAP-2: register the 高德 SDK key here when migrating to .xcodeproj.
        //   AMapServices.shared().apiKey = Secrets.shared.amapApiKey
        //   AMapServices.shared().enableHTTPS = true
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
