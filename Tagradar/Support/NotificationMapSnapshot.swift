import CoreLocation
import MapKit
import UIKit

/// Renders a small map image of a train's position for use as a notification attachment.
enum NotificationMapSnapshot {
    static func render(coordinate: CLLocationCoordinate2D, timeout: TimeInterval = 4) async -> URL? {
        // MapKit's snapshotter and its result are not Sendable, so the whole job runs inside one child
        // task and only the file URL comes out. A second task supplies the timeout.
        await withTaskGroup(of: URL?.self) { group in
            group.addTask { await snapshotFile(coordinate: coordinate) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first: URL? = if let result = await group.next() {
                result
            } else {
                nil
            }
            group.cancelAll()
            return first
        }
    }

    private static func snapshotFile(coordinate: CLLocationCoordinate2D) async -> URL? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 12000, longitudinalMeters: 24000)
        options.size = CGSize(width: 600, height: 300)
        options.scale = 2
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }
        let image = draw(marker: snapshot.point(for: coordinate), on: snapshot.image)
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "train-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func draw(marker point: CGPoint, on image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(at: .zero)
            let radius: CGFloat = 16
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: rect.insetBy(dx: -3, dy: -3))
            UIColor.systemBlue.setFill()
            context.cgContext.fillEllipse(in: rect)
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            if let symbol = UIImage(systemName: "train.side.front.car", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let size = symbol.size
                symbol.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
            }
        }
    }
}
