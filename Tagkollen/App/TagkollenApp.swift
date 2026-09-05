import SwiftData
import SwiftUI
import UserNotifications

@main
struct TagkollenApp: App {
    @State private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate: NotificationDelegate

    init() {
        let dependencies = AppDependencies()
        _dependencies = State(initialValue: dependencies)
        TrainMonitor.register(dependencies.monitor)
        notificationDelegate = NotificationDelegate(
            onOpen: { url in Task { @MainActor in dependencies.pendingOpenURL = url } },
            onMute: { id in Task { @MainActor in dependencies.alerts.mute(id) } }
        )
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

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
                .environment(dependencies.activities)
                .environment(dependencies.alerts)
                .environment(dependencies.monitor)
                .task { await dependencies.start() }
        }
        .modelContainer(dependencies.modelContainer)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                dependencies.activities.restore()
                dependencies.monitor.startForeground()
                Task { await dependencies.alerts.refreshAuthorization() }
            case .background:
                dependencies.monitor.stopForeground()
                dependencies.monitor.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }
}
