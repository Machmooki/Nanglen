import Foundation
import Testing
@testable import Nanglen_App

/// Product-rule tests against the Demo backend, which implements the same contract as the SQL RPCs.
/// (The SQL itself is covered by supabase/tests/database/*.test.sql.)
@MainActor
struct BackendRulesTests {
    // MARK: Guest

    @Test func guestCanBrowseAndFavoriteButNotContribute() async throws {
        let backend = makeBackend()
        try await backend.ensureSession()
        let caps = try await backend.capabilities()
        #expect(caps.isAnonymous && !caps.isRegistered && !caps.isAdmin)

        let page = try await backend.searchVenues(VenueSearchQuery(origin: Fixtures.cafe))
        #expect(!page.venues.isEmpty)
        try await backend.setFavorite(venueID: Fixtures.cafeID, isFavorite: true)
        #expect(try await backend.favoriteVenueIDs() == [Fixtures.cafeID])

        await #expect(throws: BackendError.registrationRequired) { try await backend.issueVisitChallenge(venueID: Fixtures.cafeID) }
        var draft = VenueSubmissionDraft()
        draft.name = "X"; draft.category = .cafe; draft.coordinate = Fixtures.cafe
        await #expect(throws: BackendError.registrationRequired) { try await backend.createSubmission(draft) }
    }

    @Test func linkingPhoneKeepsUserIDAndFavorites() async throws {
        let backend = makeBackend()
        try await backend.ensureSession()
        let guestID = try await backend.capabilities().userID
        try await backend.setFavorite(venueID: Fixtures.cafeID, isFavorite: true)
        try await backend.requestPhoneLink(phoneE164: "+66812345678")
        try await backend.confirmPhoneLink(phoneE164: "+66812345678", code: DemoSeed.demoOTP)
        let caps = try await backend.capabilities()
        #expect(caps.userID == guestID)
        #expect(caps.isRegistered)
        #expect(try await backend.favoriteVenueIDs() == [Fixtures.cafeID])
    }

    @Test func phoneAlreadyLinkedElsewhereIsRejectedNotMerged() async throws {
        let backend = makeBackend()
        try await registerUser(backend, phone: "+66812345678")
        try await backend.signOut()
        await #expect(throws: BackendError.phoneAlreadyInUse) { try await backend.requestPhoneLink(phoneE164: "+66812345678") }
    }

    @Test func wrongOTPIsRejected() async throws {
        let backend = makeBackend()
        try await backend.ensureSession()
        try await backend.requestPhoneLink(phoneE164: "+66812345678")
        await #expect(throws: BackendError.invalidOTP) { try await backend.confirmPhoneLink(phoneE164: "+66812345678", code: "000000") }
        #expect(try await backend.capabilities().isRegistered == false)
    }

    // MARK: Visit verification

    @Test func verificationOutcomes() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)

        func attempt(_ reading: LocationReading) async throws -> VisitVerificationStatus {
            let challenge = try await backend.issueVisitChallenge(venueID: Fixtures.cafeID)
            return try await backend.verifyVisit(challengeID: challenge.id, reading: reading).status
        }
        #expect(try await attempt(Fixtures.reading(Fixtures.north(of: Fixtures.cafe, meters: 150))) == .tooFar)
        #expect(try await attempt(Fixtures.reading(accuracy: 80)) == .inaccurate)
        #expect(try await attempt(Fixtures.reading(age: 120)) == .stale)
        #expect(try await attempt(Fixtures.reading(accuracy: -1)) == .invalid)
        #expect(try await attempt(Fixtures.reading(Fixtures.north(of: Fixtures.cafe, meters: 90))) == .verified)
    }

    @Test func challengeIsOneUseAndExpires() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)
        let challenge = try await backend.issueVisitChallenge(venueID: Fixtures.cafeID)
        _ = try await backend.verifyVisit(challengeID: challenge.id, reading: Fixtures.reading())
        await #expect(throws: BackendError.challengeConsumed) { try await backend.verifyVisit(challengeID: challenge.id, reading: Fixtures.reading()) }

        let late = try await backend.issueVisitChallenge(venueID: Fixtures.cafeID)
        clock.advance(121)
        await #expect(throws: BackendError.challengeExpired) {
            try await backend.verifyVisit(challengeID: late.id, reading: LocationReading(point: Fixtures.cafe, horizontalAccuracy: 5, timestamp: clock.now))
        }
    }

    @Test func readingTakenBeforeChallengeIsStale() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        let challenge = try await backend.issueVisitChallenge(venueID: Fixtures.cafeID)
        // Fixtures.reading(age: 30) predates the challenge by 30 s (cached location from Explore).
        let result = try await backend.verifyVisit(challengeID: challenge.id, reading: Fixtures.reading(age: 30))
        #expect(result.status == .stale)
        #expect(result.verificationID == nil)
    }

    // MARK: Reviews

    private func verified(_ backend: DemoBackend, venue: UUID = Fixtures.cafeID, at point: GeoPoint = Fixtures.cafe) async throws -> UUID {
        let challenge = try await backend.issueVisitChallenge(venueID: venue)
        let result = try await backend.verifyVisit(challengeID: challenge.id, reading: Fixtures.reading(point))
        return try #require(result.verificationID)
    }

    private func submission(_ verification: UUID, rating: Int = 4, tags: [String] = ["quiet"], key: UUID = UUID(), venue: UUID = Fixtures.cafeID) -> ReviewSubmission {
        ReviewSubmission(venueID: venue, verificationID: verification, rating: rating, purpose: .study, tags: tags, body: "ok", idempotencyKey: key)
    }

    @Test func reviewRequiresUnconsumedVerificationForSameVenue() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        let verification = try await verified(backend)
        await #expect(throws: BackendError.verificationInvalid) {
            try await backend.submitReview(submission(verification, venue: Fixtures.libraryID))
        }
        _ = try await backend.submitReview(submission(verification))
        await #expect(throws: BackendError.verificationConsumed) { try await backend.submitReview(submission(verification)) }
    }

    @Test func expiredVerificationCannotPublish() async throws {
        let clock = TestClock()
        let backend = makeBackend(clock: clock)
        try await registerUser(backend)
        let verification = try await verified(backend)
        clock.advance(901)
        await #expect(throws: BackendError.verificationExpired) { try await backend.submitReview(submission(verification)) }
    }

    @Test func anotherUserCannotUseMyVerification() async throws {
        let backend = makeBackend()
        try await registerUser(backend, phone: "+66811111111")
        let verification = try await verified(backend)
        try await registerUser(backend, phone: "+66822222222")
        await #expect(throws: BackendError.verificationInvalid) { try await backend.submitReview(submission(verification)) }
    }

    @Test func revisitCreatesRevisionNotDuplicateReview() async throws {
        let backend = makeBackend()
        let before = try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 50, offset: 0).reviews.count
        try await registerUser(backend)
        let first = try await backend.submitReview(submission(try await verified(backend), rating: 5))
        let second = try await backend.submitReview(submission(try await verified(backend), rating: 2))
        #expect(first.reviewID == second.reviewID)
        #expect(second.revisionNumber == 2)
        let reviews = try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 50, offset: 0).reviews
        #expect(reviews.count == before + 1)
        #expect(reviews.first { $0.isMine }?.rating == 2)
        #expect(reviews.first { $0.isMine }?.isVerifiedVisit == true)
    }

    @Test func idempotentReplayDoesNotCreateAnotherRevision() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        let key = UUID()
        let verification = try await verified(backend)
        let first = try await backend.submitReview(submission(verification, key: key))
        let replay = try await backend.submitReview(submission(verification, key: key))
        #expect(replay.replayed)
        #expect(replay.revisionID == first.revisionID)
    }

    @Test func tooManyTagsRejectedServerSide() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        let verification = try await verified(backend)
        await #expect(throws: BackendError.invalidInput("too_many_tags")) {
            try await backend.submitReview(submission(verification, tags: ["quiet", "good_wifi", "power_outlets", "lively"]))
        }
    }

    @Test func venueWithoutReviewsHasNilAverage() async throws {
        let backend = makeBackend()
        try await backend.ensureSession()
        let quietVenue = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!
        let detail = try await backend.venueDetail(id: quietVenue)
        #expect(detail.summary.rating.average == nil)
        #expect(detail.ratingDistribution == nil)
    }

    // MARK: Submissions & Admin

    private func draft(_ name: String = "Brand New Loft") -> VenueSubmissionDraft {
        var draft = VenueSubmissionDraft()
        draft.name = name
        draft.category = .studySpace
        draft.coordinate = GeoPoint(latitude: 13.7500, longitude: 100.5400)
        draft.address = "Bangkok"
        return draft
    }

    @Test func pendingSubmissionIsNotPublicUntilAdminApproves() async throws {
        let backend = makeBackend()
        try await registerUser(backend, phone: "+66811111111")
        guard case .submitted(let id, let status, _) = try await backend.createSubmission(draft()) else {
            Issue.record("expected submitted")
            return
        }
        #expect(status == .pendingReview)
        #expect(try await backend.searchVenues(VenueSearchQuery(text: "Brand New Loft")).venues.isEmpty)
        await #expect(throws: BackendError.adminRequired) { try await backend.adminDecide(submissionID: id, decision: .approve(note: nil, force: false)) }

        try await registerUser(backend, phone: DemoSeed.adminPhone)
        #expect(try await backend.capabilities().isAdmin)
        try await backend.adminDecide(submissionID: id, decision: .approve(note: "ok", force: false))
        #expect(try await backend.searchVenues(VenueSearchQuery(text: "Brand New Loft")).venues.count == 1)
        #expect(backend.auditCount == 1)
        await #expect(throws: BackendError.invalidStatusTransition) { try await backend.adminDecide(submissionID: id, decision: .approve(note: nil, force: false)) }
    }

    @Test func submissionIsIdempotentPerClientRequest() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        let request = draft()
        guard case .submitted(let first, _, _) = try await backend.createSubmission(request),
              case .submitted(let second, _, _) = try await backend.createSubmission(request) else {
            Issue.record("expected submitted")
            return
        }
        #expect(first == second)
        #expect(try await backend.mySubmissions().count == 1)
    }

    @Test func rejectAndNeedsChangesRequireReasonAndResubmit() async throws {
        let backend = makeBackend()
        try await registerUser(backend, phone: "+66811111111")
        guard case .submitted(let id, _, _) = try await backend.createSubmission(draft()) else { return }
        try await registerUser(backend, phone: DemoSeed.adminPhone)
        await #expect(throws: BackendError.invalidInput("reason_required")) { try await backend.adminDecide(submissionID: id, decision: .reject(reason: " ")) }
        try await backend.adminDecide(submissionID: id, decision: .requestChanges(reason: "Move the pin"))
        try await registerUser(backend, phone: "+66811111111")
        let mine = try #require(try await backend.mySubmissions().first)
        #expect(mine.status == .needsChanges)
        #expect(mine.decisionReason == "Move the pin")
        try await backend.resubmit(id: id, draft: draft())
        #expect(try await backend.mySubmissions().first?.status == .pendingReview)
    }

    @Test func exactProviderMatchLinksExistingVenue() async throws {
        let backend = makeBackend()
        try await registerUser(backend)
        var request = draft("Copy of cafe")
        request.provider = "curated"
        request.externalPlaceID = "seed:\(Fixtures.cafeID.uuidString)"
        #expect(try await backend.createSubmission(request) == .alreadyListed(venueID: Fixtures.cafeID))
    }

    @Test func likelyDuplicateNeedsForceAndDuplicateLinksVenue() async throws {
        let backend = makeBackend()
        try await registerUser(backend, phone: "+66811111111")
        var copy = draft("ใบชา คาเฟ่ (ตัวอย่าง)")
        copy.coordinate = Fixtures.north(of: Fixtures.cafe, meters: 10)
        guard case .submitted(let id, _, let duplicates) = try await backend.createSubmission(copy) else { return }
        #expect(duplicates.contains { $0.venueID == Fixtures.cafeID })
        try await registerUser(backend, phone: DemoSeed.adminPhone)
        await #expect(throws: BackendError.likelyDuplicate) { try await backend.adminDecide(submissionID: id, decision: .approve(note: nil, force: false)) }
        try await backend.adminDecide(submissionID: id, decision: .markDuplicate(venueID: Fixtures.cafeID, reason: "Same place"))
        #expect(try await backend.adminSubmissions(status: .duplicate).count == 1)
    }

    // MARK: Business claims and moderation

    @Test func claimGrantsScopedAccessOnlyAfterApproval() async throws {
        let backend = makeBackend()
        try await registerUser(backend, phone: "+66811111111")
        #expect(try await backend.requestClaim(VenueClaimDraft(venueID: Fixtures.cafeID, businessName: "Baicha Co.")) == .pendingReview)
        #expect(try await backend.venueDetail(id: Fixtures.cafeID).isManagedByMe == false)
        #expect(try await backend.capabilities().memberships.isEmpty)

        try await registerUser(backend, phone: DemoSeed.adminPhone)
        let claim = try #require(try await backend.adminPendingClaims().first)
        try await backend.adminDecideClaim(id: claim.id, approve: true, reason: nil)
        #expect(try await backend.venueDetail(id: Fixtures.cafeID).isManagedByMe == false, "the Admin is not a member")

        try await registerUser(backend, phone: "+66811111111")
        #expect(try await backend.venueDetail(id: Fixtures.cafeID).isManagedByMe)
        #expect(try await backend.venueDetail(id: Fixtures.libraryID).isManagedByMe == false, "scoped to the claimed venue")
        #expect(try await backend.capabilities().memberships.first?.venueIDs == [Fixtures.cafeID])
    }

    @Test func flaggedReviewCanBeHiddenOnlyByAdmin() async throws {
        let backend = makeBackend()
        try await registerUser(backend, phone: "+66811111111")
        let reviewID = try #require(try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 10, offset: 0).reviews.first?.id)
        try await backend.flagReview(id: reviewID, reason: .spam, note: nil)
        await #expect(throws: BackendError.adminRequired) { try await backend.adminModerateReview(id: reviewID, status: .hidden, reason: "x") }
        try await registerUser(backend, phone: DemoSeed.adminPhone)
        #expect(try await backend.adminFlaggedReviews().map(\.id) == [reviewID])
        try await backend.adminModerateReview(id: reviewID, status: .hidden, reason: "Spam")
        let visible = try await backend.reviews(venueID: Fixtures.cafeID, sort: .recent, limit: 50, offset: 0).reviews
        #expect(!visible.contains { $0.id == reviewID })
    }
}
