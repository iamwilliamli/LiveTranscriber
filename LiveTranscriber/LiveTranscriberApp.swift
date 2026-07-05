import SwiftUI

@main
struct LiveTranscriberApp: App {

    init() {
        AppTypography.configureUIKitAppearances()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
