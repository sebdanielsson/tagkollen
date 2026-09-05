import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Receives the background `URLSession` wake-up that keeps Live Activities fresh; SwiftUI has no hook for it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    var onBackgroundSessionEvents: ((String, @escaping () -> Void) -> Void)?

    func application(
        _: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void
    ) {
        onBackgroundSessionEvents?(identifier, completionHandler)
    }
}

@main
struct TagkollenApp: App {
    @State private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let notificationDelegate: NotificationDelegate

    init() {
        let dependencies = AppDependencies()
        _dependencies = State(initialValue: dependencies)
        notificationDelegate = NotificationDelegate(
            onOpen: { url in Task { @MainActor in dependencies.pendingOpenURL = url } },
            onMute: { id in Task { @MainActor in dependencies.alerts.mute(id) } }
        )
        TrainMonitor.register(dependencies.monitor)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        appDelegate.onBackgroundSessionEvents = { identifier, completion in
            guard identifier == ActivityBackgroundRefresher.sessionIdentifier else { return completion() }
            dependencies.activityRefresher.handleEvents(completion: completion)
        }
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
                dependencies.activityRefresher.cancelAll()
                dependencies.monitor.startForeground()
                Task { await dependencies.alerts.refreshAuthorization() }
            case .inactive:
                // Still counts as foreground for URLSession, so polls scheduled here are not discretionary.
                dependencies.activityRefresher.prepareForBackground()
            case .background:
                dependencies.monitor.stopForeground()
                dependencies.monitor.scheduleBackgroundRefresh()
                dependencies.activityRefresher.ensureScheduled()
            @unknown default:
                break
            }
        }
    }
}
