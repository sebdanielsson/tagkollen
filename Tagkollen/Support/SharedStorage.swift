import Foundation
import os
import SwiftData

/// Files and defaults shared between the app and its widget extension through the App Group.
/// Falls back to the app's own container when the group is unavailable (e.g. unit tests).
enum SharedStorage {
    static let appGroup = "group.se.tagkollen.app"
    static let keychainAccessGroup = "se.tagkollen.app"
    private static let logger = Logger(subsystem: "se.tagkollen.app", category: "SharedStorage")

    /// The App Group container, or Application Support when the group is not provisioned.
    static let containerURL: URL = {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url
        }
        logger.error("App Group \(appGroup, privacy: .public) unavailable; using Application Support")
        return URL.applicationSupportDirectory
    }()

    /// Shared `UserDefaults` for state both the app and the widgets read (followed trains, alert snapshots).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var storeURL: URL {
        containerURL.appending(path: "Tagkollen.store")
    }

    static var stationsCacheURL: URL {
        containerURL.appending(path: "stations-v1.json")
    }

    /// Creates the SwiftData container in the shared location, moving an existing store from the
    /// app's private Application Support folder the first time.
    static func makeModelContainer() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        migrateLegacyFiles()
        let config = ModelConfiguration("Tagkollen", url: storeURL)
        return try ModelContainer(for: FavoriteTrain.self, FavoriteStation.self, configurations: config)
    }

    /// Moves the pre-App-Group store and station cache into the shared container.
    private static func migrateLegacyFiles() {
        let legacyDir = URL.applicationSupportDirectory
        guard legacyDir != containerURL else { return }
        let fm = FileManager.default
        for name in ["Tagkollen.store", "Tagkollen.store-shm", "Tagkollen.store-wal", "stations-v1.json"] {
            let from = legacyDir.appending(path: name)
            let to = containerURL.appending(path: name)
            guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
            do {
                try fm.moveItem(at: from, to: to)
            } catch {
                logger.error("Could not migrate \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
