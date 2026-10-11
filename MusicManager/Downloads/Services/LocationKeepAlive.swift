import CoreLocation
import Foundation

@MainActor
final class LocationKeepAlive: NSObject {
    static let shared = LocationKeepAlive()

    private let manager = CLLocationManager()
    private var isRunning = false

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "locationKeepAliveEnabled")
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    func requestPermissionIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard isEnabled, !isRunning else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        default:
            Logger.shared.log("[Location] Location access is not allowed; keep-alive skipped")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        Logger.shared.log("[Location] Keep-alive stopped")
    }

    private func beginUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isRunning = true
        Logger.shared.log("[Location] Keep-alive started")
    }
}

extension LocationKeepAlive: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard LocationKeepAlive.shared.isEnabled, PictureInPictureKeepAlive.shared.isEngaged, !PictureInPictureKeepAlive.shared.isPictureInPictureEnabled else { return }
            LocationKeepAlive.shared.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.shared.log("[Location] Update failed: \(error.localizedDescription)")
    }
}
