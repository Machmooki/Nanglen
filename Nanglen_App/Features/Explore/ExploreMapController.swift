import MapKit
import UIKit

/// Map annotation backed by an approved venue card.
final class VenueAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    private(set) var item: VenueCardItem

    init(item: VenueCardItem) {
        self.item = item
        coordinate = CLLocationCoordinate2D(latitude: item.venue.coordinate.latitude, longitude: item.venue.coordinate.longitude)
        super.init()
        update(item)
    }

    func update(_ item: VenueCardItem) {
        self.item = item
        title = item.venue.name
        subtitle = [item.venue.category.title, item.venue.rating.displayText].joined(separator: " · ")
        let newCoordinate = CLLocationCoordinate2D(latitude: item.venue.coordinate.latitude, longitude: item.venue.coordinate.longitude)
        if newCoordinate.latitude != coordinate.latitude || newCoordinate.longitude != coordinate.longitude {
            coordinate = newCoordinate
        }
    }
}

/// Marker tinted by brand; venues with reviews get higher display priority.
final class VenueAnnotationView: MKMarkerAnnotationView {
    static let reuseIdentifier = "VenueAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        clusteringIdentifier = "venue"
        let button = UIButton(type: .detailDisclosure)
        button.tintColor = AppColors.primary
        rightCalloutAccessoryView = button
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let venueAnnotation = annotation as? VenueAnnotation else { return }
        let venue = venueAnnotation.item.venue
        glyphImage = UIImage(systemName: venue.category.symbol)
        markerTintColor = venue.rating.hasReviews ? AppColors.primary : AppColors.neutral
        displayPriority = venue.rating.hasReviews ? .defaultHigh : .defaultLow
    }
}

/// Owns the Explore map: annotation diffing, selection and detecting when the
/// user pans/zooms (to offer "search this area").
final class ExploreMapController: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    var onSelect: ((VenueCardItem) -> Void)?
    var onUserMovedMap: ((SearchRegion) -> Void)?

    private weak var mapView: MKMapView?
    private var annotations: [UUID: VenueAnnotation] = [:]
    private var userIsInteracting = false

    init(mapView: MKMapView) {
        self.mapView = mapView
        super.init()
        mapView.delegate = self
        mapView.register(VenueAnnotationView.self, forAnnotationViewWithReuseIdentifier: VenueAnnotationView.reuseIdentifier)
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(userGesture(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(userGesture(_:)))
        [pan, pinch].forEach {
            $0.delegate = self
            mapView.addGestureRecognizer($0)
        }
    }

    var visibleRegion: SearchRegion? {
        mapView.map { SearchRegion($0.region) }
    }

    func setShowsUserLocation(_ shows: Bool) {
        mapView?.showsUserLocation = shows
    }

    func setRegion(_ region: SearchRegion, animated: Bool) {
        mapView?.setRegion(region.mapKitRegion, animated: animated)
    }

    func fitToResults() {
        guard let mapView, !annotations.isEmpty else { return }
        mapView.showAnnotations(Array(annotations.values), animated: true)
    }

    func update(items: [VenueCardItem]) {
        guard let mapView else { return }
        let incoming = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let removed = annotations.filter { incoming[$0.key] == nil }
        mapView.removeAnnotations(Array(removed.values))
        removed.keys.forEach { annotations[$0] = nil }

        var added: [VenueAnnotation] = []
        for (id, item) in incoming {
            if let existing = annotations[id] {
                guard existing.item != item else { continue }
                existing.update(item)
                (mapView.view(for: existing) as? VenueAnnotationView)?.prepareForDisplay()
            } else {
                let annotation = VenueAnnotation(item: item)
                annotations[id] = annotation
                added.append(annotation)
            }
        }
        mapView.addAnnotations(added)
    }

    // MARK: Gestures

    @objc private func userGesture(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began { userIsInteracting = true }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is VenueAnnotation else { return nil }
        return mapView.dequeueReusableAnnotationView(withIdentifier: VenueAnnotationView.reuseIdentifier, for: annotation)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard userIsInteracting else { return }
        userIsInteracting = false
        onUserMovedMap?(SearchRegion(mapView.region))
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let annotation = view.annotation as? VenueAnnotation else { return }
        onSelect?(annotation.item)
    }
}
