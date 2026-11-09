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

    @Test func thaiPhoneNumbersNormalizeToE164() {
        #expect(PhoneNumberFormatter.e164(from: "081 234 5678") == "+66812345678")
        #expect(PhoneNumberFormatter.e164(from: "+66 81 234 5678") == "+66812345678")
        #expect(PhoneNumberFormatter.e164(from: "abc") == nil)
        #expect(PhoneNumberFormatter.masked("+66812345678") == "+66 •••• 5678")
    }

    @Test func backendErrorMapping() {
        #expect(BackendError.fromServerMessage("registration_required") == .registrationRequired)
        #expect(BackendError.fromServerMessage("verification_consumed") == .verificationConsumed)
        #expect(BackendError.fromServerMessage("too_many_tags") == .invalidInput("too_many_tags"))
        #expect(BackendError.verificationExpired.requiresFreshVerification)
        #expect(!BackendError.network.requiresFreshVerification)
    }
}
