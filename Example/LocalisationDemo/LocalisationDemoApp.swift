import FlutterLocalisation
import SwiftUI

@main
struct LocalisationDemoApp: App {
    // Created before the first view so every lookup already goes through it.
    @StateObject private var live = LiveLocalisation(
        secretKey: Bundle.main.object(forInfoDictionaryKey: "FLSecretKey") as? String,
        projectId: Int(Bundle.main.object(forInfoDictionaryKey: "FLProjectId") as? String ?? "") ?? 0,
        flavor: Bundle.main.object(forInfoDictionaryKey: "FLFlavor") as? String ?? "Default",
        logging: true
    )

    var body: some Scene {
        WindowGroup {
            HomeView()
                .liveLocalisation(live)
                .tint(Palette.accent)
                .task { live.start() }
        }
    }
}
