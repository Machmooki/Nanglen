import Foundation
import Supabase
import os

/// Reads `Supabase.plist` (URL + anon/publishable key) from the app bundle, or the
/// `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment variables. The anon key is public by design;
/// the service-role key must never be placed in the app.
nonisolated struct SupabaseConfiguration: Sendable {
    var url: URL
    var anonKey: String

    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> SupabaseConfiguration? {
        if let raw = environment["SUPABASE_URL"], let key = environment["SUPABASE_ANON_KEY"] {
            return make(rawURL: raw, rawKey: key)
        }
        guard let fileURL = bundle.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rawURL = plist["SUPABASE_URL"] as? String,
              let rawKey = plist["SUPABASE_ANON_KEY"] as? String
        else { return nil }
        return make(rawURL: rawURL, rawKey: rawKey)
    }

    /// Validates values and rejects placeholders and secret keys.
    static func make(rawURL: String, rawKey: String) -> SupabaseConfiguration? {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedBaseURL(rawURL), !key.isEmpty, !key.hasPrefix("YOUR_"),
              // A secret / service_role key must never ship in the app.
              !key.hasPrefix("sb_secret_"), !isServiceRoleJWT(key)
        else { return nil }
        return SupabaseConfiguration(url: url, anonKey: key)
    }

    /// Accepts "https://<ref>.supabase.co", tolerating a trailing "/" or a pasted "/rest/v1/" suffix.
    /// Requires https (http only for localhost development).
    static func normalizedBaseURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        for suffix in ["/rest/v1", "/auth/v1", "/storage/v1"] where value.lowercased().hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        guard !value.contains("YOUR_"), let components = URLComponents(string: value),
              let host = components.host, !host.isEmpty,
              components.path.isEmpty, components.query == nil, components.user == nil
        else { return nil }
        let isLocal = host == "localhost" || host == "127.0.0.1"
        guard components.scheme == "https" || (components.scheme == "http" && isLocal) else { return nil }
        return components.url
    }

    private static func isServiceRoleJWT(_ key: String) -> Bool {
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (json["role"] as? String) == "service_role"
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

    nonisolated private static let authLogger = Logger(subsystem: "Mach.Nanglen-App", category: "Auth")
    nonisolated private static let mediaLogger = Logger(subsystem: "Mach.Nanglen-App", category: "Media")

    /// GoTrue answers 500 `unexpected_failure` with e.g. "Error sending email change email" or the raw
    /// SMTP reply ("535 5.7.8 Username and Password not accepted") when the code email can't be sent.
    static func isEmailDeliveryFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("error sending") || lower.contains("smtp") || lower.contains("5.7.8")
            || lower.contains("username and password not accepted")
    }

    static func map(_ error: Error) -> Error {
        if let error = error as? BackendError { return error }
        if let error = error as? PostgrestError { return BackendError.fromServerMessage(error.message) }
        if let error = error as? AuthError {
            if case let .api(message, code, _, _) = error {
                if code == .emailExists || code == .userAlreadyExists || code == .phoneExists || code == .identityAlreadyExists {
                    return BackendError.accountExists
                }
                if code == .userNotFound || code == .otpDisabled { return BackendError.notFound }
                if code == .overEmailSendRateLimit { return BackendError.rateLimited }
                if code == .otpExpired || message.localizedCaseInsensitiveContains("token") { return BackendError.invalidOTP }
                // Shown in the Xcode console so a server-side cause (e.g. SMTP login refused) isn't hidden
                // behind the generic message.
                authLogger.error("Auth API error \(code.rawValue, privacy: .public): \(message)")
                if isEmailDeliveryFailure(message) { return BackendError.emailNotSent }
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

    func requestEmailLink(email: String) async throws {
        do {
            // For an anonymous user this links an email identity to the SAME user id after the code is verified.
            // The "Change email address" template must contain {{ .Token }} (see supabase/templates/email_otp.html).
            try await client.auth.update(user: UserAttributes(email: email))
        } catch {
            throw Self.map(error)
        }
    }

    func confirmEmailLink(email: String, code: String) async throws {
        do {
            try await client.auth.verifyOTP(email: email, token: code, type: .emailChange)
            _ = try await client.auth.refreshSession()
        } catch {
            throw Self.map(error)
        }
    }

    func requestEmailSignIn(email: String) async throws {
        do {
            // Existing accounts only: never creates a second account by accident.
            try await client.auth.signInWithOTP(email: email, shouldCreateUser: false)
        } catch {
            throw Self.map(error)
        }
    }

    func confirmEmailSignIn(email: String, code: String) async throws {
        do {
            try await client.auth.verifyOTP(email: email, token: code, type: .email)
        } catch {
            throw Self.map(error)
        }
    }

    func deleteAccount() async throws {
        do {
            // The Edge Function derives the user from this session's JWT and uses the service role server-side.
            try await client.functions.invoke("delete-account", options: FunctionInvokeOptions(method: .post))
        } catch let error as FunctionsError {
            if case let .httpError(code, _) = error, code == 409 { throw BackendError.deletionBlocked }
            throw BackendError.server("delete_failed")
        } catch {
            throw Self.map(error)
        }
        try? await client.auth.signOut(scope: .local)
        try await ensureSession()
    }

    func updateDisplayName(_ name: String) async throws {
        try await rpcVoid("update_my_display_name", ["p_display_name": name])
    }

    private nonisolated struct AvatarChange: Decodable, Sendable {
        var previous_path: String?
    }

    /// Upload first, then `set_my_avatar` checks the caller owns the object. The old file is deleted afterwards
    /// (best effort: a leftover file is private to its owner and is removed with the account).
    func updateAvatar(_ photo: PhotoUpload?) async throws {
        let bucket = client.storage.from(MediaBucket.avatar.rawValue)
        let change: AvatarChange
        if let photo {
            let path = "\(UUID().uuidString.lowercased()).\(photo.fileExtension)"
            do {
                try await bucket.upload(path, data: photo.data, options: FileOptions(contentType: photo.mimeType, upsert: false))
            } catch {
                throw Self.map(error)
            }
            change = try await rpc("set_my_avatar", ["p_storage_path": path])
        } else {
            change = try await rpc("clear_my_avatar")
        }
        if let previous = change.previous_path {
            _ = try? await bucket.remove(paths: [previous])
        }
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
            p_query: query.trimmedText.isEmpty ? nil : String(query.trimmedText.prefix(100)),
            p_latitude: query.origin?.latitude, p_longitude: query.origin?.longitude,
            p_radius_m: query.radiusMeters, p_category: query.category?.rawValue,
            p_min_rating: query.filter.minimumRating, p_sort: query.filter.sort.rawValue,
            p_limit: query.limit + 1, p_offset: query.offset,
            p_tags: query.filter.tags.isEmpty ? nil : query.filter.tags.sorted(),
            p_reviewed_only: query.filter.reviewedOnly)
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

    // MARK: ConfigRemote

    func publicConfig() async throws -> RemoteConfigValues {
        try await rpc("get_public_config")
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

    /// Uploads to '<parent>/<uuid>.<ext>' — the only shape Storage RLS and attach RPCs accept.
    private func uploadPhoto(_ photo: PhotoUpload, parent: UUID, bucket: MediaBucket) async throws -> String {
        do {
            // '<parent>/<random>.<ext>': no auth user id in public paths. Storage RLS checks parent ownership.
            let path = "\(parent.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(photo.fileExtension)"
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

    func submissionPhotos(submissionID: UUID) async throws -> [SubmissionPhoto] {
        let rows: [SubmissionMediaDTO] = try await rpc("list_my_submission_media", ["p_submission_id": submissionID])
        return rows.map(\.model)
    }

    /// The RPC checks ownership and `needs_changes`, deletes the row and returns the path; the Storage object is
    /// then removed with the owner's own policy. A failed object delete only leaves an unreferenced file.
    func removeSubmissionPhoto(id: UUID) async throws {
        let path: String = try await rpc("remove_submission_media", ["p_media_id": id])
        do {
            _ = try await client.storage.from(MediaBucket.venue.rawValue).remove(paths: [path])
        } catch {
            Self.mediaLogger.notice("Submission photo row removed but the Storage object was not: \(error.localizedDescription, privacy: .public)")
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

    func adminFlaggedReviews() async throws -> [AdminFlaggedReview] {
        let rows: [FlaggedReviewDTO] = try await rpc("admin_list_flagged_reviews", ["p_limit": 50])
        return rows.map(\.model)
    }

    func adminModerateReview(id: UUID, status: ReviewStatus, reason: String) async throws {
        try await rpcVoid("admin_moderate_review", ModerateParams(p_review_id: id, p_status: status.rawValue, p_reason: reason))
    }
}
