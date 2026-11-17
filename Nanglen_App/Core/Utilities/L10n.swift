import Foundation

/// All user-facing strings. English is the development language; keys are the English source text so the
/// String Catalog can add translations later.
enum L10n {
    enum Common {
        static var ok: String { String(localized: "OK") }
        static var cancel: String { String(localized: "Cancel") }
        static var close: String { String(localized: "Close") }
        static var retry: String { String(localized: "Try again") }
        static var save: String { String(localized: "Save") }
        static var done: String { String(localized: "Done") }
        static var send: String { String(localized: "Send") }
        static var unnamedPlace: String { String(localized: "Unnamed place") }
        static var openSettings: String { String(localized: "Open Settings") }
        static var somethingWentWrong: String { String(localized: "Something went wrong. Please try again.") }
        static var directions: String { String(localized: "Directions") }
        static var remove: String { String(localized: "Remove") }
        static var optional: String { String(localized: "Optional") }
        static var loading: String { String(localized: "Loading…") }
        static var demoBadge: String { String(localized: "Demo mode") }
    }

    enum Category {
        static var all: String { String(localized: "All") }
        static var cafe: String { String(localized: "Café") }
        static var library: String { String(localized: "Library") }
        static var coworking: String { String(localized: "Co-working") }
        static var studySpace: String { String(localized: "Study Space") }
        static var other: String { String(localized: "Other") }
    }

    enum Rating {
        static var noReviews: String { String(localized: "No reviews yet") }
        static func summary(_ average: String, _ count: Int) -> String { "\(average) · \(reviewCount(count))" }
        static func accessibility(_ average: String, _ count: Int) -> String {
            count == 1 ? String(localized: "Average rating \(average) out of 5 from 1 review")
                       : String(localized: "Average rating \(average) out of 5 from \(count) reviews")
        }
        static func reviewCount(_ count: Int) -> String {
            count == 1 ? String(localized: "1 review") : String(localized: "\(count) reviews")
        }
        static func starLabel(_ star: Int) -> String {
            switch star {
            case 1: String(localized: "1 star · Poor")
            case 2: String(localized: "2 stars · Below expectations")
            case 3: String(localized: "3 stars · Okay")
            case 4: String(localized: "4 stars · Good")
            default: String(localized: "5 stars · Excellent")
            }
        }
    }

    enum Explore {
        static var title: String { String(localized: "Explore") }
        static var searchPlaceholder: String { String(localized: "Search cafés, libraries, study spots…") }
        static var filter: String { String(localized: "Filters") }
        static var viewList: String { String(localized: "List") }
        static var viewMap: String { String(localized: "Map") }
        static var searchThisArea: String { String(localized: "Search this area") }
        static var locateMe: String { String(localized: "My location") }
        static var nearYou: String { String(localized: "Near you") }
        static var defaultArea: String { String(localized: "Siam, Bangkok · Use my location") }
        static var locating: String { String(localized: "Finding your location…") }
        static var mapArea: String { String(localized: "Map area") }
        static var locationOff: String { String(localized: "Location off · Search by name or map instead") }
        static var recommended: String { String(localized: "Top picks nearby 🔥") }
        static var recommendedSubtitle: String { String(localized: "Ranked by rating, reviews and distance") }
        static var eyebrow: String { String(localized: "Find your chill spot ✨") }
        static var noPhotosYet: String { String(localized: "No photos yet") }
        static var newPlace: String { String(localized: "New") }
        static var savedBadge: String { String(localized: "Saved") }
        static func distanceAway(_ distance: String) -> String { String(localized: "\(distance) away") }
        static var results: String { String(localized: "Search results") }
        static func resultsCount(_ count: Int) -> String { String(localized: "\(count) places on Nanglen") }
        static var searching: String { String(localized: "Searching…") }
        static var emptyTitle: String { String(localized: "No places found on Nanglen yet") }
        static var emptyMessage: String { String(localized: "Try another search, widen the distance, or suggest a new place to the community.") }
        static var addPlace: String { String(localized: "Add a new place") }
        static var missingPlaceFooter: String { String(localized: "Can't find it? Suggest a new place. Our team reviews it before it goes live.") }
        static var errorTitle: String { String(localized: "Couldn't load data") }
        static var offlineBanner: String { String(localized: "Offline · Showing saved data that may be out of date") }
        static func offlineSince(_ relative: String) -> String { String(localized: "Offline · Data saved \(relative) may be out of date") }
        static var loadMore: String { String(localized: "Load more") }
        static var locationDeniedTitle: String { String(localized: "Location access not allowed") }
        static var locationDeniedMessage: String { String(localized: "Turn on location access in Settings to find places near you, or search by name.") }
    }

    enum Filter {
        static var title: String { String(localized: "Filters") }
        static var sort: String { String(localized: "Sort by") }
        static var sortRelevance: String { String(localized: "Best match") }
        static var sortDistance: String { String(localized: "Nearest") }
        static var sortRating: String { String(localized: "Top rated") }
        static var distance: String { String(localized: "Distance") }
        static var minimumRating: String { String(localized: "Minimum rating") }
        static var any: String { String(localized: "Any") }
        static var apply: String { String(localized: "Show results") }
        static var reset: String { String(localized: "Reset") }
        static var footnote: String { String(localized: "Averages come from verified-visit reviews. Ranking also considers the number of reviews. Paid listings get no special ranking.") }
        static var goodFor: String { String(localized: "Good for") }
        static var goodForHint: String { String(localized: "Based on what visitors said. Pick up to 3.") }
        static var reviewedOnly: String { String(localized: "Only places with reviews") }
        static var tooManyTags: String { String(localized: "You can pick up to 3") }
        static var clearAll: String { String(localized: "Clear all") }
        static func ratingAtLeast(_ value: String) -> String { String(localized: "\(value)★ & up") }
        static func within(_ distance: String) -> String { String(localized: "Within \(distance)") }
        static var hasReviews: String { String(localized: "Has reviews") }
        static func removeFilter(_ name: String) -> String { String(localized: "Remove filter \(name)") }
    }

    enum Detail {
        static var writeReview: String { String(localized: "Write a review") }
        static var updateReview: String { String(localized: "Update review") }
        static var save: String { String(localized: "Save place") }
        static var unsave: String { String(localized: "Remove from saved") }
        static var communityTags: String { String(localized: "Visitors say") }
        static var communityTagsNote: String { String(localized: "From user reviews, not confirmed by the venue") }
        static var facilities: String { String(localized: "Facilities") }
        static var facilitiesNote: String { String(localized: "Reported by visitors") }
        static var view360: String { String(localized: "360°") }
        static var lookAround: String { String(localized: "Street view 360°") }
        static var location: String { String(localized: "Location") }
        static func photoPosition(_ index: Int, _ total: Int) -> String { String(localized: "Photo \(index) of \(total)") }
        static var panoramaHint: String { String(localized: "Drag to look around · Pinch to zoom") }
        static var panoramaFailed: String { String(localized: "Couldn't load the 360° view. Check your connection and try again.") }
        static var panoramaMotionOn: String { String(localized: "Move your phone to look around") }
        static var panoramaMotion: String { String(localized: "Look around by moving your phone") }
        static var reviews: String { String(localized: "Reviews") }
        static var sortRelevant: String { String(localized: "Relevant") }
        static var sortRecent: String { String(localized: "Recent") }
        static var noReviewsMessage: String { String(localized: "Be the first to review after visiting in person") }
        static var verifiedVisit: String { String(localized: "Verified visit") }
        static var you: String { String(localized: "You") }
        static var info: String { String(localized: "Place info") }
        static var address: String { String(localized: "Address") }
        static var website: String { String(localized: "Website") }
        static var phone: String { String(localized: "Phone") }
        static var sourceCommunity: String { String(localized: "Info from the person who suggested this place, checked by our team") }
        static var sourceBusiness: String { String(localized: "Info from the verified owner") }
        static var sourceCurated: String { String(localized: "Info from the Nanglen team") }
        static var claim: String { String(localized: "Own this place? Claim ownership") }
        static var managedByYou: String { String(localized: "You manage this place") }
        static var report: String { String(localized: "Report review") }
        static var reportSent: String { String(localized: "Report sent. Our team will take a look.") }
        static var temporarilyClosed: String { String(localized: "Temporarily closed") }
        static var permanentlyClosed: String { String(localized: "Permanently closed") }
        static var myReviewHidden: String { String(localized: "Your review was hidden by our team") }
        static func myReviewSummary(_ rating: Int, _ relative: String) -> String { String(localized: "Your review \(rating)★ · \(relative)") }
        static var revisitHint: String { String(localized: "You can update it after verifying a new visit") }
        static var photosPending: String { String(localized: "Photos appear after they're reviewed") }
        static var flagSpam: String { String(localized: "Spam or advertising") }
        static var flagOffensive: String { String(localized: "Offensive or hateful") }
        static var flagNotARealVisit: String { String(localized: "Probably not a real visit") }
        static var flagWrongVenue: String { String(localized: "Review is for a different place") }
        static var flagPrivacy: String { String(localized: "Privacy violation") }
    }

    enum Review {
        static var title: String { String(localized: "Write a review") }
        static var explain: String { String(localized: "To keep Nanglen reviews trustworthy, we check that you're at this place.") }
        static var checking: String { String(localized: "Checking your location…") }
        static var askingPermission: String { String(localized: "Asking for location access while using the app") }
        static var verifying: String { String(localized: "Verifying with the server…") }
        static var verified: String { String(localized: "Visit verified") }
        static func tooFar(_ distance: String) -> String { String(localized: "You're about \(distance) from this place. You need to be within the allowed radius.") }
        static var tooFarGeneric: String { String(localized: "You're too far from this place") }
        static var inaccurate: String { String(localized: "Your location isn't accurate enough yet. Move near a window or into the open and try again.") }
        static var stale: String { String(localized: "Your location is out of date. Please try again.") }
        static var unavailable: String { String(localized: "Can't get your location right now. Please try again.") }
        static var permissionDenied: String { String(localized: "Location access is needed to verify your visit") }
        static var registrationRequired: String { String(localized: "Verify your email before writing a review") }
        static var spoofDisclaimer: String { String(localized: "Verification uses your device's GPS. We don't store your location history.") }
        static var rating: String { String(localized: "Overall rating") }
        static var ratingRequired: String { String(localized: "Choose a rating from 1 to 5 stars") }
        static var purpose: String { String(localized: "What did you come for?") }
        static var tags: String { String(localized: "What stood out? (pick up to 3)") }
        static var comment: String { String(localized: "Short comment") }
        static var commentPlaceholder: String { String(localized: "What should others know before coming?") }
        static var photos: String { String(localized: "Photos (up to 3)") }
        static var addPhoto: String { String(localized: "Add photo") }
        static var submit: String { String(localized: "Publish review") }
        static var submitting: String { String(localized: "Publishing…") }
        static var published: String { String(localized: "Review published. Thank you!") }
        static var updated: String { String(localized: "Review updated") }
        static func photosFailed(_ count: Int) -> String { String(localized: "\(count) photos failed to upload. Your review was published.") }
        static var photosPending: String { String(localized: "Photos appear after they're reviewed") }
        static var draftSaved: String { String(localized: "Draft saved on this device. Not published yet.") }
        static var draftRestored: String { String(localized: "Restored your unsent draft") }
        static var reverify: String { String(localized: "Your verification expired or was already used. Verify your location again before publishing.") }
        static func characters(_ count: Int, _ max: Int) -> String { String(localized: "\(count)/\(max)") }
        static var tooManyTags: String { String(localized: "You can pick up to 3 tags") }
        static var verifyAgain: String { String(localized: "Verify location again") }
    }

    enum Purpose {
        static var study: String { String(localized: "Study") }
        static var work: String { String(localized: "Work") }
        static var meeting: String { String(localized: "Meeting") }
        static var relax: String { String(localized: "Relax") }
        static var other: String { String(localized: "Other") }
    }

    enum Account {
        static var guestTitle: String { String(localized: "Guest") }
        static var guestMessage: String { String(localized: "Use the app right away without signing up. Saved places are tied to this device and may be lost if you delete the app or switch devices.") }
        static var verifyEmail: String { String(localized: "Verify email") }
        static var verifyEmailBenefit: String { String(localized: "Verify your email to write reviews, suggest places and keep your saved places across devices. Everything you already saved stays. It's free, and we'll send a 6-digit code.") }
        static var verifyEmailShort: String { String(localized: "Free · Write reviews and keep your saved places") }
        static var emailPlaceholder: String { String(localized: "you@example.com") }
        static var sendCode: String { String(localized: "Send code") }
        static var resendCode: String { String(localized: "Send a new code") }
        static var codePlaceholder: String { String(localized: "6-digit code") }
        static var verifyCode: String { String(localized: "Verify code") }
        static var useDifferentEmail: String { String(localized: "Use a different email") }
        static func codeSent(_ masked: String) -> String { String(localized: "Code sent to \(masked). Check your inbox and spam folder.") }
        static var linked: String { String(localized: "Email verified. You're now a member.") }
        static var signedIn: String { String(localized: "Signed in to your account") }
        static var accountExistsTitle: String { String(localized: "You already have an account") }
        static func accountExistsMessage(_ email: String) -> String { String(localized: "\(email) is already a Nanglen account. Sign in to it? Places you saved as a guest on this phone won't be moved over.") }
        static var signInInstead: String { String(localized: "Sign in") }
        static var emailPrivacy: String { String(localized: "We only use your email to sign you in. It's never shown on reviews.") }
        static func demoOTPHint(_ code: String) -> String { String(localized: "Demo mode: no email is sent. Use code \(code)") }
        static var invalidEmail: String { String(localized: "Enter a valid email address") }
        static var registeredRequiredTitle: String { String(localized: "Members only") }
        static var registeredRequiredReview: String { String(localized: "Guests can read reviews, but writing one requires a verified email so reviews stay trustworthy.") }
        static var registeredRequiredSubmit: String { String(localized: "Verify your email to suggest a new place") }
        static var registeredRequiredClaim: String { String(localized: "Verify your email to claim ownership") }
    }

    enum Submission {
        static var title: String { String(localized: "Suggest a place") }
        static var intro: String { String(localized: "New places appear on Nanglen only after our team reviews and approves them.") }
        static var searchMaps: String { String(localized: "Search Apple Maps") }
        static var searchMapsPlaceholder: String { String(localized: "Place name in Apple Maps") }
        static var pinHint: String { String(localized: "Move the map so the pin sits on the entrance") }
        static var notOnNanglen: String { String(localized: "From Apple Maps · Not on Nanglen yet") }
        static var alreadyOnNanglen: String { String(localized: "Already on Nanglen") }
        static var name: String { String(localized: "Place name *") }
        static var category: String { String(localized: "Category *") }
        static var address: String { String(localized: "Address *") }
        static var description: String { String(localized: "Why do you recommend it? (optional)") }
        static var website: String { String(localized: "Website or social (https://…)") }
        static var phone: String { String(localized: "Contact phone (optional)") }
        static var note: String { String(localized: "Note to the team (optional)") }
        static var photos: String { String(localized: "Photos (up to 5)") }
        static var submit: String { String(localized: "Submit for review") }
        static var resubmit: String { String(localized: "Resubmit for review") }
        static var submitted: String { String(localized: "Submitted · Waiting for review") }
        static var submittedMessage: String { String(localized: "Track the status in Profile › My suggested places") }
        static var alreadyListedTitle: String { String(localized: "This place already exists") }
        static var alreadyListedMessage: String { String(localized: "This place is already on Nanglen. You can open it and write a review.") }
        static var openVenue: String { String(localized: "Open place") }
        static func possibleDuplicates(_ names: String) -> String { String(localized: "Possible duplicate of: \(names). Our team will check.") }
        static var nameRequired: String { String(localized: "Enter a place name") }
        static var categoryRequired: String { String(localized: "Choose a category") }
        static var locationRequired: String { String(localized: "Pin the location on the map") }
        static var invalidWebsite: String { String(localized: "Links must start with https://") }
        static var textTooLong: String { String(localized: "Text is too long") }
        static var useThisPlace: String { String(localized: "Use this place") }
        static var mine: String { String(localized: "My suggested places") }
        static var mineEmpty: String { String(localized: "You haven't suggested any places yet") }
        static var withdraw: String { String(localized: "Withdraw") }
        static var editAndResubmit: String { String(localized: "Edit and resubmit") }
        static var adminFeedback: String { String(localized: "Feedback from our team") }
    }

    enum SubmissionStatusText {
        static var draft: String { String(localized: "Draft") }
        static var pending: String { String(localized: "Waiting for review") }
        static var needsChanges: String { String(localized: "Needs changes") }
        static var approved: String { String(localized: "Approved") }
        static var rejected: String { String(localized: "Rejected") }
        static var duplicate: String { String(localized: "Duplicate") }
        static var withdrawn: String { String(localized: "Withdrawn") }
    }

    enum Claim {
        static var title: String { String(localized: "Verify ownership") }
        static var intro: String { String(localized: "Our team checks your evidence before granting management access. Owners can't edit or delete user reviews.") }
        static var businessName: String { String(localized: "Business name *") }
        static var role: String { String(localized: "Role") }
        static var owner: String { String(localized: "Owner") }
        static var manager: String { String(localized: "Manager") }
        static var editor: String { String(localized: "Editor") }
        static var contact: String { String(localized: "Contact details (optional)") }
        static var evidence: String { String(localized: "Evidence, e.g. business registration number or official page link") }
        static var submit: String { String(localized: "Send request") }
        static var submitted: String { String(localized: "Request sent · Waiting for review") }
        static var myClaims: String { String(localized: "Ownership requests") }
        static var pending: String { String(localized: "Pending review") }
        static var approved: String { String(localized: "Approved") }
        static var rejected: String { String(localized: "Rejected") }
        static var withdrawn: String { String(localized: "Withdrawn") }
    }

    enum Admin {
        static var title: String { String(localized: "Review queue") }
        static var submissions: String { String(localized: "New places") }
        static var claims: String { String(localized: "Ownership claims") }
        static var flagged: String { String(localized: "Reported reviews") }
        static var empty: String { String(localized: "Nothing waiting for review") }
        static var approve: String { String(localized: "Approve") }
        static var reject: String { String(localized: "Reject") }
        static var requestChanges: String { String(localized: "Request changes") }
        static var markDuplicate: String { String(localized: "Duplicate of this place") }
        static var duplicates: String { String(localized: "Nearby places that may be duplicates") }
        static var noDuplicates: String { String(localized: "No nearby duplicates found") }
        static var submitter: String { String(localized: "Submitted by") }
        static func submitterStats(_ name: String, _ approved: Int, _ total: Int) -> String { String(localized: "\(name) · \(approved) of \(total) approved") }
        static var reasonTitle: String { String(localized: "Reason (the submitter will see this)") }
        static var notePlaceholder: String { String(localized: "Note (optional)") }
        static var likelyDuplicate: String { String(localized: "A likely duplicate exists within 50 m. Approve anyway?") }
        static var approveAnyway: String { String(localized: "Approve anyway") }
        static var hide: String { String(localized: "Hide review") }
        static var removeReview: String { String(localized: "Remove review") }
        static var dismiss: String { String(localized: "Dismiss (keep review)") }
        static var done: String { String(localized: "Decision saved") }
        static var history: String { String(localized: "Review history") }
        static func photosCount(_ count: Int) -> String { String(localized: "\(count) photos") }
        static func dupCount(_ count: Int) -> String { String(localized: "\(count) possible duplicates") }
        static func flags(_ count: Int, _ reasons: String) -> String { String(localized: "\(count) reports · \(reasons)") }
    }

    enum Saved {
        static var title: String { String(localized: "Saved") }
        static var emptyTitle: String { String(localized: "No saved places yet") }
        static var emptyMessage: String { String(localized: "Tap ♡ on a place to keep it for later") }
        static var guestNote: String { String(localized: "Saved as a guest · Verify your phone to keep them across devices") }
        static var offline: String { String(localized: "Offline · Showing places saved on this device") }
    }

    enum Profile {
        static var title: String { String(localized: "Profile") }
        static var registered: String { String(localized: "Member · Email verified") }
        static var notVerified: String { String(localized: "Email not verified") }
        static var admin: String { String(localized: "Administrator") }
        static var businessOwner: String { String(localized: "Business owner") }
        static var contributions: String { String(localized: "Contributions") }
        static var savedCount: String { String(localized: "Saved places") }
        static var reviewsCount: String { String(localized: "My reviews") }
        static var addPlace: String { String(localized: "Suggest a new place") }
        static var mySubmissions: String { String(localized: "My suggested places") }
        static var myBusinesses: String { String(localized: "Businesses I manage") }
        static var moderation: String { String(localized: "Team review queue") }
        static var editName: String { String(localized: "Change display name") }
        static var photo: String { String(localized: "Profile photo") }
        static var photoAdd: String { String(localized: "Add photo") }
        static var photoChange: String { String(localized: "Change") }
        static var photoChoose: String { String(localized: "Choose from library") }
        static var photoRemove: String { String(localized: "Remove photo") }
        static var photoUploading: String { String(localized: "Uploading…") }
        static var photoUpdated: String { String(localized: "Profile photo updated") }
        static var photoRemoved: String { String(localized: "Profile photo removed") }
        static var photoUnreadable: String { String(localized: "Couldn't use this photo. Please choose another.") }
        static var settings: String { String(localized: "Settings") }
        static var location: String { String(localized: "Location access") }
        static var locationOn: String { String(localized: "While using the app") }
        static var locationOff: String { String(localized: "Not allowed") }
        static var locationNotAsked: String { String(localized: "Not asked yet") }
        static var clearCache: String { String(localized: "Clear cache") }
        static var clearCacheConfirm: String { String(localized: "Clears places and drafts stored on this device. Nothing on the server is deleted.") }
        static var cacheCleared: String { String(localized: "Cache cleared") }
        static var backend: String { String(localized: "Server") }
        static var demoBackend: String { String(localized: "Demo mode (local data)") }
        static var demoExplain: String { String(localized: "Supabase isn't configured, so the app uses a local mock server. Data isn't shared with other users.") }
        static func demoAdminHint(_ email: String) -> String { String(localized: "Demo (debug builds): verify \(email) to try admin access") }
        static var deleteAccount: String { String(localized: "Delete account") }
        static var deleteAccountConfirm: String { String(localized: "This permanently deletes your account, reviews, saved places, suggestions and uploaded photos. Approved places stay on Nanglen. This can't be undone.") }
        static var accountDeleted: String { String(localized: "Your account was deleted") }
        static var renameRules: String { String(localized: "2–40 characters. Names like \"Admin\" or \"Nanglen\" are reserved.") }
        static var signOut: String { String(localized: "Sign out") }
        static var signOutConfirm: String { String(localized: "Signing out makes you a new guest. Your account stays on the server; sign in again with the same email to get it back.") }
        static var version: String { String(localized: "Version") }
        static var privacy: String { String(localized: "We use your location only when searching and verifying a visit. We don't store your travel history.") }
    }

    enum Errors {
        static func message(for error: BackendError) -> String {
            switch error {
            case .notConfigured: String(localized: "The server isn't configured")
            case .notAuthenticated: String(localized: "Your session expired. Try reopening the app.")
            case .registrationRequired: L10n.Account.registeredRequiredTitle
            case .adminRequired: String(localized: "Administrator access required")
            case .rateLimited: String(localized: "Too many requests. Try again later.")
            case .notFound: String(localized: "Not found. It may have been removed or changed.")
            case .venueNotReviewable: String(localized: "This place can't be reviewed yet")
            case .challengeExpired, .challengeConsumed, .verificationConsumed, .verificationExpired, .verificationInvalid:
                L10n.Review.reverify
            case .invalidInput(let code): inputMessage(code)
            case .invalidStatusTransition: String(localized: "The status has changed. Refresh and try again.")
            case .likelyDuplicate: L10n.Admin.likelyDuplicate
            case .providerRefExists: String(localized: "This Apple Maps place is already linked. Mark it as a duplicate instead.")
            case .reviewRemoved: String(localized: "Your review for this place was removed by our team")
            case .accountExists: String(localized: "This email already has an account. Sign in to it instead.")
            case .deletionBlocked: String(localized: "Administrator accounts can't be deleted in the app. Ask another admin to remove your access first.")
            case .invalidOTP: String(localized: "The code is incorrect or expired")
            case .emailNotSent: String(localized: "We couldn't send the code email right now. Please try again in a few minutes.")
            case .network: String(localized: "Can't connect to the internet")
            case .server: L10n.Common.somethingWentWrong
            }
        }

        static func inputMessage(_ code: String) -> String {
            switch code {
            case "invalid_rating": L10n.Review.ratingRequired
            case "too_many_tags": L10n.Review.tooManyTags
            case "body_too_long": String(localized: "Comment is longer than 500 characters")
            case "name_required": L10n.Submission.nameRequired
            case "category_required": L10n.Submission.categoryRequired
            case "invalid_coordinate": L10n.Submission.locationRequired
            case "invalid_website_url": L10n.Submission.invalidWebsite
            case "reason_required": String(localized: "Please give a reason")
            case "invalid_email": L10n.Account.invalidEmail
            case "reserved_display_name": String(localized: "That name is reserved. Please choose another.")
            case "invalid_display_name": L10n.Profile.renameRules
            case "claim_already_pending": String(localized: "You already have a pending request for this place")
            case "cannot_flag_own_review": String(localized: "You can't report your own review")
            case "file_too_large": String(localized: "File is larger than 5 MB")
            case "too_many_photos": String(localized: "Too many photos")
            default: L10n.Common.somethingWentWrong
            }
        }

        static func message(for error: Error) -> String {
            if let backend = error as? BackendError { return message(for: backend) }
            if error is URLError { return message(for: BackendError.network) }
            return L10n.Common.somethingWentWrong
        }
    }
}
