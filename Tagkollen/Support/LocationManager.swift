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
    private var pendingRequests: [CheckedContinuation<CLLocation?, Never>] = []

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
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        if let recent = manager.location, Date.now.timeIntervalSince(recent.timestamp) < 60 {
            return recent
        }
        return await withCheckedContinuation { continuation in
            pendingRequests.append(continuation)
            manager.requestLocation()
        }
    }

    private func resolvePending(with location: CLLocation?) {
        let waiting = pendingRequests
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
