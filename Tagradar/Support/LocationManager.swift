import CoreLocation
import Foundation
import Observation

/// Thin wrapper around CoreLocation authorization for the "my location" button.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus
    /// Set while a permission prompt is pending so the map can center once access is granted.
    var pendingCenter = false

    private let manager = CLLocationManager()
    /// Keyed so a cancelled caller can drop its own request without disturbing the others waiting
    /// on the same fix.
    private var pendingRequests: [UUID: CheckedContinuation<CLLocation?, Never>] = [:]

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    /// One-shot fix, or nil when unavailable. Requires authorization.
    ///
    /// Honours cancellation: CoreLocation is free to stay silent — indoors, or with location
    /// services wedged — and without this a cancelled caller would stay suspended for as long as
    /// it takes the next delegate callback to arrive, if one ever does.
    func currentLocation() async -> CLLocation? {
        guard isAuthorized, !Task.isCancelled else { return nil }
        if let recent = manager.location, Date.now.timeIntervalSince(recent.timestamp) < 60 {
            return recent
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingRequests[id] = continuation
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor in self.cancelPending(id) }
        }
    }

    private func cancelPending(_ id: UUID) {
        pendingRequests.removeValue(forKey: id)?.resume(returning: nil)
    }

    private func resolvePending(with location: CLLocation?) {
        let waiting = pendingRequests.values
        pendingRequests.removeAll()
        for continuation in waiting {
            continuation.resume(returning: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            resolvePending(with: latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in
            resolvePending(with: nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            status = newStatus
        }
    }
}
