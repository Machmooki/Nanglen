import UIKit

/// Profile (Storyboard `ProfileViewController`, a table view controller with prototype cells).
/// Business/Admin rows appear only when the backend says so; the backend still enforces every action.
final class ProfileViewController: UITableViewController, AppContainerConfigurable {
    private enum Segue {
        static let presentPhoneLink = "presentPhoneLink"
        static let presentAddPlace = "presentAddPlace"
        static let showMySubmissions = "showMySubmissions"
        static let showAdminQueue = "showAdminQueue"
    }

    private enum Row: Equatable {
        case header
        case linkPhone, editName
        case saved, reviews, addPlace, mySubmissions
        case business(BusinessMembership)
        case claim(VenueClaim)
        case moderation
        case location, backend, clearCache, signOut, version
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
            result.append(Section(rows: [.editName]))
        } else {
            result.append(Section(footer: L10n.Account.guestMessage, rows: [.linkPhone]))
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
        if caps?.isRegistered == true { settings.append(.signOut) }
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
            (cell as? ProfileHeaderCell)?.configure(capabilities: state.capabilities, isDemo: state.mode == .demo)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileValueCell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        var accessory: UITableViewCell.AccessoryType = .none
        var tint = AppColors.primary
        let caps = state.capabilities
        switch row {
        case .header: break
        case .linkPhone:
            content = .subtitleCell()
            content.text = L10n.Account.linkPhone
            content.secondaryText = L10n.Account.linkPhoneBenefit
            content.image = UIImage(systemName: "phone.badge.checkmark")
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
        case .linkPhone: performSegue(withIdentifier: Segue.presentPhoneLink, sender: self)
        case .addPlace: performSegue(withIdentifier: Segue.presentAddPlace, sender: self)
        case .mySubmissions: performSegue(withIdentifier: Segue.showMySubmissions, sender: self)
        case .moderation: performSegue(withIdentifier: Segue.showAdminQueue, sender: self)
        case .editName: promptDisplayName()
        case .location:
            if state.location != .notDetermined, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .clearCache:
            confirm(title: L10n.Profile.clearCache, message: L10n.Profile.clearCacheConfirm, action: L10n.Profile.clearCache) { [weak self] in self?.viewModel?.clearCache() }
        case .signOut:
            confirm(title: L10n.Profile.signOut, message: L10n.Profile.signOutConfirm, action: L10n.Profile.signOut) { [weak self] in self?.viewModel?.signOut() }
        default: break
        }
    }

    private func promptDisplayName() {
        let alert = UIAlertController(title: L10n.Profile.editName, message: nil, preferredStyle: .alert)
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
        case Segue.presentPhoneLink:
            ((segue.destination as? UINavigationController)?.topViewController as? PhoneLinkViewController)?
                .configure(viewModel: container.makePhoneLinkViewModel(), isDemo: container.isDemo)
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
    }

    func configure(capabilities: UserCapabilities?, isDemo: Bool) {
        let caps = capabilities
        nameLabel.text = caps?.isRegistered == true ? caps?.displayName : L10n.Account.guestTitle
        var roles: [String] = [caps?.isRegistered == true ? L10n.Profile.registered : L10n.Profile.notVerified]
        if caps?.isBusinessOwner == true { roles.append(L10n.Profile.businessOwner) }
        if caps?.isAdmin == true { roles.append(L10n.Profile.admin) }
        identifierLabel.text = roles.joined(separator: " · ")
        identifierLabel.textColor = caps?.isRegistered == true ? AppColors.good : AppColors.textSecondary
        avatarImageView.image = UIImage(systemName: caps?.isAdmin == true ? "checkmark.shield.fill" : caps?.isRegistered == true ? "person.fill.checkmark" : "person.fill")
        sinceLabel.text = isDemo ? "⚠︎ " + L10n.Common.demoBadge : nil
        sinceLabel.isHidden = !isDemo
        accessibilityLabel = [nameLabel.text, identifierLabel.text, sinceLabel.text].compactMap { $0 }.joined(separator: ", ")
    }
}
