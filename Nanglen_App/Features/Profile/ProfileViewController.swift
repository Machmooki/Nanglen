import PhotosUI
import UIKit

/// Profile (Storyboard `ProfileViewController`, a table view controller with prototype cells).
/// Business/Admin rows appear only when the backend says so; the backend still enforces every action.
final class ProfileViewController: UITableViewController, AppContainerConfigurable {
    private enum Segue {
        static let presentSignIn = "presentSignIn"
        static let presentAddPlace = "presentAddPlace"
        static let showMySubmissions = "showMySubmissions"
        static let showAdminQueue = "showAdminQueue"
    }

    private enum Row: Equatable {
        case header
        case verifyEmail, photo, editName
        case saved, reviews, addPlace, mySubmissions
        case business(BusinessMembership)
        case claim(VenueClaim)
        case moderation
        case location, backend, clearCache, signOut, deleteAccount, version
    }

    private struct Section {
        var title: String?
        var footer: String?
        var rows: [Row]
    }

    private var container: AppContainer?
    private var viewModel: ProfileViewModel?
    private var state = ProfileViewModel.State()
    private var sections: [Section] = []

    func configure(with container: AppContainer) {
        self.container = container
        viewModel = container.makeProfileViewModel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.Profile.title
        navigationItem.backButtonDisplayMode = .minimal
        tableView.backgroundColor = AppColors.background
        viewModel?.onChange = { [weak self] state in
            self?.state = state
            self?.rebuild()
        }
        viewModel?.onMessage = { [weak self] message in self?.showToast(message) }
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await viewModel?.load() }
    }

    private func rebuild() {
        let caps = state.capabilities
        var result: [Section] = [Section(rows: [.header])]
        if caps?.isRegistered == true {
            result.append(Section(rows: [.photo, .editName]))
        } else {
            result.append(Section(footer: L10n.Account.guestMessage, rows: [.verifyEmail]))
        }
        result.append(Section(title: L10n.Profile.contributions, rows: [.saved, .reviews, .addPlace, .mySubmissions]))
        if let memberships = caps?.memberships, !memberships.isEmpty || !state.claims.isEmpty {
            result.append(Section(title: L10n.Profile.myBusinesses, rows: memberships.map(Row.business) + state.claims.map(Row.claim)))
        } else if !state.claims.isEmpty {
            result.append(Section(title: L10n.Claim.myClaims, rows: state.claims.map(Row.claim)))
        }
        if caps?.isAdmin == true {
            result.append(Section(title: L10n.Profile.admin, rows: [.moderation]))
        }
        var settings: [Row] = [.location, .backend, .clearCache]
        if caps?.isRegistered == true { settings += [.signOut, .deleteAccount] }
        settings.append(.version)
        let footer = [state.mode == .demo ? L10n.Profile.demoExplain : nil, L10n.Profile.privacy].compactMap { $0 }.joined(separator: "\n\n")
        result.append(Section(title: L10n.Profile.settings, footer: footer, rows: settings))
        sections = result
        tableView.reloadData()
    }

    // MARK: Data source

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        if row == .header {
            let cell = tableView.dequeueReusableCell(withIdentifier: ProfileHeaderCell.reuseIdentifier, for: indexPath)
            let header = cell as? ProfileHeaderCell
            header?.configure(capabilities: state.capabilities, isDemo: state.mode == .demo,
                              avatarURL: state.avatarURL, isUploading: state.isUploadingPhoto)
            header?.onAvatarTap = { [weak self, weak cell] in
                guard let self, let cell, state.capabilities?.isRegistered == true else { return }
                presentPhotoOptions(from: cell)
            }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileValueCell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        var accessory: UITableViewCell.AccessoryType = .none
        var tint = AppColors.primary
        let caps = state.capabilities
        switch row {
        case .header: break
        case .verifyEmail:
            content = .subtitleCell()
            content.text = L10n.Account.verifyEmail
            content.secondaryText = L10n.Account.verifyEmailShort
            content.image = UIImage(systemName: "envelope.badge.shield.half.filled")
            accessory = .disclosureIndicator
        case .photo:
            content.text = L10n.Profile.photo
            content.secondaryText = state.isUploadingPhoto ? L10n.Profile.photoUploading
                : (state.capabilities?.avatarPath == nil ? L10n.Profile.photoAdd : L10n.Profile.photoChange)
            content.image = UIImage(systemName: "person.crop.circle")
            accessory = .disclosureIndicator
        case .editName:
            content.text = L10n.Profile.editName
            content.secondaryText = caps?.displayName
            content.image = UIImage(systemName: "pencil")
        case .saved:
            content.text = L10n.Profile.savedCount
            content.secondaryText = "\(caps?.favoritesCount ?? 0)"
            content.image = UIImage(systemName: "heart")
        case .reviews:
            content.text = L10n.Profile.reviewsCount
            content.secondaryText = "\(caps?.reviewsCount ?? 0)"
            content.image = UIImage(systemName: "star.bubble")
        case .addPlace:
            content.text = L10n.Profile.addPlace
            content.image = UIImage(systemName: "plus.circle")
            accessory = .disclosureIndicator
        case .mySubmissions:
            content.text = L10n.Profile.mySubmissions
            content.secondaryText = (caps?.openSubmissionsCount ?? 0) > 0 ? L10n.SubmissionStatusText.pending + " \(caps?.openSubmissionsCount ?? 0)" : nil
            content.image = UIImage(systemName: "tray.full")
            accessory = .disclosureIndicator
        case .business(let membership):
            content = .subtitleCell()
            content.text = membership.businessName
            content.secondaryText = (ClaimantRole(rawValue: membership.role)?.title ?? membership.role) + " · \(membership.venueIDs.count)"
            content.image = UIImage(systemName: "building.2.fill")
        case .claim(let claim):
            content = .subtitleCell()
            content.text = claim.businessName
            content.secondaryText = [claim.status.title, claim.decisionReason].compactMap { $0 }.joined(separator: " · ")
            content.image = UIImage(systemName: "building.2")
            tint = claim.status.tone.foreground
        case .moderation:
            content.text = L10n.Profile.moderation
            content.image = UIImage(systemName: "checkmark.shield")
            accessory = .disclosureIndicator
        case .location:
            content.text = L10n.Profile.location
            content.secondaryText = switch state.location {
            case .authorized: L10n.Profile.locationOn
            case .notDetermined: L10n.Profile.locationNotAsked
            default: L10n.Profile.locationOff
            }
            content.image = UIImage(systemName: "location")
            accessory = state.location == .notDetermined ? .none : .disclosureIndicator
        case .backend:
            content.text = L10n.Profile.backend
            content.secondaryText = switch state.mode {
            case .demo: L10n.Profile.demoBackend
            case .supabase(let host): host
            }
            content.image = UIImage(systemName: "server.rack")
            if state.mode == .demo { tint = AppColors.warning }
        case .clearCache:
            content.text = L10n.Profile.clearCache
            content.image = UIImage(systemName: "trash")
        case .deleteAccount:
            content.text = L10n.Profile.deleteAccount
            content.image = UIImage(systemName: "person.crop.circle.badge.xmark")
            tint = AppColors.bad
            content.textProperties.color = AppColors.bad
        case .signOut:
            content.text = L10n.Profile.signOut
            content.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
            tint = AppColors.bad
            content.textProperties.color = AppColors.bad
        case .version:
            content.text = L10n.Profile.version
            let info = Bundle.main.infoDictionary
            content.secondaryText = "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
            content.image = UIImage(systemName: "info.circle")
        }
        content.imageProperties.tintColor = tint
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryType = accessory
        cell.selectionStyle = [.saved, .reviews, .version, .backend].contains(row) ? .none : .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .verifyEmail: performSegue(withIdentifier: Segue.presentSignIn, sender: self)
        case .addPlace: performSegue(withIdentifier: Segue.presentAddPlace, sender: self)
        case .mySubmissions: performSegue(withIdentifier: Segue.showMySubmissions, sender: self)
        case .moderation: performSegue(withIdentifier: Segue.showAdminQueue, sender: self)
        case .editName: promptDisplayName()
        case .photo:
            if let cell = tableView.cellForRow(at: indexPath) { presentPhotoOptions(from: cell) }
        case .location:
            if state.location != .notDetermined, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .clearCache:
            confirm(title: L10n.Profile.clearCache, message: L10n.Profile.clearCacheConfirm, action: L10n.Profile.clearCache) { [weak self] in self?.viewModel?.clearCache() }
        case .deleteAccount:
            confirm(title: L10n.Profile.deleteAccount, message: L10n.Profile.deleteAccountConfirm, action: L10n.Profile.deleteAccount) { [weak self] in
                self?.viewModel?.deleteAccount()
            }
        case .signOut:
            confirm(title: L10n.Profile.signOut, message: L10n.Profile.signOutConfirm, action: L10n.Profile.signOut) { [weak self] in self?.viewModel?.signOut() }
        default: break
        }
    }

    // MARK: Profile photo

    private func presentPhotoOptions(from sourceView: UIView) {
        guard !state.isUploadingPhoto else { return }
        let hasPhoto = state.capabilities?.avatarPath != nil
        let sheet = UIAlertController(title: L10n.Profile.photo, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.Profile.photoChoose, style: .default) { [weak self] _ in self?.pickProfilePhoto() })
        if hasPhoto {
            sheet.addAction(UIAlertAction(title: L10n.Profile.photoRemove, style: .destructive) { [weak self] _ in
                self?.viewModel?.setProfilePhoto(nil)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = sourceView
        sheet.popoverPresentationController?.sourceRect = sourceView.bounds
        present(sheet, animated: true)
    }

    private func pickProfilePhoto() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func promptDisplayName() {
        let alert = UIAlertController(title: L10n.Profile.editName, message: L10n.Profile.renameRules, preferredStyle: .alert)
        alert.addTextField { [weak self] field in
            field.text = self?.state.capabilities?.displayName
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.save, style: .default) { [weak self, weak alert] _ in
            self?.viewModel?.updateDisplayName(alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func confirm(title: String, message: String, action: String, handler: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: .destructive) { _ in handler() })
        present(alert, animated: true)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let container else { return }
        switch segue.identifier {
        case Segue.presentSignIn:
            ((segue.destination as? UINavigationController)?.topViewController as? SignInViewController)?
                .configure(viewModel: container.makeSignInViewModel(), isDemo: container.isDemo)
        case Segue.presentAddPlace:
            ((segue.destination as? UINavigationController)?.topViewController as? AddPlaceViewController)?
                .configure(viewModel: container.makeAddPlaceViewModel(), container: container)
        case Segue.showMySubmissions:
            (segue.destination as? MySubmissionsViewController)?.configure(viewModel: container.makeMySubmissionsViewModel(), container: container)
        case Segue.showAdminQueue:
            (segue.destination as? AdminQueueViewController)?.configure(viewModel: container.makeAdminQueueViewModel(), container: container)
        default: break
        }
    }
}

/// Prototype cell in Main.storyboard (Profile header).
final class ProfileHeaderCell: UITableViewCell {
    static let reuseIdentifier = "ProfileHeaderCell"

    @IBOutlet private weak var avatarView: UIView!
    @IBOutlet private weak var avatarImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var identifierLabel: UILabel!
    @IBOutlet private weak var sinceLabel: UILabel!

    var onAvatarTap: (() -> Void)?
    private let photoView = RemoteImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let cameraBadge = UIImageView(image: UIImage(systemName: "camera.circle.fill"))

    // UIView declares awakeFromNib nonisolated; nibs always load on the main thread.
    nonisolated override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { setUp() }
    }

    private func setUp() {
        selectionStyle = .none
        avatarView.backgroundColor = AppColors.primarySoft
        avatarView.layer.cornerRadius = 32
        avatarImageView.tintColor = AppColors.primary
        avatarImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        nameLabel.apply(AppTypography.title)
        identifierLabel.apply(AppTypography.subheadlineEmphasized, color: AppColors.primary)
        sinceLabel.apply(AppTypography.footnote, color: AppColors.textTertiary)

        // Profile photo sits on top of the symbol; the badge hints that the avatar is tappable.
        avatarView.clipsToBounds = true
        photoView.layer.cornerRadius = 0
        photoView.isHidden = true
        spinner.color = .white
        spinner.hidesWhenStopped = true
        cameraBadge.tintColor = AppColors.primary
        cameraBadge.backgroundColor = AppColors.card
        cameraBadge.layer.cornerRadius = 12
        cameraBadge.clipsToBounds = true
        cameraBadge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        cameraBadge.isHidden = true
        [photoView, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            avatarView.addSubview($0)
        }
        cameraBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cameraBadge)
        NSLayoutConstraint.activate([
            photoView.topAnchor.constraint(equalTo: avatarView.topAnchor),
            photoView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),
            photoView.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor),
            photoView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            cameraBadge.widthAnchor.constraint(equalToConstant: 24),
            cameraBadge.heightAnchor.constraint(equalToConstant: 24),
            cameraBadge.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 2),
            cameraBadge.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 2),
        ])
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))
    }

    @objc private func avatarTapped() {
        onAvatarTap?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarView.layer.cornerRadius = avatarView.bounds.height / 2
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAvatarTap = nil
    }

    func configure(capabilities: UserCapabilities?, isDemo: Bool, avatarURL: URL? = nil, isUploading: Bool = false) {
        let caps = capabilities
        photoView.isHidden = avatarURL == nil
        photoView.load(avatarURL, maxPixelSize: 512)
        if isUploading { spinner.startAnimating() } else { spinner.stopAnimating() }
        photoView.alpha = isUploading ? 0.5 : 1
        cameraBadge.isHidden = caps?.isRegistered != true
        nameLabel.text = caps?.isRegistered == true ? caps?.displayName : L10n.Account.guestTitle
        var roles: [String] = [caps?.isRegistered == true ? L10n.Profile.registered : L10n.Profile.notVerified]
        if caps?.isBusinessOwner == true { roles.append(L10n.Profile.businessOwner) }
        if caps?.isAdmin == true { roles.append(L10n.Profile.admin) }
        identifierLabel.text = roles.joined(separator: " · ")
        identifierLabel.textColor = caps?.isRegistered == true ? AppColors.good : AppColors.textSecondary
        avatarImageView.image = UIImage(systemName: caps?.isAdmin == true ? "checkmark.shield.fill" : caps?.isRegistered == true ? "person.fill.checkmark" : "person.fill")
        sinceLabel.text = [caps?.contactHint, isDemo ? "⚠︎ " + L10n.Common.demoBadge : nil].compactMap { $0 }.joined(separator: " · ")
        sinceLabel.isHidden = sinceLabel.text?.isEmpty ?? true
        accessibilityLabel = [nameLabel.text, identifierLabel.text, sinceLabel.text].compactMap { $0 }.joined(separator: ", ")
        avatarView.isAccessibilityElement = caps?.isRegistered == true
        avatarView.accessibilityLabel = L10n.Profile.photo
        avatarView.accessibilityTraits = .button
    }
}

extension ProfileViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor in self?.viewModel?.setProfilePhoto(image) }
        }
    }
}
