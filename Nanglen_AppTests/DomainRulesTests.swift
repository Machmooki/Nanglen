import Foundation
import Testing
@testable import Nanglen_App

@MainActor
struct RankingTests {
    let ranker = VenueRanker()

    @Test func bayesianRatingDoesNotLetOneFiveStarReviewWin() {
        let oneFive = ranker.bayesianRating(average: 5, count: 1)
        let manyStrong = ranker.bayesianRating(average: 4.6, count: 40)
        #expect(manyStrong > oneFive)
    }

    @Test func noReviewsFallsBackToPrior() {
        #expect(ranker.bayesianRating(average: nil, count: 0) == ranker.priorMean)
    }

    @Test func ratingSortUsesConfidence() {
        let a = Fixtures.summary(name: "A", average: 5, count: 1)
        let b = Fixtures.summary(name: "B", average: 4.6, count: 40)
        #expect(ranker.sort([a, b], by: .rating).map(\.name) == ["B", "A"])
    }

    @Test func distanceSortPutsUnknownDistanceLast() {
        let near = Fixtures.summary(name: "Near", average: nil, count: 0, distance: 100)
        let far = Fixtures.summary(name: "Far", average: nil, count: 0, distance: 900)
        let unknown = Fixtures.summary(name: "Unknown", average: nil, count: 0, distance: nil)
        #expect(ranker.sort([unknown, far, near], by: .distance).map(\.name) == ["Near", "Far", "Unknown"])
    }

    @Test func relevancePrefersPrefixThenSubstring() {
        #expect(ranker.relevance(name: "Study Loft", query: "study") > ranker.relevance(name: "My Study Loft", query: "study"))
        #expect(ranker.relevance(name: "Hive Corner", query: "zzz") == 0)
    }

    @Test func scoreIncludesDistanceAndQuality() {
        let close = ranker.score(rating: .empty, distanceMeters: 100, relevance: nil)
        let far = ranker.score(rating: .empty, distanceMeters: 5_000, relevance: nil)
        #expect(close > far)
    }
}

@MainActor
struct RatingDisplayTests {
    @Test func noReviewsNeverShowsZero() {
        #expect(RatingSummary.empty.displayText == L10n.Rating.noReviews)
        #expect(!RatingSummary(reviewCount: 0, average: 0).displayText.contains("0.0"))
    }

    @Test func showsAverageAndCount() {
        let text = RatingSummary(reviewCount: 28, average: 4.6).displayText
        #expect(text.contains("4.6"))
        #expect(text.contains("28"))
    }
}

@MainActor
struct ReadingEvaluatorTests {
    let policy = VerificationPolicy.default

    @Test func plausibleInsideRadius() {
        let reading = Fixtures.reading(Fixtures.north(of: Fixtures.cafe, meters: 60))
        guard case .plausible = VisitReadingEvaluator.evaluate(reading, venue: Fixtures.cafe, policy: policy, now: Fixtures.now) else {
            Issue.record("expected plausible")
            return
        }
    }

    @Test func tooFarOutsideRadius() {
        let reading = Fixtures.reading(Fixtures.north(of: Fixtures.cafe, meters: 150))
        guard case .tooFar = VisitReadingEvaluator.evaluate(reading, venue: Fixtures.cafe, policy: policy, now: Fixtures.now) else {
            Issue.record("expected tooFar")
            return
        }
    }

    @Test func inaccurateAndStaleAndInvalid() {
        #expect(VisitReadingEvaluator.evaluate(Fixtures.reading(accuracy: 51), venue: Fixtures.cafe, policy: policy, now: Fixtures.now) == .inaccurate(accuracy: 51))
        if case .stale = VisitReadingEvaluator.evaluate(Fixtures.reading(age: 61), venue: Fixtures.cafe, policy: policy, now: Fixtures.now) {} else { Issue.record("expected stale") }
        #expect(VisitReadingEvaluator.evaluate(Fixtures.reading(accuracy: -1), venue: Fixtures.cafe, policy: policy, now: Fixtures.now) == .invalid)
    }
}

@MainActor
struct ValidatorTests {
    @Test func reviewRequiresRatingAndLimits() {
        #expect(ReviewValidator.issues(rating: nil, tags: [], body: "", maxTags: 3, maxBody: 500) == [.ratingRequired])
        #expect(ReviewValidator.issues(rating: 6, tags: [], body: "", maxTags: 3, maxBody: 500) == [.ratingRequired])
        #expect(ReviewValidator.issues(rating: 4, tags: ["a", "b", "c", "d"], body: "", maxTags: 3, maxBody: 500) == [.tooManyTags(max: 3)])
        #expect(ReviewValidator.issues(rating: 4, tags: [], body: String(repeating: "ก", count: 501), maxTags: 3, maxBody: 500) == [.bodyTooLong(max: 500)])
        #expect(ReviewValidator.issues(rating: 5, tags: ["quiet"], body: "ดี", maxTags: 3, maxBody: 500).isEmpty)
    }

    @Test func submissionRequiresNameCategoryLocation() {
        var draft = VenueSubmissionDraft()
        #expect(Set(SubmissionValidator.issues(draft)) == [.nameRequired, .categoryRequired, .locationRequired])
        draft.name = "Loft"
        draft.category = .studySpace
        draft.coordinate = Fixtures.cafe
        #expect(SubmissionValidator.issues(draft).isEmpty)
        draft.websiteURL = "javascript:alert(1)"
        #expect(SubmissionValidator.issues(draft) == [.invalidWebsite])
    }

    @Test func emailsNormalizeAndMask() {
        #expect(EmailAddress.normalized("  Mint@Gmail.com ") == "mint@gmail.com")
        #expect(EmailAddress.normalized("no-at-sign") == nil)
        #expect(EmailAddress.normalized("a@b") == nil)
        #expect(EmailAddress.normalized("a@@b.com") == nil)
        #expect(EmailAddress.normalized("a b@c.com") == nil)
        #expect(EmailAddress.masked("mint@gmail.com") == "m•••@gmail.com")
    }

    @Test func displayNamePolicy() {
        #expect(DisplayNamePolicy.clean(" Mint\u{200B}\u{202E}  Reader\n") == "Mint Reader")
        #expect(DisplayNamePolicy.isReserved("Official Nanglen"))
        #expect(DisplayNamePolicy.isReserved("แอดมินร้าน"))
        #expect(!DisplayNamePolicy.isReserved("Mint"))
    }

    @Test func onlyWebLinksAreOpened() {
        #expect(SafeLink.isWebURL(URL(string: "https://example.com")!))
        #expect(!SafeLink.isWebURL(URL(string: "javascript:alert(1)")!))
        #expect(!SafeLink.isWebURL(URL(string: "file:///etc/passwd")!))
        #expect(!SafeLink.isWebURL(URL(string: "https://user:pw@evil.example")!))
        #expect(!SafeLink.isWebURL(URL(string: "tel:123")!))
    }

    @Test func filterSummaryAndRemoval() {
        var filter = VenueFilter()
        filter.tags = ["quiet", "study_friendly"]
        filter.minimumRating = 4
        filter.reviewedOnly = true
        #expect(filter.activeCount == 4)
        #expect(filter.activeItems == [.tag("study_friendly"), .tag("quiet"), .minimumRating, .reviewedOnly])
        filter.remove(.tag("quiet"))
        filter.remove(.minimumRating)
        #expect(filter.activeItems == [.tag("study_friendly"), .reviewedOnly])
    }

    @Test func backendErrorMapping() {
        #expect(BackendError.fromServerMessage("registration_required") == .registrationRequired)
        #expect(BackendError.fromServerMessage("verification_consumed") == .verificationConsumed)
        #expect(BackendError.fromServerMessage("too_many_tags") == .invalidInput("too_many_tags"))
        #expect(BackendError.verificationExpired.requiresFreshVerification)
        #expect(!BackendError.network.requiresFreshVerification)
    }
}

@MainActor
struct SupabaseConfigurationTests {
    @Test func baseURLIsNormalized() {
        #expect(SupabaseConfiguration.normalizedBaseURL("https://abc.supabase.co")?.absoluteString == "https://abc.supabase.co")
        #expect(SupabaseConfiguration.normalizedBaseURL(" https://abc.supabase.co/ ")?.absoluteString == "https://abc.supabase.co")
        #expect(SupabaseConfiguration.normalizedBaseURL("https://abc.supabase.co/rest/v1/")?.absoluteString == "https://abc.supabase.co")
        #expect(SupabaseConfiguration.normalizedBaseURL("http://localhost:54321")?.absoluteString == "http://localhost:54321")
    }

    @Test func badURLsAreRejected() {
        #expect(SupabaseConfiguration.normalizedBaseURL("http://abc.supabase.co") == nil, "plain http only for localhost")
        #expect(SupabaseConfiguration.normalizedBaseURL("https://YOUR_PROJECT_REF.supabase.co") == nil)
        #expect(SupabaseConfiguration.normalizedBaseURL("https://abc.supabase.co/other/path") == nil)
        #expect(SupabaseConfiguration.normalizedBaseURL("not a url") == nil)
    }

    @Test func placeholderAndSecretKeysAreRejected() {
        #expect(SupabaseConfiguration.make(rawURL: "https://abc.supabase.co", rawKey: "sb_publishable_abc") != nil)
        #expect(SupabaseConfiguration.make(rawURL: "https://abc.supabase.co", rawKey: "YOUR_PUBLISHABLE_KEY") == nil)
        #expect(SupabaseConfiguration.make(rawURL: "https://abc.supabase.co", rawKey: "sb_secret_abc") == nil)
        // {"role":"service_role"} as a JWT payload
        let serviceRole = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig"
        #expect(SupabaseConfiguration.make(rawURL: "https://abc.supabase.co", rawKey: serviceRole) == nil)
        let anon = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.sig"
        #expect(SupabaseConfiguration.make(rawURL: "https://abc.supabase.co", rawKey: anon) != nil)
    }

    @Test func smtpFailuresBecomeEmailNotSent() {
        #expect(SupabaseBackend.isEmailDeliveryFailure("Error sending email change email"))
        #expect(SupabaseBackend.isEmailDeliveryFailure("535 \"5.7.8 Username and Password not accepted."))
        #expect(!SupabaseBackend.isEmailDeliveryFailure("Database error saving new user"))
        #expect(BackendError.emailNotSent != .server(""))
    }
}
