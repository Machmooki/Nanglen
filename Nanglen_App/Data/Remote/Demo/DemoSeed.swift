import Foundation

/// Fictional demo data mirroring `supabase/seed.sql`. Names are marked "(ตัวอย่าง)";
/// only name/category/location/address are seeded — no invented amenities.
nonisolated enum DemoSeed {
    /// Demo-only phone numbers. In Demo mode the OTP is always `demoOTP`.
    static let demoOTP = "123456"
    /// Linking this number makes the user a Demo Admin (mirrors a server-side admin_users row).
    static let adminPhone = "+66800000000"

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
        SeedVenue(id: "00000000-0000-4000-8000-000000000001", name: "ใบชา คาเฟ่ (ตัวอย่าง)", category: .cafe, address: "สยามสแควร์ ซอย 3 ปทุมวัน กรุงเทพฯ", latitude: 13.7462, longitude: 100.5326, description: "ร้านกาแฟตัวอย่างสำหรับทดสอบระบบ"),
        SeedVenue(id: "00000000-0000-4000-8000-000000000002", name: "ห้องสมุดชุมชนปทุมวัน (ตัวอย่าง)", category: .library, address: "ถนนพระราม 1 ปทุมวัน กรุงเทพฯ", latitude: 13.7440, longitude: 100.5300),
        SeedVenue(id: "00000000-0000-4000-8000-000000000003", name: "Hive Corner Co-working (ตัวอย่าง)", category: .coworking, address: "ถนนพระราม 1 ปทุมวัน กรุงเทพฯ", latitude: 13.7468, longitude: 100.5350),
        SeedVenue(id: "00000000-0000-4000-8000-000000000004", name: "มุมอ่านหนังสือสามย่าน (ตัวอย่าง)", category: .studySpace, address: "สามย่าน ปทุมวัน กรุงเทพฯ", latitude: 13.7330, longitude: 100.5290),
        SeedVenue(id: "00000000-0000-4000-8000-000000000005", name: "Morning Drip Café (ตัวอย่าง)", category: .cafe, address: "ถนนเพลินจิต ปทุมวัน กรุงเทพฯ", latitude: 13.7440, longitude: 100.5390),
        SeedVenue(id: "00000000-0000-4000-8000-000000000006", name: "Studio 24 Workspace (ตัวอย่าง)", category: .coworking, address: "สุขุมวิท 21 วัฒนา กรุงเทพฯ", latitude: 13.7378, longitude: 100.5603),
        SeedVenue(id: "00000000-0000-4000-8000-000000000007", name: "ลานนั่งเล่นริมสวน (ตัวอย่าง)", category: .other, address: "ถนนราชดำริ ปทุมวัน กรุงเทพฯ", latitude: 13.7305, longitude: 100.5415),
        SeedVenue(id: "00000000-0000-4000-8000-000000000008", name: "Paper & Bean (ตัวอย่าง)", category: .cafe, address: "บรรทัดทอง ปทุมวัน กรุงเทพฯ", latitude: 13.7420, longitude: 100.5235),
    ]

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
        SeedReview(venueIndex: 0, author: "ผู้ใช้ตัวอย่าง A", rating: 5, purpose: .study, tags: ["quiet", "study_friendly", "power_outlets"], body: "ข้อความรีวิวตัวอย่างสำหรับโหมดสาธิต"),
        SeedReview(venueIndex: 0, author: "ผู้ใช้ตัวอย่าง B", rating: 4, purpose: .work, tags: ["good_wifi", "work_friendly"], body: nil),
        SeedReview(venueIndex: 0, author: "ผู้ใช้ตัวอย่าง C", rating: 4, purpose: .relax, tags: ["comfortable_seating"], body: "รีวิวตัวอย่าง: ที่นั่งสบาย"),
        SeedReview(venueIndex: 1, author: "ผู้ใช้ตัวอย่าง A", rating: 5, purpose: .study, tags: ["quiet", "study_friendly"], body: nil),
        SeedReview(venueIndex: 2, author: "ผู้ใช้ตัวอย่าง B", rating: 4, purpose: .work, tags: ["good_wifi", "power_outlets", "work_friendly"], body: "รีวิวตัวอย่างสำหรับ co-working"),
        SeedReview(venueIndex: 4, author: "ผู้ใช้ตัวอย่าง C", rating: 5, purpose: .meeting, tags: ["lively"], body: nil),
        SeedReview(venueIndex: 7, author: "ผู้ใช้ตัวอย่าง A", rating: 3, purpose: .relax, tags: ["expensive"], body: "รีวิวตัวอย่าง"),
    ]
}
