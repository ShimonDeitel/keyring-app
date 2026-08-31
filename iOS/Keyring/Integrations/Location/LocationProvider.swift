import Foundation
import CoreLocation
import Observation

enum LocationProviderError: Error {
    case denied
    case unavailable
}

/// Wraps CoreLocation for the "confirm current location" action. Never used
/// for background tracking, and permission is only requested the first time
/// a Pro user actually taps the confirm-location action — never at launch.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var authorizationStatus: CLAuthorizationStatus

    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// Reverse-geocoded name + the raw coordinate for a fresh fix, or throws
    /// if the user denies access.
    func confirmCurrentLocation() async throws -> (name: String, coordinate: CLLocationCoordinate2D) {
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationProviderError.denied
        }
        let location = try await requestLocation()
        let name = await reverseGeocodedName(for: location) ?? "Current location"
        return (name, location.coordinate)
    }

    private func requestAuthorization() async {
        await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func reverseGeocodedName(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return [placemark.name, placemark.locality].compactMap { $0 }.joined(separator: ", ")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: error)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            self.authContinuation?.resume()
            self.authContinuation = nil
        }
    }
}
