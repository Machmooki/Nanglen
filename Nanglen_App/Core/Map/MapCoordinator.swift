import MapKit
import UIKit

/// MapKit actions that leave the app.
final class MapCoordinator {
    /// Opens the venue in Apple Maps with directions. Uses the Apple Maps place when the venue has an
    /// `apple_maps` provider reference, otherwise a pin at the canonical coordinate.
    func openInAppleMaps(_ venue: VenueSummary, appleMapsID: String? = nil) async {
        let item = await resolveMapItem(for: venue, appleMapsID: appleMapsID)
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    private func resolveMapItem(for venue: VenueSummary, appleMapsID: String?) async -> MKMapItem {
        if let appleMapsID, let identifier = MKMapItem.Identifier(rawValue: appleMapsID),
           let item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem {
            return item
        }
        let location = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
        let address = venue.address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) }
        let item = MKMapItem(location: location, address: address)
        item.name = venue.name
        return item
    }
}
