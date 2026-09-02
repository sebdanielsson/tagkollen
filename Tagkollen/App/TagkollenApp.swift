import SwiftData
import SwiftUI

@main
struct TagkollenApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(dependencies.apiKeyStore)
                .environment(dependencies.stations)
                .environment(dependencies.live)
                .environment(dependencies.delays)
                .environment(dependencies.journeys)
                .environment(dependencies.location)
                .environment(dependencies.speech)
                .environment(dependencies.settings)
                .task { await dependencies.start() }
        }
        .modelContainer(dependencies.modelContainer)
    }
}
