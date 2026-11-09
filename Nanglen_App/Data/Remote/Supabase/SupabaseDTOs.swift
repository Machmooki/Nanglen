import Foundation

// Wire formats for the Supabase RPCs (snake_case, exactly as the SQL functions name them).
// Dates arrive as ISO-8601 strings and are parsed explicitly to stay decoder-agnostic.

// MARK: - Params

nonisolated struct SearchParams: Encodable, Sendable {
    var p_query: String?
    var p_latitude: Double?
    var p_longitude: Double?
    var p_radius_m: Double
    var p_category: String?
    var p_min_rating: Double?
    var p_sort: String
    var p_limit: Int
    var p_offset: Int
}

nonisolated struct CardsParams: Encodable, Sendable {
    var p_ids: [UUID]
    var p_latitude: Double?
    var p_longitude: Double?
}

nonisolated struct ProviderParams: Encodable, Sendable {
    var p_provider: String
    var p_external_ids: [String]
}

nonisolated struct ReviewListParams: Encodable, Sendable {
    var p_venue_id: UUID
    var p_sort: String
    var p_limit: Int
    var p_offset: Int
}

nonisolated struct EventParams: Encodable, Sendable {
    var p_event_name: String
    var p_venue_id: UUID?
}

nonisolated struct VerifyParams: Encodable, Sendable {
    var p_challenge_id: UUID
    var p_latitude: Double
    var p_longitude: Double
    var p_horizontal_accuracy: Double
    var p_location_timestamp: String
}

nonisolated struct SubmitReviewParams: Encodable, Sendable {
    var p_venue_id: UUID
    var p_verification_id: UUID
    var p_rating: Int
    var p_visit_purpose: String?
    var p_tags: [String]
    var p_body: String?
    var p_idempotency_key: UUID
}

nonisolated struct MediaParams: Encodable, Sendable {
    var p_revision_id: UUID?
    var p_submission_id: UUID?
    var p_storage_path: String
    var p_mime_type: String
    var p_byte_size: Int
    var p_width: Int
    var p_height: Int
}

nonisolated struct FlagParams: Encodable, Sendable {
    var p_review_id: UUID
    var p_reason: String
    var p_note: String?
}

nonisolated struct SubmissionParams: Encodable, Sendable {
    var p_client_request_id: UUID
    var p_name: String
    var p_category: String
    var p_formatted_address: String
    var p_latitude: Double
    var p_longitude: Double
    var p_provider: String?
    var p_external_place_id: String?
    var p_description: String
    var p_website_url: String
    var p_phone_number: String
    var p_submitter_note: String
}

nonisolated struct ResubmitParams: Encodable, Sendable {
    var p_submission_id: UUID
    var p_name: String
    var p_category: String
    var p_formatted_address: String
    var p_latitude: Double
    var p_longitude: Double
    var p_description: String
    var p_website_url: String
    var p_phone_number: String
    var p_submitter_note: String
}

nonisolated struct ClaimParams: Encodable, Sendable {
    var p_client_request_id: UUID
    var p_venue_id: UUID
    var p_business_name: String
    var p_claimant_role: String
    var p_contact_note: String
    var p_evidence_note: String
}

nonisolated struct ApproveParams: Encodable, Sendable {
    var p_submission_id: UUID
    var p_note: String?
    var p_force: Bool
}

nonisolated struct ReasonParams: Encodable, Sendable {
    var p_submission_id: UUID
    var p_reason: String
}

nonisolated struct DuplicateParams: Encodable, Sendable {
    var p_submission_id: UUID
    var p_venue_id: UUID
    var p_reason: String
}

nonisolated struct ClaimDecisionParams: Encodable, Sendable {
    var p_claim_id: UUID
    var p_approve: Bool
    var p_reason: String?
}

nonisolated struct ModerateParams: Encodable, Sendable {
    var p_review_id: UUID
    var p_status: String
    var p_reason: String
}

// MARK: - Results

nonisolated struct VenueCardDTO: Decodable, Sendable {
    var id: UUID
    var name: String
    var category: String
    var formatted_address: String?
    var latitude: Double
    var longitude: Double
    var status: String
    var review_count: Int?
    var average_rating: Double?
    var top_tags: [String]?
    var cover_path: String?
    var distance_m: Double?
    var rank_score: Double?

    var model: VenueSummary {
        VenueSummary(
            id: id, name: name, category: VenueCategory(rawValue: category) ?? .other, address: formatted_address,
            coordinate: GeoPoint(latitude: latitude, longitude: longitude), status: VenueStatus(rawValue: status) ?? .active,
            rating: RatingSummary(reviewCount: review_count ?? 0, average: (review_count ?? 0) > 0 ? average_rating : nil),
            topTags: top_tags ?? [], coverPath: cover_path, distanceMeters: distance_m, rankScore: rank_score)
    }
}

nonisolated struct ProviderMatchDTO: Decodable, Sendable {
    var external_place_id: String
    var venue_id: UUID
}

nonisolated struct MyReviewDTO: Decodable, Sendable {
    var review_id: UUID
    var status: String
    var rating: Int
    var visit_purpose: String?
    var body: String?
    var revision_number: Int
    var updated_at: String
    var tags: [String]?
}

nonisolated struct VenueDetailDTO: Decodable, Sendable {
    var id: UUID
    var name: String
    var description: String?
    var category: String
    var formatted_address: String?
    var latitude: Double
    var longitude: Double
    var status: String
    var website_url: String?
    var phone_number: String?
    var details_source: String?
    var apple_maps_id: String?
    var review_count: Int
    var average_rating: Double?
    var rating_distribution: [Int]?
    var last_review_at: String?
    var tags: [TagCount]
    var photo_paths: [String]
    var is_favorite: Bool
    var is_managed_by_me: Bool
    var my_review: MyReviewDTO?

    var model: VenueDetail {
        let rating = RatingSummary(reviewCount: review_count, average: review_count > 0 ? average_rating : nil)
        let summary = VenueSummary(
            id: id, name: name, category: VenueCategory(rawValue: category) ?? .other, address: formatted_address,
            coordinate: GeoPoint(latitude: latitude, longitude: longitude), status: VenueStatus(rawValue: status) ?? .active,
            rating: rating, topTags: Array(tags.prefix(3).map(\.slug)), coverPath: photo_paths.first,
            distanceMeters: nil, rankScore: nil)
        let mine = my_review.map { dto in
            MyReview(reviewID: dto.review_id, status: ReviewStatus(rawValue: dto.status) ?? .published, rating: dto.rating,
                     purpose: dto.visit_purpose.flatMap(VisitPurpose.init(rawValue:)), body: dto.body, tags: dto.tags ?? [],
                     revisionNumber: dto.revision_number, updatedAt: SupabaseBackend.date(dto.updated_at) ?? Date())
        }
        return VenueDetail(
            summary: summary, description: description, websiteURL: website_url.flatMap(URL.init(string:)),
            phoneNumber: phone_number, detailsSource: details_source, appleMapsID: apple_maps_id,
            ratingDistribution: rating_distribution, lastReviewAt: SupabaseBackend.date(last_review_at),
            tagCounts: tags, photoPaths: photo_paths, isFavorite: is_favorite, isManagedByMe: is_managed_by_me, myReview: mine)
    }
}

nonisolated struct ReviewDTO: Decodable, Sendable {
    var review_id: UUID
    var author_name: String
    var rating: Int
    var visit_purpose: String?
    var body: String?
    var tags: [String]?
    var photo_paths: [String]?
    var revision_number: Int
    var updated_at: String
    var is_mine: Bool

    var model: PublishedReview {
        PublishedReview(id: review_id, authorName: author_name, rating: rating,
                        purpose: visit_purpose.flatMap(VisitPurpose.init(rawValue:)), body: body, tags: tags ?? [],
                        photoPaths: photo_paths ?? [], revisionNumber: revision_number,
                        updatedAt: SupabaseBackend.date(updated_at) ?? Date(), isMine: is_mine)
    }
}

nonisolated struct FavoriteDTO: Decodable, Sendable {
    var venue_id: UUID
}

nonisolated struct PublicConfigDTO: Decodable, Sendable {
    var visit_radius_m: Double
    var visit_max_accuracy_m: Double
    var visit_max_location_age_s: Double
}

nonisolated struct ChallengeDTO: Decodable, Sendable {
    var challenge_id: UUID
    var issued_at: String
    var expires_at: String
    var radius_m: Double
    var max_accuracy_m: Double
    var max_location_age_s: Double
}

nonisolated struct VerificationDTO: Decodable, Sendable {
    var verification_id: UUID?
    var status: String
    var distance_bucket: String?
    var expires_at: String?
}

nonisolated struct SubmitReviewDTO: Decodable, Sendable {
    var review_id: UUID
    var revision_id: UUID
    var revision_number: Int
    var status: String
    var replayed: Bool?
}

nonisolated struct DuplicateCandidateDTO: Decodable, Sendable {
    var venue_id: UUID
    var name: String
    var formatted_address: String?
    var distance_m: Double
    var name_similarity: Double
    var provider_match: Bool

    var model: DuplicateCandidate {
        DuplicateCandidate(venueID: venue_id, name: name, address: formatted_address, distanceMeters: distance_m,
                           nameSimilarity: name_similarity, providerMatch: provider_match)
    }
}

nonisolated struct SubmissionReceiptDTO: Decodable, Sendable {
    var submission_id: UUID?
    var status: String
    var existing_venue_id: UUID?
    var duplicate_candidates: [DuplicateCandidateDTO]?
}

nonisolated struct SubmissionDTO: Decodable, Sendable {
    var id: UUID
    var name: String
    var category: String
    var formatted_address: String?
    var latitude: Double
    var longitude: Double
    var description: String?
    var website_url: String?
    var phone_number: String?
    var submitter_note: String?
    var status: String
    var revision: Int
    var decision_reason: String?
    var duplicate_of_venue_id: UUID?
    var approved_venue_id: UUID?
    var submitted_at: String?
    var updated_at: String

    var model: VenueSubmission {
        VenueSubmission(
            id: id, name: name, category: VenueCategory(rawValue: category) ?? .other, address: formatted_address,
            coordinate: GeoPoint(latitude: latitude, longitude: longitude), description: description,
            websiteURL: website_url, phoneNumber: phone_number, note: submitter_note,
            status: SubmissionStatus(rawValue: status) ?? .pendingReview, revision: revision, decisionReason: decision_reason,
            duplicateOfVenueID: duplicate_of_venue_id, approvedVenueID: approved_venue_id,
            submittedAt: SupabaseBackend.date(submitted_at), updatedAt: SupabaseBackend.date(updated_at) ?? Date())
    }
}

nonisolated struct ClaimReceiptDTO: Decodable, Sendable {
    var claim_id: UUID
    var status: String
}

nonisolated struct ClaimDTO: Decodable, Sendable {
    var id: UUID
    var venue_id: UUID
    var business_name: String
    var claimant_role: String
    var status: String
    var decision_reason: String?
    var created_at: String

    var model: VenueClaim {
        VenueClaim(id: id, venueID: venue_id, venueName: nil, businessName: business_name,
                   role: ClaimantRole(rawValue: claimant_role) ?? .owner, status: ClaimStatus(rawValue: status) ?? .pendingReview,
                   decisionReason: decision_reason, createdAt: SupabaseBackend.date(created_at) ?? Date())
    }
}

nonisolated struct MembershipDTO: Decodable, Sendable {
    var business_id: UUID
    var business_name: String
    var role: String
    var venue_ids: [UUID]
}

nonisolated struct CapabilitiesDTO: Decodable, Sendable {
    var user_id: UUID
    var is_anonymous: Bool
    var is_registered: Bool
    var is_admin: Bool
    var display_name: String?
    var favorites_count: Int
    var reviews_count: Int
    var open_submissions_count: Int
    var memberships: [MembershipDTO]

    var model: UserCapabilities {
        UserCapabilities(
            userID: user_id, isAnonymous: is_anonymous, isRegistered: is_registered, isAdmin: is_admin,
            displayName: display_name ?? "ผู้ใช้ Nanglen", favoritesCount: favorites_count, reviewsCount: reviews_count,
            openSubmissionsCount: open_submissions_count,
            memberships: memberships.map { BusinessMembership(businessID: $0.business_id, businessName: $0.business_name, role: $0.role, venueIDs: $0.venue_ids) })
    }
}

nonisolated struct AdminSubmissionDTO: Decodable, Sendable {
    var id: UUID
    var name: String
    var category: String
    var formatted_address: String?
    var latitude: Double
    var longitude: Double
    var status: String
    var revision: Int
    var submitted_at: String?
    var submitter_name: String
    var media_count: Int
    var duplicate_candidate_count: Int

    var model: AdminSubmissionRow {
        AdminSubmissionRow(
            id: id, name: name, category: VenueCategory(rawValue: category) ?? .other, address: formatted_address,
            coordinate: GeoPoint(latitude: latitude, longitude: longitude), status: SubmissionStatus(rawValue: status) ?? .pendingReview,
            revision: revision, submittedAt: SupabaseBackend.date(submitted_at), submitterName: submitter_name,
            mediaCount: media_count, duplicateCandidateCount: duplicate_candidate_count)
    }
}

nonisolated struct AdminSubmissionDetailDTO: Decodable, Sendable {
    struct Submitter: Decodable, Sendable {
        var display_name: String
        var total_submissions: Int
        var approved_submissions: Int
    }

    struct Media: Decodable, Sendable {
        var storage_path: String
    }

    struct History: Decodable, Sendable {
        var action: String
        var reason: String?
        var created_at: String
    }

    var id: UUID
    var name: String
    var category: String
    var formatted_address: String?
    var latitude: Double
    var longitude: Double
    var provider: String?
    var external_place_id: String?
    var description: String?
    var website_url: String?
    var phone_number: String?
    var submitter_note: String?
    var status: String
    var revision: Int
    var decision_reason: String?
    var submitted_at: String?
    var created_at: String
    var duplicate_of_venue_id: UUID?
    var approved_venue_id: UUID?
    var submitter: Submitter
    var media: [Media]
    var duplicate_candidates: [DuplicateCandidateDTO]
    var history: [History]

    var model: AdminSubmissionDetail {
        let submission = VenueSubmission(
            id: id, name: name, category: VenueCategory(rawValue: category) ?? .other, address: formatted_address,
            coordinate: GeoPoint(latitude: latitude, longitude: longitude), description: description,
            websiteURL: website_url, phoneNumber: phone_number, note: submitter_note,
            status: SubmissionStatus(rawValue: status) ?? .pendingReview, revision: revision, decisionReason: decision_reason,
            duplicateOfVenueID: duplicate_of_venue_id, approvedVenueID: approved_venue_id,
            submittedAt: SupabaseBackend.date(submitted_at), updatedAt: SupabaseBackend.date(created_at) ?? Date())
        return AdminSubmissionDetail(
            submission: submission, provider: provider, externalPlaceID: external_place_id,
            submitterName: submitter.display_name, submitterTotal: submitter.total_submissions,
            submitterApproved: submitter.approved_submissions, mediaPaths: media.map(\.storage_path),
            duplicates: duplicate_candidates.map(\.model),
            history: history.map { ModerationHistoryItem(action: $0.action, reason: $0.reason, createdAt: SupabaseBackend.date($0.created_at) ?? Date()) })
    }
}

nonisolated struct AdminClaimDTO: Decodable, Sendable {
    var id: UUID
    var venue_id: UUID
    var venue_name: String
    var business_name: String
    var claimant_role: String
    var claimant_name: String
    var contact_note: String?
    var evidence_note: String?
    var created_at: String

    var model: AdminClaimRow {
        AdminClaimRow(id: id, venueID: venue_id, venueName: venue_name, businessName: business_name,
                      role: ClaimantRole(rawValue: claimant_role) ?? .owner, claimantName: claimant_name,
                      contactNote: contact_note, evidenceNote: evidence_note, createdAt: SupabaseBackend.date(created_at) ?? Date())
    }
}

nonisolated struct FlaggedReviewDTO: Decodable, Sendable {
    var review_id: UUID
    var venue_name: String
    var author_name: String
    var rating: Int
    var body: String?
    var review_status: String
    var open_flags: Int
    var reasons: [String]

    var model: AdminFlaggedReview {
        AdminFlaggedReview(id: review_id, venueName: venue_name, authorName: author_name, rating: rating, body: body,
                           status: ReviewStatus(rawValue: review_status) ?? .published, openFlags: open_flags, reasons: reasons)
    }
}
