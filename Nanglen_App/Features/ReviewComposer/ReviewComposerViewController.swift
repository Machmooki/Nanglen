import UIKit

/// Review composer (Storyboard scene `ReviewComposerViewController`, presented in a navigation sheet).
final class ReviewComposerViewController: UIViewController {
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var venueNameLabel: UILabel!
    @IBOutlet private weak var verificationView: VerificationStatusView!
    @IBOutlet private weak var formStackView: UIStackView!
    @IBOutlet private weak var ratingTitleLabel: UILabel!
    @IBOutlet private weak var ratingControl: StarRatingControl!
    @IBOutlet private weak var purposeTitleLabel: UILabel!
    @IBOutlet private weak var purposeChips: ChipGroupView!
    @IBOutlet private weak var tagsTitleLabel: UILabel!
    @IBOutlet private weak var tagsChips: ChipGroupView!
    @IBOutlet private weak var commentTitleLabel: UILabel!
    @IBOutlet private weak var commentTextView: UITextView!
    @IBOutlet private weak var commentCountLabel: UILabel!
    @IBOutlet private weak var photosTitleLabel: UILabel!
    @IBOutlet private weak var photoStrip: PhotoStripView!
    @IBOutlet private weak var noticeLabel: UILabel!
    @IBOutlet private weak var submitButton: UIButton!

    private var viewModel: ReviewComposerViewModel?
    private weak var container: AppContainer?
    private let placeholderLabel = UILabel()
    private let photoPicker = PhotoSourcePicker()
    private var keyboard: FormKeyboardHandler?

    func configure(viewModel: ReviewComposerViewModel, container: AppContainer) {
        self.viewModel = viewModel
        self.container = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let viewModel else {
            assertionFailure("ReviewComposerViewController needs configure(viewModel:container:)")
            return
        }
        setUpAppearance(viewModel)
        viewModel.onChange = { [weak self] state in self?.render(state) }
        viewModel.onOutcome = { [weak self] outcome in self?.handle(outcome) }
        render(viewModel.state)
        viewModel.start()
        isModalInPresentation = true
    }

    private func setUpAppearance(_ viewModel: ReviewComposerViewModel) {
        view.backgroundColor = AppColors.background
        title = viewModel.existing == nil ? L10n.Review.title : L10n.Detail.updateReview
        venueNameLabel.apply(AppTypography.title3)
        venueNameLabel.text = viewModel.venue.name
        [ratingTitleLabel, purposeTitleLabel, tagsTitleLabel, commentTitleLabel, photosTitleLabel].forEach { AppStyles.sectionTitle($0) }
        ratingTitleLabel.text = L10n.Review.rating
        purposeTitleLabel.text = L10n.Review.purpose + " · " + L10n.Common.optional
        tagsTitleLabel.text = L10n.Review.tags
        commentTitleLabel.text = L10n.Review.comment + " · " + L10n.Common.optional
        photosTitleLabel.text = L10n.Review.photos(viewModel.configuration.reviewMaxPhotos)

        verificationView.onAction = { [weak self] action in self?.handle(action) }
        purposeChips.allowsMultipleSelection = false
        purposeChips.configure(items: VisitPurpose.allCases.map { .init(id: $0.rawValue, title: $0.title, symbol: $0.symbol) },
                               selection: Set([viewModel.state.draft.purpose?.rawValue].compactMap { $0 }))
        purposeChips.onChange = { [weak self] selection in self?.viewModel?.setPurpose(selection.first) }
        // No "pick up to N" rule for reviewers: the limit equals the catalog size (server setting review_max_tags).
        let maxTags = viewModel.configuration.reviewMaxTags
        tagsChips.maximumSelection = maxTags >= ReviewTag.catalog.count ? nil : maxTags
        tagsChips.configure(items: ReviewTag.catalog.map { .init(id: $0.slug, title: $0.title, symbol: $0.symbol) },
                            selection: Set(viewModel.state.draft.tags))
        tagsChips.onChange = { [weak self] selection in self?.viewModel?.setTags(selection) }

        commentTextView.font = AppTypography.body
        commentTextView.adjustsFontForContentSizeCategory = true
        commentTextView.backgroundColor = AppColors.card
        commentTextView.layer.cornerRadius = AppRadius.control
        commentTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        commentTextView.delegate = self
        commentTextView.text = viewModel.state.draft.body
        commentTextView.accessibilityLabel = L10n.Review.comment
        placeholderLabel.apply(AppTypography.body, color: AppColors.textTertiary)
        placeholderLabel.text = L10n.Review.commentPlaceholder
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        commentTextView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: commentTextView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: commentTextView.leadingAnchor, constant: 13),
            placeholderLabel.widthAnchor.constraint(equalTo: commentTextView.widthAnchor, constant: -26),
        ])
        commentCountLabel.apply(AppTypography.caption, color: AppColors.textTertiary)
        noticeLabel.apply(AppTypography.footnote, color: AppColors.warning)

        photoStrip.maximumCount = viewModel.configuration.reviewMaxPhotos
        photoStrip.onAdd = { [weak self] in self?.pickPhoto() }
        photoStrip.onRemove = { [weak self] index in self?.viewModel?.removePhoto(at: index) }
        ratingControl.setValue(viewModel.state.draft.rating ?? 0)
        submitButton.accessibilityIdentifier = "composer.submit"
        keyboard = FormKeyboardHandler(scrollView: scrollView, rootView: view)
        keyboard?.manage([commentTextView])
    }

    private func render(_ state: ReviewComposerViewModel.State) {
        guard let viewModel else { return }
        verificationView.render(state.verification)
        formStackView.alpha = state.canEdit ? 1 : 0.45
        formStackView.isUserInteractionEnabled = state.canEdit
        if ratingControl.value != (state.draft.rating ?? 0) { ratingControl.setValue(state.draft.rating ?? 0) }
        if commentTextView.text != state.draft.body { commentTextView.text = state.draft.body }
        placeholderLabel.isHidden = !state.draft.body.isEmpty
        commentCountLabel.text = L10n.Review.characters(state.draft.body.count, viewModel.configuration.reviewMaxBodyLength)
        photoStrip.setImages(state.photos)
        noticeLabel.text = state.notice
        noticeLabel.isHidden = state.notice == nil
        AppStyles.primaryButton(submitButton, title: state.isSubmitting ? L10n.Review.submitting : L10n.Review.submit, systemImage: "paperplane.fill")
        submitButton.isEnabled = viewModel.canSubmit
        submitButton.configuration?.showsActivityIndicator = state.isSubmitting
    }

    private func handle(_ action: VerificationStatusView.Action) {
        switch action {
        case .retry:
            viewModel?.verify()
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .verifyEmail:
            presentSignIn()
        }
    }

    private func handle(_ outcome: ReviewComposerViewModel.Outcome) {
        switch outcome {
        case .published(let message):
            AppComponents.successHaptic()
            let presenter = presentingViewController
            dismiss(animated: true) { presenter?.showToast(message) }
        case .needsRegistration:
            presentSignIn()
        }
    }

    private func presentSignIn() {
        guard let container,
              let navigation = storyboard?.instantiateViewController(withIdentifier: "SignInNavigationController") as? UINavigationController,
              let phone = navigation.topViewController as? SignInViewController else { return }
        phone.configure(viewModel: container.makeSignInViewModel(), isDemo: container.isDemo) { [weak self] in
            self?.viewModel?.verify()
        }
        present(navigation, animated: true)
    }

    private func pickPhoto() {
        guard let viewModel else { return }
        view.endEditing(true)
        photoPicker.present(from: self, sourceView: photoStrip.addButton, limit: viewModel.remainingPhotoSlots) { [weak self] images in
            self?.viewModel?.addPhotos(images)
        }
    }

    // MARK: Actions

    @IBAction private func ratingChanged(_ sender: StarRatingControl) {
        viewModel?.setRating(sender.value)
    }

    @IBAction private func submitTapped(_ sender: UIButton) {
        view.endEditing(true)
        viewModel?.submit()
    }

    @IBAction private func cancelTapped(_ sender: Any) {
        viewModel?.cancel()
        dismiss(animated: true)
    }
}

extension ReviewComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        viewModel?.setBody(textView.text)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text as NSString
        return current.replacingCharacters(in: range, with: text).count <= (viewModel?.configuration.reviewMaxBodyLength ?? 500)
    }
}
