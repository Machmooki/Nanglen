import Foundation
import Supabase

/// Reads `Supabase.plist` (URL + anon/publishable key) from the app bundle, or the
/// `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment variables. The anon key is public by design;
/// the service-role key must never be placed in the app.
nonisolated struct SupabaseConfiguration: Sendable {
    var url: URL
    var anonKey: String

    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> SupabaseConfiguration? {
        if let raw = environment["SUPABASE_URL"], let url = URL(string: raw), let key = environment["SUPABASE_ANON_KEY"], !key.isEmpty {
            return SupabaseConfiguration(url: url, anonKey: key)
        }
        guard let fileURL = bundle.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rawURL = plist["SUPABASE_URL"] as? String, let url = URL(string: rawURL), url.host != nil,
              let key = plist["SUPABASE_ANON_KEY"] as? String, !key.isEmpty, !key.hasPrefix("YOUR_")
        else { return nil }
        return SupabaseConfiguration(url: url, anonKey: key)
    }
}

/// Production backend: Supabase Auth (anonymous Guest → phone-linked Registered), PostgREST RPCs
/// guarded by RLS and SECURITY DEFINER functions, and private Storage buckets.
final class SupabaseBackend: NanglenBackend {
    let mode: BackendMode
    private let client: SupabaseClient
    private let signedURLLifetime = 3_600

    init(configuration: SupabaseConfiguration) {
        mode = .supabase(host: configuration.url.host ?? "supabase")
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.anonKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    // MARK: Helpers

    private func rpc<T: Decodable & Sendable>(_ function: String, _ params: some Encodable & Sendable) async throws -> T {
        do {
            return try await client.rpc(function, params: params).execute().value
        } catch {
            throw Self.map(error)
        }
    }

    private func rpc<T: Decodable & Sendable>(_ function: String) async throws -> T {
        do {
            return try await client.rpc(function).execute().value
        } catch {
            throw Self.map(error)
        }
    }

    private func rpcVoid(_ function: String, _ params: some Encodable & Sendable) async throws {
        do {
            try await client.rpc(function, params: params).execute()
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: Error) -> Error {
        if let error = error as? BackendError { return error }
        if let error = error as? PostgrestError { return BackendError.fromServerMessage(error.message) }
        if let error = error as? AuthError {
            if case let .api(message, code, _, _) = error {
                if code == .phoneExists || code == .identityAlreadyExists { return BackendError.phoneAlreadyInUse }
                if code == .otpExpired || message.localizedCaseInsensitiveContains("token") { return BackendError.invalidOTP }
                return BackendError.server(message)
            }
            if case .sessionMissing = error { return BackendError.notAuthenticated }
            return BackendError.server(error.localizedDescription)
        }
        if error is URLError { return BackendError.network }
        return error
    }

    nonisolated(unsafe) private static let dateParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = dateParser.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: raw)
    }

    // MARK: AuthRemote

    func ensureSession() async throws {
        do {
            _ = try await client.auth.session
        } catch {
            do {
                try await client.auth.signInAnonymously()
            } catch {
                throw Self.map(error)
            }
        }
    }

    func capabilities() async throws -> UserCapabilities {
        let dto: CapabilitiesDTO = try await rpc("get_my_capabilities")
        return dto.model
    }

    func requestPhoneLink(phoneE164: String) async throws {
        do {
            // For an anonymous user this links a phone identity to the SAME user id after OTP verification.
            try await client.auth.update(user: UserAttributes(phone: phoneE164))
        } catch {
            throw Self.map(error)
        }
    }

    func confirmPhoneLink(phoneE164: String, code: String) async throws {
        do {
            try await client.auth.verifyOTP(phone: phoneE164, token: code, type: .phoneChange)
            _ = try await client.auth.refreshSession()
        } catch {
            throw Self.map(error)
        }
    }

    func updateDisplayName(_ name: String) async throws {
        try await rpcVoid("update_my_display_name", ["p_display_name": name])
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw Self.map(error)
        }
        try await ensureSession()
    }

    // MARK: VenueRemote

    func searchVenues(_ query: VenueSearchQuery) async throws -> VenueSearchPage {
        let params = SearchParams(
            p_query: query.trimmedText.isEmpty ? nil : query.trimmedText,
            p_latitude: query.origin?.latitude, p_longitude: query.origin?.longitude,
            p_radius_m: query.radiusMeters, p_category: query.category?.rawValue,
            p_min_rating: query.filter.minimumRating.value, p_sort: query.filter.sort.rawValue,
            p_limit: query.limit + 1, p_offset: query.offset)
        let rows: [VenueCardDTO] = try await rpc("search_venues", params)
        return VenueSearchPage(venues: rows.prefix(query.limit).map(\.model), hasMore: rows.count > query.limit)
    }

    func venueCards(ids: [UUID], origin: GeoPoint?) async throws -> [VenueSummary] {
        guard !ids.isEmpty else { return [] }
        var result: [VenueSummary] = []
        for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
            let rows: [VenueCardDTO] = try await rpc("get_venue_cards", CardsParams(p_ids: chunk, p_latitude: origin?.latitude, p_longitude: origin?.longitude))
            result += rows.map(\.model)
        }
        return result
    }

    func venueDetail(id: UUID) async throws -> VenueDetail {
        let dto: VenueDetailDTO = try await rpc("get_venue", ["p_venue_id": id])
        return dto.model
    }

    func matchProviderRefs(provider: String, externalIDs: [String]) async throws -> [String: UUID] {
        guard !externalIDs.isEmpty else { return [:] }
        let rows: [ProviderMatchDTO] = try await rpc("match_provider_refs", ProviderParams(p_provider: provider, p_external_ids: Array(externalIDs.prefix(100))))
        return Dictionary(rows.map { ($0.external_place_id, $0.venue_id) }, uniquingKeysWith: { first, _ in first })
    }

    func reviews(venueID: UUID, sort: ReviewSort, limit: Int, offset: Int) async throws -> ReviewPage {
        let rows: [ReviewDTO] = try await rpc("list_venue_reviews", ReviewListParams(p_venue_id: venueID, p_sort: sort.rawValue, p_limit: limit + 1, p_offset: offset))
        return ReviewPage(reviews: rows.prefix(limit).map(\.model), hasMore: rows.count > limit)
    }

    func signedMediaURLs(paths: [String], bucket: MediaBucket) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        do {
            let results = try await client.storage.from(bucket.rawValue).createSignedURLs(paths: paths, expiresIn: signedURLLifetime)
            var urls: [String: URL] = [:]
            for result in results {
                if case let .success(path, url) = result { urls[path] = url }
            }
            return urls
        } catch {
            throw Self.map(error)
        }
    }

    func logEvent(_ name: String, venueID: UUID?) async {
        try? await rpcVoid("log_event", EventParams(p_event_name: name, p_venue_id: venueID))
    }

    // MARK: FavoriteRemote

    func favoriteVenueIDs() async throws -> [UUID] {
        let rows: [FavoriteDTO] = try await rpc("my_favorite_venue_ids")
        return rows.map(\.venue_id)
    }

    func setFavorite(venueID: UUID, isFavorite: Bool) async throws {
        do {
            if isFavorite {
                // user_id defaults to auth.uid() server-side; RLS rejects anything else.
                try await client.from("favorites").upsert(["venue_id": venueID], onConflict: "user_id,venue_id", ignoreDuplicates: true).execute()
            } else {
                try await client.from("favorites").delete().eq("venue_id", value: venueID).execute()
            }
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: ReviewRemote

    func verificationPolicy() async throws -> VerificationPolicy {
        let dto: PublicConfigDTO = try await rpc("get_public_config")
        return VerificationPolicy(radiusMeters: dto.visit_radius_m, maxHorizontalAccuracy: dto.visit_max_accuracy_m, maxLocationAge: dto.visit_max_location_age_s)
    }

    func issueVisitChallenge(venueID: UUID) async throws -> VisitChallenge {
        let dto: ChallengeDTO = try await rpc("issue_visit_challenge", ["p_venue_id": venueID])
        return VisitChallenge(
            id: dto.challenge_id, venueID: venueID,
            issuedAt: Self.date(dto.issued_at) ?? Date(), expiresAt: Self.date(dto.expires_at) ?? Date(),
            policy: VerificationPolicy(radiusMeters: dto.radius_m, maxHorizontalAccuracy: dto.max_accuracy_m, maxLocationAge: dto.max_location_age_s))
    }

    func verifyVisit(challengeID: UUID, reading: LocationReading) async throws -> VisitVerificationResult {
        let params = VerifyParams(
            p_challenge_id: challengeID, p_latitude: reading.point.latitude, p_longitude: reading.point.longitude,
            p_horizontal_accuracy: reading.horizontalAccuracy,
            p_location_timestamp: Self.dateParser.string(from: reading.timestamp))
        let dto: VerificationDTO = try await rpc("verify_visit", params)
        return VisitVerificationResult(status: VisitVerificationStatus(rawValue: dto.status) ?? .invalid,
                                       verificationID: dto.verification_id, expiresAt: Self.date(dto.expires_at),
                                       distanceBucket: dto.distance_bucket)
    }

    func submitReview(_ submission: ReviewSubmission) async throws -> ReviewSubmissionResult {
        let params = SubmitReviewParams(
            p_venue_id: submission.venueID, p_verification_id: submission.verificationID, p_rating: submission.rating,
            p_visit_purpose: submission.purpose?.rawValue, p_tags: submission.tags, p_body: submission.body,
            p_idempotency_key: submission.idempotencyKey)
        let dto: SubmitReviewDTO = try await rpc("submit_review", params)
        return ReviewSubmissionResult(reviewID: dto.review_id, revisionID: dto.revision_id, revisionNumber: dto.revision_number,
                                      status: ReviewStatus(rawValue: dto.status) ?? .published, replayed: dto.replayed ?? false)
    }

    func uploadReviewPhoto(revisionID: UUID, photo: PhotoUpload) async throws {
        let path = try await uploadPhoto(photo, parent: revisionID, bucket: .review)
        try await rpcVoid("attach_review_media", MediaParams(p_revision_id: revisionID, p_submission_id: nil, p_storage_path: path,
                                                             p_mime_type: photo.mimeType, p_byte_size: photo.data.count,
                                                             p_width: photo.width, p_height: photo.height))
    }

    func flagReview(id: UUID, reason: FlagReason, note: String?) async throws {
        try await rpcVoid("flag_review", FlagParams(p_review_id: id, p_reason: reason.rawValue, p_note: note))
    }

    /// Uploads to '<uid>/<parent>/<uuid>.<ext>' — the only shape Storage RLS and attach RPCs accept.
    private func uploadPhoto(_ photo: PhotoUpload, parent: UUID, bucket: MediaBucket) async throws -> String {
        do {
            let uid = try await client.auth.session.user.id
            let path = "\(uid.uuidString.lowercased())/\(parent.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(photo.fileExtension)"
            try await client.storage.from(bucket.rawValue).upload(path, data: photo.data, options: FileOptions(contentType: photo.mimeType, upsert: false))
            return path
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: SubmissionRemote

    func createSubmission(_ draft: VenueSubmissionDraft) async throws -> SubmissionReceipt {
        guard let coordinate = draft.coordinate, let category = draft.category else { throw BackendError.invalidInput("invalid_coordinate") }
        let params = SubmissionParams(
            p_client_request_id: draft.clientRequestID, p_name: draft.name, p_category: category.rawValue,
            p_formatted_address: draft.address, p_latitude: coordinate.latitude, p_longitude: coordinate.longitude,
            p_provider: draft.provider, p_external_place_id: draft.externalPlaceID, p_description: draft.description,
            p_website_url: draft.websiteURL, p_phone_number: draft.phoneNumber, p_submitter_note: draft.note)
        let dto: SubmissionReceiptDTO = try await rpc("create_venue_submission", params)
        if dto.status == "already_listed", let venueID = dto.existing_venue_id { return .alreadyListed(venueID: venueID) }
        guard let id = dto.submission_id else { throw BackendError.server("missing_submission_id") }
        return .submitted(submissionID: id, status: SubmissionStatus(rawValue: dto.status) ?? .pendingReview,
                          duplicates: dto.duplicate_candidates?.map(\.model) ?? [])
    }

    func resubmit(id: UUID, draft: VenueSubmissionDraft) async throws {
        guard let coordinate = draft.coordinate, let category = draft.category else { throw BackendError.invalidInput("invalid_coordinate") }
        let params = ResubmitParams(
            p_submission_id: id, p_name: draft.name, p_category: category.rawValue, p_formatted_address: draft.address,
            p_latitude: coordinate.latitude, p_longitude: coordinate.longitude, p_description: draft.description,
            p_website_url: draft.websiteURL, p_phone_number: draft.phoneNumber, p_submitter_note: draft.note)
        try await rpcVoid("resubmit_venue_submission", params)
    }

    func withdrawSubmission(id: UUID) async throws {
        try await rpcVoid("withdraw_venue_submission", ["p_submission_id": id])
    }

    func uploadSubmissionPhoto(submissionID: UUID, photo: PhotoUpload) async throws {
        let path = try await uploadPhoto(photo, parent: submissionID, bucket: .venue)
        try await rpcVoid("attach_submission_media", MediaParams(p_revision_id: nil, p_submission_id: submissionID, p_storage_path: path,
                                                                 p_mime_type: photo.mimeType, p_byte_size: photo.data.count,
                                                                 p_width: photo.width, p_height: photo.height))
    }

    func mySubmissions() async throws -> [VenueSubmission] {
        do {
            let rows: [SubmissionDTO] = try await client.from("venue_submissions")
                .select("id,name,category,formatted_address,latitude,longitude,description,website_url,phone_number,submitter_note,status,revision,decision_reason,duplicate_of_venue_id,approved_venue_id,submitted_at,updated_at")
                .order("updated_at", ascending: false)
                .limit(100)
                .execute().value
            return rows.map(\.model)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: BusinessRemote

    func requestClaim(_ draft: VenueClaimDraft) async throws -> ClaimStatus {
        let params = ClaimParams(p_client_request_id: draft.clientRequestID, p_venue_id: draft.venueID, p_business_name: draft.businessName,
                                 p_claimant_role: draft.role.rawValue, p_contact_note: draft.contactNote, p_evidence_note: draft.evidenceNote)
        let dto: ClaimReceiptDTO = try await rpc("request_venue_claim", params)
        return ClaimStatus(rawValue: dto.status) ?? .pendingReview
    }

    func myClaims() async throws -> [VenueClaim] {
        do {
            let rows: [ClaimDTO] = try await client.from("venue_claims")
                .select("id,venue_id,business_name,claimant_role,status,decision_reason,created_at")
                .order("created_at", ascending: false).limit(50)
                .execute().value
            return rows.map(\.model)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: AdminRemote (each RPC re-checks Admin on the server)

    func adminSubmissions(status: SubmissionStatus) async throws -> [AdminSubmissionRow] {
        let rows: [AdminSubmissionDTO] = try await rpc("admin_list_venue_submissions", ["p_status": status.rawValue])
        return rows.map(\.model)
    }

    func adminSubmissionDetail(id: UUID) async throws -> AdminSubmissionDetail {
        let dto: AdminSubmissionDetailDTO = try await rpc("admin_get_venue_submission", ["p_submission_id": id])
        return dto.model
    }

    func adminDecide(submissionID: UUID, decision: AdminSubmissionDecision) async throws {
        switch decision {
        case .approve(let note, let force):
            try await rpcVoid("admin_approve_venue_submission", ApproveParams(p_submission_id: submissionID, p_note: note, p_force: force))
        case .reject(let reason):
            try await rpcVoid("admin_reject_venue_submission", ReasonParams(p_submission_id: submissionID, p_reason: reason))
        case .requestChanges(let reason):
            try await rpcVoid("admin_request_submission_changes", ReasonParams(p_submission_id: submissionID, p_reason: reason))
        case .markDuplicate(let venueID, let reason):
            try await rpcVoid("admin_mark_submission_duplicate", DuplicateParams(p_submission_id: submissionID, p_venue_id: venueID, p_reason: reason))
        }
    }

    func adminPendingClaims() async throws -> [AdminClaimRow] {
        let rows: [AdminClaimDTO] = try await rpc("admin_list_venue_claims", ["p_status": "pending_review"])
        return rows.map(\.model)
    }

    func adminDecideClaim(id: UUID, approve: Bool, reason: String?) async throws {
        try await rpcVoid("admin_decide_venue_claim", ClaimDecisionParams(p_claim_id: id, p_approve: approve, p_reason: reason))
    }

    func adminFlaggedReviews() async throws -> [AdminFlaggedReview] {
        let rows: [FlaggedReviewDTO] = try await rpc("admin_list_flagged_reviews", ["p_limit": 50])
        return rows.map(\.model)
    }

    func adminModerateReview(id: UUID, status: ReviewStatus, reason: String) async throws {
        try await rpcVoid("admin_moderate_review", ModerateParams(p_review_id: id, p_status: status.rawValue, p_reason: reason))
    }
}
