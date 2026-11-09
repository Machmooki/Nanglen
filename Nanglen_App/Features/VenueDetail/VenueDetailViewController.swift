import MapKit
import UIKit

/// Venue detail (Storyboard scene `VenueDetailViewController`). Fixed layout lives in the storyboard;
/// review cards, tag pills and info rows are added at runtime.
final class VenueDetailViewController: UIViewController {
    private enum Segue {
        static let presentReviewComposer = "presentReviewComposer"
        static let presentPhoneLink = "presentPhoneLink"
        static let presentClaim = "presentClaim"
    }

    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var heroMapView: MKMapView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var metaLabel: UILabel!
    @IBOutlet private weak var ratingLabel: UILabel!
    @IBOutlet private weak var addressLabel: UILabel!
    @IBOutlet private weak var directionsButton: UIButton!
    @IBOutlet private weak var writeReviewButton: UIButton!
    @IBOutlet private weak var myReviewLabel: UILabel!
    @IBOutlet private weak var galleryStackView: UIStackView!
    @IBOutlet private weak var tagsTitleLabel: UILabel!
    @IBOutlet private weak var tagsNoteLabel: UILabel!
    @IBOutlet private weak var tagsView: TagPillsView!
    @IBOutlet private weak var reviewsTitleLabel: UILabel!
    @IBOutlet private weak var reviewSortControl: UISegmentedControl!
    @IBOutlet private weak var reviewsStackView: UIStackView!
    @IBOutlet private weak var emptyReviewsLabel: UILabel!
    @IBOutlet private weak var loadMoreReviewsButton: UIButton!
    @IBOutlet private weak var infoTitleLabel: UILabel!
    @IBOutlet private weak var infoStackView: UIStackView!
    @IBOutlet private weak var sourceLabel: UILabel!
    @IBOutlet private weak var claimButton: UIButton!
    @IBOutlet private weak var favoriteBarButton: UIBarButtonItem!

    private var viewModel: VenueDetailViewModel?
    private weak var container: AppContainer?
    private var renderedReviewIDs: [UUID] = []
    private var renderedMedia: [String: URL] = [:]

    func configure(viewModel: VenueDetailViewModel, container: AppContainer) {
        self.viewModel = viewModel
        self.container = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let viewModel else {
            assertionFailure("VenueDetailViewController needs configure(viewModel:container:)")
            return
        }
        setUpAppearance()
        viewModel.onChange = { [weak self] state in self?.render(state) }
        viewModel.onMessage = { [weak self] message in self?.showToast(message) }
        render(viewModel.state)
        Task { await viewModel.load() }
    }

    private func setUpAppearance() {
        view.backgroundColor = AppColors.background
        navigationItem.largeTitleDisplayMode = .never
        heroMapView.isScrollEnabled = false
        heroMapView.isZoomEnabled = false
        heroMapView.pointOfInterestFilter = .excludingAll
        heroMapView.layer.cornerRadius = AppRadius.card
        heroMapView.layer.cornerCurve = .continuous
        nameLabel.apply(AppTypography.title)
        nameLabel.accessibilityTraits = .header
        metaLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        ratingLabel.apply(AppTypography.headline)
        addressLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        myReviewLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        [tagsTitleLabel, reviewsTitleLabel, infoTitleLabel].forEach { AppStyles.sectionTitle($0) }
        tagsTitleLabel.text = L10n.Detail.communityTags
        tagsNoteLabel.apply(AppTypography.caption, color: AppColors.textTertiary)
        tagsNoteLabel.text = L10n.Detail.communityTagsNote
        reviewsTitleLabel.text = L10n.Detail.reviews
        infoTitleLabel.text = L10n.Detail.info
        emptyReviewsLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        emptyReviewsLabel.text = L10n.Detail.noReviewsMessage
        sourceLabel.apply(AppTypography.caption, color: AppColors.textTertiary)
        reviewSortControl.removeAllSegments()
        reviewSortControl.insertSegment(withTitle: L10n.Detail.sortRelevant, at: 0, animated: false)
        reviewSortControl.insertSegment(withTitle: L10n.Detail.sortRecent, at: 1, animated: false)
        reviewSortControl.selectedSegmentIndex = 0
        AppStyles.segmentedControl(reviewSortControl)
        AppStyles.secondaryButton(directionsButton, title: L10n.Common.directions, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
        var more = UIButton.Configuration.plain()
        more.title = L10n.Explore.loadMore
        loadMoreReviewsButton.configuration = more
        var claim = UIButton.Configuration.plain()
        claim.title = L10n.Detail.claim
        claim.image = UIImage(systemName: "building.2")
        claim.imagePadding = AppSpacing.xs
        claim.baseForegroundColor = AppColors.textSecondary
        claimButton.configuration = claim
        writeReviewButton.accessibilityIdentifier = "detail.writeReview"
        favoriteBarButton.accessibilityIdentifier = "detail.favorite"
    }

    // MARK: Rendering

    private func render(_ state: VenueDetailViewModel.State) {
        let venue = state.venue
        title = nil
        nameLabel.text = venue.name
        metaLabel.text = [venue.metaText, venue.statusNote].compactMap { $0 }.joined(separator: " · ")
        ratingLabel.text = venue.rating.hasReviews ? "★ " + venue.rating.displayText : venue.rating.displayText
        ratingLabel.textColor = venue.rating.hasReviews ? AppColors.textPrimary : AppColors.textSecondary
        ratingLabel.accessibilityLabel = venue.rating.accessibilityText
        addressLabel.text = venue.address
        addressLabel.isHidden = venue.address == nil
        updateMap(venue)

        favoriteBarButton.image = UIImage(systemName: state.isFavorite ? "heart.fill" : "heart")
        favoriteBarButton.tintColor = state.isFavorite ? AppColors.bad : AppColors.primary
        favoriteBarButton.accessibilityLabel = state.isFavorite ? L10n.Detail.unsave : L10n.Detail.save

        let hasReview = state.myReview != nil
        AppStyles.primaryButton(writeReviewButton, title: hasReview ? L10n.Detail.updateReview : L10n.Detail.writeReview, systemImage: "square.and.pencil")
        writeReviewButton.isEnabled = state.acceptsReviews
        if let mine = state.myReview {
            myReviewLabel.text = mine.status == .published
                ? L10n.Detail.myReviewSummary(mine.rating, Formatters.relative(mine.updatedAt)) + " · " + L10n.Detail.revisitHint
                : L10n.Detail.myReviewHidden
            myReviewLabel.isHidden = false
        } else {
            myReviewLabel.isHidden = true
        }

        renderGallery(state)
        let tags = state.detail?.tagCounts ?? []
        tagsView.configure(tags.prefix(8).map { ReviewTag.pill(for: $0.slug, count: $0.count) })
        [tagsTitleLabel, tagsNoteLabel, tagsView].forEach { $0?.isHidden = tags.isEmpty }

        renderReviews(state)
        renderInfo(state)
        claimButton.isHidden = !(viewModel?.canClaim ?? false)
        if state.detail?.isManagedByMe == true {
            sourceLabel.text = [sourceLabel.text, L10n.Detail.managedByYou].compactMap { $0 }.joined(separator: "\n")
        }
        if let error = state.errorMessage, state.detail == nil {
            emptyReviewsLabel.text = error
            emptyReviewsLabel.isHidden = false
        }
    }

    private var mapVenueID: UUID?

    private func updateMap(_ venue: VenueSummary) {
        guard mapVenueID != venue.id else { return }
        mapVenueID = venue.id
        let coordinate = CLLocationCoordinate2D(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
        heroMapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500), animated: false)
        heroMapView.removeAnnotations(heroMapView.annotations)
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title = venue.name
        heroMapView.addAnnotation(pin)
    }

    private func renderGallery(_ state: VenueDetailViewModel.State) {
        let urls = viewModel?.photoURLs(for: state.detail?.photoPaths ?? []) ?? []
        AppComponents.replaceArrangedSubviews(of: galleryStackView, with: urls.prefix(3).map { url in
            let imageView = RemoteImageView()
            imageView.load(url)
            imageView.heightAnchor.constraint(equalToConstant: 110).isActive = true
            return imageView
        })
        galleryStackView.isHidden = urls.isEmpty
    }

    private func renderReviews(_ state: VenueDetailViewModel.State) {
        let ids = state.reviews.map(\.id)
        if ids != renderedReviewIDs || state.mediaURLs != renderedMedia {
            renderedReviewIDs = ids
            renderedMedia = state.mediaURLs
            AppComponents.replaceArrangedSubviews(of: reviewsStackView, with: state.reviews.map { review in
                let card = ReviewCardView()
                card.configure(review, photoURLs: viewModel?.photoURLs(for: review.photoPaths) ?? [])
                card.onReport = { [weak self] in self?.presentReport(for: review) }
                return card
            })
        }
        reviewsStackView.isHidden = state.reviews.isEmpty
        emptyReviewsLabel.isHidden = !state.reviews.isEmpty || state.isLoading
        emptyReviewsLabel.text = L10n.Detail.noReviewsMessage
        reviewSortControl.isHidden = state.reviews.count < 2
        loadMoreReviewsButton.isHidden = !state.hasMoreReviews
    }

    private func renderInfo(_ state: VenueDetailViewModel.State) {
        var rows: [UIView] = []
        if let address = state.venue.address { rows.append(infoRow(symbol: "mappin.and.ellipse", title: L10n.Detail.address, value: address)) }
        if let description = state.detail?.description { rows.append(infoRow(symbol: "text.quote", title: nil, value: description)) }
        // Official details are only shown when their source is known.
        if state.detail?.detailsSource != nil {
            if let url = state.detail?.websiteURL { rows.append(linkRow(symbol: "safari", title: L10n.Detail.website, value: url.host ?? url.absoluteString, url: url)) }
            if let phone = state.detail?.phoneNumber, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                rows.append(linkRow(symbol: "phone", title: L10n.Detail.phone, value: phone, url: url))
            }
        }
        AppComponents.replaceArrangedSubviews(of: infoStackView, with: rows)
        infoTitleLabel.isHidden = rows.isEmpty
        sourceLabel.text = switch state.detail?.detailsSource {
        case "business_verified": L10n.Detail.sourceBusiness
        case "admin_curated": L10n.Detail.sourceCurated
        case "community_submission": L10n.Detail.sourceCommunity
        default: nil
        }
        sourceLabel.isHidden = sourceLabel.text == nil
    }

    private func infoRow(symbol: String, title: String?, value: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = AppColors.primary
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
        let label = UILabel()
        label.apply(AppTypography.subheadline)
        label.numberOfLines = 0
        label.text = value
        label.accessibilityLabel = [title, value].compactMap { $0 }.joined(separator: ": ")
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = AppSpacing.m
        row.alignment = .firstBaseline
        return row
    }

    private func linkRow(symbol: String, title: String, value: String, url: URL) -> UIView {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = value
        config.image = UIImage(systemName: symbol)
        config.imagePadding = AppSpacing.m
        config.contentInsets = .zero
        button.configuration = config
        button.contentHorizontalAlignment = .leading
        button.accessibilityLabel = "\(title): \(value)"
        button.addAction(UIAction { _ in UIApplication.shared.open(url) }, for: .primaryActionTriggered)
        return button
    }

    // MARK: Actions

    @IBAction private func favoriteTapped(_ sender: Any) {
        AppComponents.selectionHaptic()
        viewModel?.toggleFavorite()
    }

    @IBAction private func directionsTapped(_ sender: UIButton) {
        viewModel?.openDirections()
    }

    @IBAction private func writeReviewTapped(_ sender: UIButton) {
        guard let viewModel else { return }
        switch viewModel.writeReviewRoute() {
        case .compose:
            performSegue(withIdentifier: Segue.presentReviewComposer, sender: self)
        case .needsRegistration:
            presentRegistrationPrompt(message: L10n.Account.registeredRequiredReview)
        case .notReviewable:
            showToast(L10n.Errors.message(for: BackendError.venueNotReviewable))
        }
    }

    @IBAction private func reviewSortChanged(_ sender: UISegmentedControl) {
        viewModel?.setSort(sender.selectedSegmentIndex == 0 ? .relevant : .recent)
    }

    @IBAction private func loadMoreReviewsTapped(_ sender: UIButton) {
        viewModel?.loadMoreReviews()
    }

    @IBAction private func claimTapped(_ sender: UIButton) {
        if container?.session.capabilities?.isRegistered == true {
            performSegue(withIdentifier: Segue.presentClaim, sender: self)
        } else {
            presentRegistrationPrompt(message: L10n.Account.registeredRequiredClaim)
        }
    }

    private func presentRegistrationPrompt(message: String) {
        let alert = UIAlertController(title: L10n.Account.registeredRequiredTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Account.linkPhone, style: .default) { [weak self] _ in
            self?.performSegue(withIdentifier: Segue.presentPhoneLink, sender: self)
        })
        present(alert, animated: true)
    }

    private func presentReport(for review: PublishedReview) {
        guard container?.session.capabilities?.isRegistered == true else {
            presentRegistrationPrompt(message: L10n.Account.registeredRequiredReview)
            return
        }
        let sheet = UIAlertController(title: L10n.Detail.report, message: nil, preferredStyle: .actionSheet)
        let reasons: [(FlagReason, String)] = [
            (.spam, String(localized: "สแปมหรือโฆษณา")), (.offensive, String(localized: "ไม่สุภาพหรือสร้างความเกลียดชัง")),
            (.notARealVisit, String(localized: "ไม่น่าจะไปจริง")), (.wrongVenue, String(localized: "รีวิวผิดสถานที่")),
            (.privacy, String(localized: "ละเมิดความเป็นส่วนตัว")), (.other, L10n.Category.other),
        ]
        for (reason, title) in reasons {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in self?.viewModel?.report(reviewID: review.id, reason: reason) })
        }
        sheet.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }

    // MARK: Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let container, let viewModel,
              let navigation = segue.destination as? UINavigationController else { return }
        switch segue.identifier {
        case Segue.presentReviewComposer:
            (navigation.topViewController as? ReviewComposerViewController)?.configure(
                viewModel: container.makeReviewComposerViewModel(venue: viewModel.state.venue, existing: viewModel.state.myReview),
                container: container)
        case Segue.presentPhoneLink:
            (navigation.topViewController as? PhoneLinkViewController)?.configure(viewModel: container.makePhoneLinkViewModel(), isDemo: container.isDemo)
        case Segue.presentClaim:
            (navigation.topViewController as? ClaimVenueViewController)?.configure(viewModel: container.makeClaimViewModel(venue: viewModel.state.venue))
        default:
            break
        }
    }
}

extension UIViewController {
    /// Lightweight confirmation banner (auto-dismissing alert keeps the UI simple and accessible).
    func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        UIAccessibility.post(notification: .announcement, argument: message)
        Task { @MainActor [weak alert] in
            try? await Task.sleep(for: .seconds(1.6))
            alert?.dismiss(animated: true)
        }
    }
}
