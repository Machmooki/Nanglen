import Foundation

/// Fictional demo data mirroring `supabase/seed.sql`. Names are marked "(Demo)";
/// only name/category/location/address are seeded — no invented amenities.
nonisolated enum DemoSeed {
    /// In Demo mode no email is sent; the code is always `demoOTP`.
    static let demoOTP = "123456"
    /// DEBUG builds only: verifying this email makes the user a Demo Admin
    /// (mirrors a server-side `private.admin_users` row). Release builds have no demo admin.
    static let adminEmail = "admin@demo.nanglen.app"

    struct SeedVenue {
        var id: String
        var name: String
        var category: VenueCategory
        var address: String
        var latitude: Double
        var longitude: Double
        var description: String?
    }

    static let venues: [SeedVenue] = [
        SeedVenue(id: "00000000-0000-4000-8000-000000000001", name: "Baicha Café (Demo)", category: .cafe, address: "Siam Square Soi 3, Pathum Wan, Bangkok", latitude: 13.7462, longitude: 100.5326, description: "Sample coffee shop for testing"),
        SeedVenue(id: "00000000-0000-4000-8000-000000000002", name: "Pathum Wan Community Library (Demo)", category: .library, address: "Rama I Road, Pathum Wan, Bangkok", latitude: 13.7440, longitude: 100.5300),
        SeedVenue(id: "00000000-0000-4000-8000-000000000003", name: "Hive Corner Co-working (Demo)", category: .coworking, address: "Rama I Road, Pathum Wan, Bangkok", latitude: 13.7468, longitude: 100.5350),
        SeedVenue(id: "00000000-0000-4000-8000-000000000004", name: "Samyan Reading Corner (Demo)", category: .studySpace, address: "Samyan, Pathum Wan, Bangkok", latitude: 13.7330, longitude: 100.5290),
        SeedVenue(id: "00000000-0000-4000-8000-000000000005", name: "Morning Drip Café (Demo)", category: .cafe, address: "Phloen Chit Road, Pathum Wan, Bangkok", latitude: 13.7440, longitude: 100.5390),
        SeedVenue(id: "00000000-0000-4000-8000-000000000006", name: "Studio 24 Workspace (Demo)", category: .coworking, address: "Sukhumvit 21, Watthana, Bangkok", latitude: 13.7378, longitude: 100.5603),
        SeedVenue(id: "00000000-0000-4000-8000-000000000007", name: "Parkside Lounge (Demo)", category: .other, address: "Ratchadamri Road, Pathum Wan, Bangkok", latitude: 13.7305, longitude: 100.5415),
        SeedVenue(id: "00000000-0000-4000-8000-000000000008", name: "Paper & Bean (Demo)", category: .cafe, address: "Banthat Thong, Pathum Wan, Bangkok", latitude: 13.7420, longitude: 100.5235),
    ]

    // MARK: Demo media

    /// Demo-only photos and 360° panoramas, streamed from Wikimedia Commons (freely licensed; author and
    /// license are on each file's Commons page). They only illustrate the UI — they are not the real venues.
    /// Real venues get media from Supabase Storage (`venue_media`).
    static func commonsURL(_ file: String, width: Int) -> String {
        let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        return "https://commons.wikimedia.org/wiki/Special:FilePath/\(encoded)?width=\(width)"
    }

    /// Venue index → photo URLs (first one is the cover).
    static let photos: [Int: [String]] = [
        0: ["A_time_for_a_cup_of_coffee.jpg", "Cafe_Braeunerhof_Wien_2004.jpg", "Kafae_boran_Chiang_Mai.jpg"],
        1: ["Bangkok_City_Library.jpg"],
        2: ["Central_Embassy.jpg"],
        4: ["Coffeehouse,_coffee_shop,_or_café,_IRAN,_Mashhad_19.jpg", "Kafae_boran_Chiang_Mai.jpg"],
        7: ["Cafe_Braeunerhof_Wien_2004.jpg", "A_time_for_a_cup_of_coffee.jpg"],
    ].mapValues { $0.map { commonsURL($0, width: 1280) } }

    /// Venue index → equirectangular 360° panorama. Venues without one fall back to Apple Look Around.
    static let panoramas: [Int: String] = [
        0: commonsURL("360°_panoramas_Estonian_University_of_Life_Sciences,_research.jpg", width: 3840),
    ]

    private static func index(of venueID: UUID) -> Int? {
        venues.firstIndex { UUID(uuidString: $0.id) == venueID }
    }

    static func photoURLs(for venueID: UUID) -> [String] { index(of: venueID).flatMap { photos[$0] } ?? [] }
    static func panoramaURL(for venueID: UUID) -> String? { index(of: venueID).flatMap { panoramas[$0] } }

    /// Demo reviews written by clearly-labelled demo accounts, so ratings and tags can be seen in Demo mode.
    struct SeedReview {
        var venueIndex: Int
        var author: String
        var rating: Int
        var purpose: VisitPurpose?
        var tags: [String]
        var body: String?
    }

    static let reviews: [SeedReview] = [
        SeedReview(venueIndex: 0, author: "Demo user A", rating: 5, purpose: .study, tags: ["quiet", "study_friendly", "power_outlets"], body: "Sample review text for demo mode"),
        SeedReview(venueIndex: 0, author: "Demo user B", rating: 4, purpose: .work, tags: ["good_wifi", "work_friendly"], body: nil),
        SeedReview(venueIndex: 0, author: "Demo user C", rating: 4, purpose: .relax, tags: ["comfortable_seating"], body: "Sample review: comfy seats"),
        SeedReview(venueIndex: 1, author: "Demo user A", rating: 5, purpose: .study, tags: ["quiet", "study_friendly"], body: nil),
        SeedReview(venueIndex: 2, author: "Demo user B", rating: 4, purpose: .work, tags: ["good_wifi", "power_outlets", "work_friendly"], body: "Sample co-working review"),
        SeedReview(venueIndex: 4, author: "Demo user C", rating: 5, purpose: .meeting, tags: ["lively"], body: nil),
        SeedReview(venueIndex: 7, author: "Demo user A", rating: 3, purpose: .relax, tags: ["expensive"], body: "Sample review"),
    ]
}
