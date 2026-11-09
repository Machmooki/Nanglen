import Foundation

nonisolated enum VisitPurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case study, work, meeting, relax, other
}

nonisolated enum ReviewStatus: String, Codable, Hashable, Sendable {
    case published, hidden, removed
}

nonisolated enum ReviewSort: String, CaseIterable, Hashable, Sendable {
    case relevant, recent
}

/// Controlled experience-tag taxonomy (mirrors `public.review_tags`).
/// Tags are community impressions — never presented as guaranteed venue facts.
nonisolated struct ReviewTag: Hashable, Sendable, Codable, Identifiable {
    var slug: String
    var labelTH: String
    var labelEN: String
    var group: String
    var sortOrder: Int

    var id: String { slug }

    /// Built-in copy of the reference data so the UI works before/without the network.
    static let catalog: [ReviewTag] = [
        ReviewTag(slug: "study_friendly", labelTH: "เหมาะกับอ่านหนังสือ", labelEN: "Study-friendly", group: "activity", sortOrder: 10),
        ReviewTag(slug: "work_friendly", labelTH: "เหมาะกับทำงาน", labelEN: "Work-friendly", group: "activity", sortOrder: 20),
        ReviewTag(slug: "quiet", labelTH: "เงียบสงบ", labelEN: "Quiet", group: "environment", sortOrder: 30),
        ReviewTag(slug: "lively", labelTH: "บรรยากาศคึกคัก", labelEN: "Lively atmosphere", group: "environment", sortOrder: 40),
        ReviewTag(slug: "good_lighting", labelTH: "แสงดี", labelEN: "Good lighting", group: "environment", sortOrder: 50),
        ReviewTag(slug: "good_wifi", labelTH: "Wi-Fi ดี", labelEN: "Good Wi-Fi", group: "amenity", sortOrder: 60),
        ReviewTag(slug: "power_outlets", labelTH: "มีปลั๊กไฟ", labelEN: "Power outlets", group: "amenity", sortOrder: 70),
        ReviewTag(slug: "comfortable_seating", labelTH: "ที่นั่งสบาย", labelEN: "Comfortable seating", group: "amenity", sortOrder: 80),
        ReviewTag(slug: "good_value", labelTH: "คุ้มค่า", labelEN: "Good value", group: "value", sortOrder: 90),
        ReviewTag(slug: "expensive", labelTH: "ราคาค่อนข้างสูง", labelEN: "Expensive", group: "value", sortOrder: 100),
    ]

    static func named(_ slug: String) -> ReviewTag? { catalog.first { $0.slug == slug } }
}

/// A published review as shown to everyone (current revision only).
nonisolated struct PublishedReview: Identifiable, Hashable, Sendable {
    var id: UUID
    var authorName: String
    var rating: Int
    var purpose: VisitPurpose?
    var body: String?
    var tags: [String]
    var photoPaths: [String]
    var revisionNumber: Int
    var updatedAt: Date
    var isMine: Bool
    /// Every review published by the real backend is tied to a consumed visit verification.
    /// Only seeded demo data can be false.
    var isVerifiedVisit = true
}

nonisolated struct ReviewPage: Hashable, Sendable {
    var reviews: [PublishedReview]
    var hasMore: Bool
}

/// The caller's own current review for a venue (may be hidden by moderation).
nonisolated struct MyReview: Hashable, Sendable {
    var reviewID: UUID
    var status: ReviewStatus
    var rating: Int
    var purpose: VisitPurpose?
    var body: String?
    var tags: [String]
    var revisionNumber: Int
    var updatedAt: Date
}

/// What the user filled in on the composer. Validated by `ReviewValidator` and again by the server.
nonisolated struct ReviewDraft: Hashable, Sendable, Codable {
    var venueID: UUID
    var rating: Int?
    var purpose: VisitPurpose?
    var tags: [String] = []
    var body: String = ""
    /// Stable per draft so retries never create duplicate revisions.
    var idempotencyKey = UUID()
    var updatedAt = Date()
}

nonisolated struct ReviewSubmission: Hashable, Sendable {
    var venueID: UUID
    var verificationID: UUID
    var rating: Int
    var purpose: VisitPurpose?
    var tags: [String]
    var body: String?
    var idempotencyKey: UUID
}

nonisolated struct ReviewSubmissionResult: Hashable, Sendable {
    var reviewID: UUID
    var revisionID: UUID
    var revisionNumber: Int
    var status: ReviewStatus
    var replayed: Bool
}

nonisolated enum FlagReason: String, CaseIterable, Hashable, Sendable {
    case spam
    case offensive
    case notARealVisit = "not_a_real_visit"
    case wrongVenue = "wrong_venue"
    case privacy
    case other
}

/// Image prepared for upload (already re-encoded and size-checked on device).
nonisolated struct PhotoUpload: Hashable, Sendable {
    var data: Data
    var mimeType: String
    var fileExtension: String
    var width: Int
    var height: Int
}
