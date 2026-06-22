//
//  GameCheatListViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/6.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import UIKit
import SnapKit
import ObjcHelper
import RACoordinator

/// The in-game cheat editor. Bound system templates are shown first and are
/// toggle/detail-only; user-created cheats are shown second and remain editable,
/// deletable, and reorderable. Presented from the toolbar inside a navigation
/// controller; pauses the game while open.
///
/// Built on a UICollectionView list + diffable data source. User cheats
/// drag-reorder via the cell's `.reorder()` grip (no edit mode).
final class GameCheatListViewController: UIViewController {
    private enum Section: Hashable {
        case template(count: Int, origin: GameCheatTemplateBindingOrigin?)
        case user
    }

    private enum RowID: Hashable {
        case template(Int)
        case user(String)
    }

    private var gamePauseLease: GamePauseCoordinator.Lease?

    private let session: GameCheatSession
    private let showClose: Bool

    private var collectionView: UICollectionView!
    /// Set when returning from "create editable copy" so the freshly added user
    /// cheat is scrolled into view once this list reappears.
    private var pendingScrollUserId: String?
    private var dataSource: UICollectionViewDiffableDataSource<Section, RowID>!
    private let tipLabel = UILabel(frame: .zero)
    private var catalogDownloadInProgress = false

    init(session: GameCheatSession, showClose: Bool = true) {
        self.session = session
        self.showClose = showClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func cheatStateDidChange() {
        applySnapshot(animatingDifferences: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        gamePauseLease = acquireGamePause(reason: "cheat-list")
        attachGamePauseLeaseToPresentation(gamePauseLease)

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "cheat_title")
        let titleIcon = IconRender.shared.settingsIcon(symbol: "star.circle", background: .cheatIconColor, size: CGSize(width: 22, height: 22))
        navigationItem.titleView = Self.makeIconTitleView(Bundle.localizedString(forKey: "cheat_title"), icon: titleIcon)

        if showClose {
            let close = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeAction))
            close.tintColor = .label
            navigationItem.leftBarButtonItem = close
        }
        // The catalog button opens the read-only template browser. If the
        // optional cheat ODR is missing, it downloads in-place before opening.
        let catalog = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(catalogAction))
        catalog.tintColor = .label
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addAction))
        add.tintColor = .label
        navigationItem.rightBarButtonItems = [add, catalog]

        configureCollectionView()
        configureDataSource()
        applySnapshot(animatingDifferences: false)

        // Entering/leaving a netplay session forces every cheat off / restores it
        // in the session snapshot. Refresh the switches if that happens while the
        // list is on screen (e.g. a peer leaves and the session ends).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cheatStateDidChange),
            name: .gameCheatStateChanged,
            object: nil
        )

    #if DEBUG
        debugPrintROMCRC32AndRDBMatch()
    #endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySnapshot(animatingDifferences: false)
        reloadTemplateSection()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isClosingOrBeingDismissedFromGamePauseContext() {
            gamePauseLease?.release()
            gamePauseLease = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachGamePauseLeaseToPresentation(gamePauseLease)
        scrollToPendingUserCheatIfNeeded()
    }

    /// Called by the template detail page after it copies a system cheat into the
    /// user list, so this controller scrolls to the new (bottom) row on return.
    func revealUserCheat(id: String) {
        pendingScrollUserId = id
    }

    private func scrollToPendingUserCheatIfNeeded() {
        guard let id = pendingScrollUserId,
              let indexPath = dataSource.indexPath(for: .user(id)) else { return }
        pendingScrollUserId = nil
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
    }
}

private final class GameCheatSectionTextView: UICollectionReusableView {
    private let label = UILabel(frame: .zero)
    private var topConstraint: Constraint?
    private var bottomConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        addSubview(label)
        label.snp.makeConstraints { make in
            // The supplementary view is already laid out in the inset-grouped
            // content rect. Match RetroRomCoreInfoViewController: pin to that
            // rect directly instead of adding another artificial inset.
            make.leading.trailing.equalToSuperview()
            topConstraint = make.top.equalToSuperview().constraint
            bottomConstraint = make.bottom.equalToSuperview().constraint
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureHeader(_ text: String, addsSectionGap: Bool) {
        isHidden = false
        label.text = text
        label.font = .boldSystemFont(ofSize: UIFont.labelFontSize)
        label.textColor = .secondaryLabel
        topConstraint?.update(offset: addsSectionGap ? 32 : 20)
        bottomConstraint?.update(offset: -10)
    }

    func configureFooter(_ text: String?) {
        isHidden = text == nil
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        if text == nil {
            topConstraint?.update(offset: 0)
            bottomConstraint?.update(offset: 0)
        } else {
            topConstraint?.update(offset: 8)
            bottomConstraint?.update(offset: -18)
        }
    }
}

// MARK: - Collection view / data source

extension GameCheatListViewController {
    private func item(for id: String) -> GameCheatItem? {
        session.items.first { $0.id == id }
    }

    private func templateItem(for id: Int) -> RACheatItem? {
        session.templateItems.first { $0.catalogId == id }
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        config.footerMode = .supplementary
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.trailingSwipeActions(at: indexPath)
        }
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<GameCheatCollectionViewCell, RowID> { [weak self] cell, _, rowID in
            guard let self else { return }
            switch rowID {
            case .template(let catalogId):
                guard let item = self.templateItem(for: catalogId) else { return }
                cell.configure(with: item)
                cell.onToggle = { [weak self] isOn in
                    guard let self else { return }
                    guard self.allowToggleCheat(isOn: isOn) else { return }
                    self.session.setTemplateEnabled(isOn, for: item)
                }
            case .user(let id):
                guard let item = self.item(for: id) else { return }
                cell.configure(with: item)
                cell.onToggle = { [weak self] isOn in
                    guard let self else { return }
                    guard self.allowToggleCheat(isOn: isOn) else { return }
                    self.session.setEnabled(isOn, for: item)
                }
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, RowID>(collectionView: collectionView) { collectionView, indexPath, rowID in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: rowID)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<GameCheatSectionTextView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let self else { return }
            let text: String?
            switch self.dataSource.sectionIdentifier(for: indexPath.section) {
            case .template(let count, let origin):
                let titleKey: String
                if origin == .automatic {
                    titleKey = "cheat_template_section_auto"
                } else {
                    titleKey = "cheat_template_section"
                }
                text = String(
                    format: Bundle.localizedString(forKey: "cheat_template_section_count_format"),
                    Bundle.localizedString(forKey: titleKey),
                    count)
            case .user:
                text = Bundle.localizedString(forKey: "cheat_user_section")
            case .none:
                text = nil
            }
            header.configureHeader(text ?? "", addsSectionGap: indexPath.section > 0)
        }
        let footerRegistration = UICollectionView.SupplementaryRegistration<GameCheatSectionTextView>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footer, _, indexPath in
            guard let self else { return }
            let text: String?
            switch self.dataSource.sectionIdentifier(for: indexPath.section) {
            case .template:
                text = Bundle.localizedString(forKey: "cheat_template_footer")
            case .user, .none:
                text = nil
            }
            footer.configureFooter(text)
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            if kind == UICollectionView.elementKindSectionFooter {
                return collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
            }
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }

        // Drag the cell's `.reorder()` grip to reorder user-created cheats.
        dataSource.reorderingHandlers.canReorderItem = { [weak self] rowID in
            guard let self else { return false }
            if case .user(let id) = rowID {
                return self.item(for: id) != nil
            }
            return false
        }
        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self else { return }
            let ids = transaction.finalSnapshot.itemIdentifiers(inSection: .user).compactMap { rowID -> String? in
                if case .user(let id) = rowID { return id }
                return nil
            }
            self.session.reorder(idOrder: ids)
        }
    }

    private func applySnapshot(animatingDifferences: Bool) {
        let templateIds = session.templateItems.map { RowID.template($0.catalogId) }
        let userIds = session.items.map { RowID.user($0.id) }
        let existing = Set(dataSource.snapshot().itemIdentifiers)

        var snapshot = NSDiffableDataSourceSnapshot<Section, RowID>()
        if !templateIds.isEmpty {
            let templateSection = Section.template(
                count: templateIds.count,
                origin: session.templateBinding?.origin
            )
            snapshot.appendSections([templateSection])
            snapshot.appendItems(templateIds, toSection: templateSection)
        }
        if !userIds.isEmpty {
            snapshot.appendSections([.user])
            snapshot.appendItems(userIds, toSection: .user)
        }
        // Re-render rows that survived (e.g. after an edit or switch changed state).
        let toReconfigure = (templateIds + userIds).filter { existing.contains($0) }
        if !toReconfigure.isEmpty {
            snapshot.reconfigureItems(toReconfigure)
        }
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
        updateTipLabel()
    }

    private func trailingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard
            let rowID = dataSource.itemIdentifier(for: indexPath),
            case .user(let id) = rowID,
            let item = item(for: id)
        else { return nil }

        let title = Bundle.localizedString(forKey: "cheat_delete")
        let delete = UIContextualAction(style: .destructive, title: title) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let ok = self.session.deleteCheat(item)
            if ok {
                self.applySnapshot(animatingDifferences: true)
            }
            completion(ok)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func reloadTemplateSection() {
        session.reloadTemplateItems { [weak self] in
            self?.applySnapshot(animatingDifferences: true)
        }
    }

    @MainActor
    private func allowToggleCheat(isOn: Bool) -> Bool {
        guard isOn else { return true }
        // Cheats can't be enabled during a netplay session (would desync peers).
        // Bounce the switch back via applySnapshot and explain why. Checked before
        // the Pro gate so the message is netplay-specific, not a paywall.
        if RANetplayCoordinator.shared.isNetplayEnabled {
            applySnapshot(animatingDifferences: true)
            showNetplayCheatBlocked()
            return false
        }
        let allowed = AppStoreProFeatureGate.shared.requirePro(
            feature: .cheats,
            presentation: .alert,
            from: self,
            toastContext: .game
        )
        if !allowed {
            applySnapshot(animatingDifferences: true)
        }
        return allowed
    }

    private func showNetplayCheatBlocked() {
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "cheat_title"),
            message: Bundle.localizedString(forKey: "netplay_cheat_blocked"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }

    private func debugPrintROMCRC32AndRDBMatch() {
        let game = session.game
        DispatchQueue.global(qos: .utility).async {
            do {
                _ = try game.ensureCRC32()
            } catch {
                print("[CheatAutoBind] ROM=\(game.itemName), failed to ensure CRC32: \(error)")
            }

            let candidates = game.crc32LookupCandidates()
            print("[CheatAutoBind] ROM=\(game.itemName), rom.crc32=\(game.crc32 ?? "nil"), candidates=\(candidates)")
            guard !candidates.isEmpty else {
                return
            }

            for crc32 in candidates {
                if let entry = RAGameRDBManager.shared().findGame(byCRC32: crc32) {
                    let group = entry.groupName ?? "nil"
                    print("[CheatAutoBind] CRC32=\(crc32) matched gamerdb: name=\"\(entry.name)\", group=\"\(group)\", platformId=\(entry.platformId)")
                } else {
                    print("[CheatAutoBind] CRC32=\(crc32) did not match gamerdb")
                }
            }
        }
    }
}

// MARK: - Tip / actions

extension GameCheatListViewController {
    private func updateTipLabel() {
        guard session.items.isEmpty, session.templateItems.isEmpty else {
            tipLabel.removeFromSuperview()
            return
        }

        tipLabel.textAlignment = .center
        tipLabel.numberOfLines = 0
        tipLabel.attributedText = session.cheatSupported
            ? Self.emptyStateAttributedText()
            : Self.unsupportedAttributedText()
        if tipLabel.superview == nil {
            view.addSubview(tipLabel)
            tipLabel.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.leading.greaterThanOrEqualToSuperview().offset(40)
                make.trailing.lessThanOrEqualToSuperview().offset(-40)
            }
        }
        view.bringSubviewToFront(tipLabel)
    }

    /// Empty state: a bold title over a softer body line whose `%@` slots are
    /// replaced with the live `plus` / `magnifyingglass` toolbar symbols so the
    /// hint visually points at the two top-right buttons.
    private static func emptyStateAttributedText() -> NSAttributedString {
        let titleFont = UIFont.systemFont(ofSize: 19, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 15, weight: .regular)

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center
        titleParagraph.paragraphSpacing = 10

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.alignment = .center
        bodyParagraph.lineSpacing = 6

        let result = NSMutableAttributedString(
            string: Bundle.localizedString(forKey: "cheat_empty_title") + "\n",
            attributes: [
                .font: titleFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: titleParagraph
            ])

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: bodyParagraph
        ]
        let body = Bundle.localizedString(forKey: "cheat_empty_body")
        let parts = body.components(separatedBy: "%@")
        let symbols = ["plus", "magnifyingglass"]
        for (index, part) in parts.enumerated() {
            if !part.isEmpty {
                result.append(NSAttributedString(string: part, attributes: bodyAttributes))
            }
            if index < parts.count - 1, index < symbols.count,
               let symbol = symbolAttachment(symbols[index], font: bodyFont) {
                result.append(symbol)
            }
        }
        return result
    }

    private static func unsupportedAttributedText() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 6
        return NSAttributedString(
            string: Bundle.localizedString(forKey: "cheat_core_unsupported"),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph
            ])
    }

    /// An inline, baseline-centered SF Symbol tinted to match the body text.
    private static func symbolAttachment(_ name: String, font: UIFont) -> NSAttributedString? {
        let config = UIImage.SymbolConfiguration(font: font)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal) else {
            return nil
        }
        let attachment = NSTextAttachment(image: image)
        let centeredY = (font.capHeight - image.size.height) / 2.0
        attachment.bounds = CGRect(x: 0, y: centeredY,
                                   width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    @objc
    private func closeAction() {
        Vibration.selection.vibrate()
        navigationController?.dismiss(animated: true)
    }

    @objc
    private func addAction() {
        Vibration.selection.vibrate()
        let editor = GameCheatEditViewController(session: session, editing: nil)
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc
    private func catalogAction() {
        Vibration.selection.vibrate()
        let platformIds = session.core.cheatCatalogPlatformIds
        guard !platformIds.isEmpty else {
            showCatalogUnavailable()
            return
        }
        ensureCheatCatalogReady { [weak self] in
            guard let self else { return }
            let browser = GameCheatCatalogBrowserViewController(platformIds: platformIds, session: session)
            self.navigationController?.pushViewController(browser, animated: true)
        }
    }

    private func ensureCheatCatalogReady(_ completion: @escaping () -> Void) {
        guard let cheat = OnDemandResourceLoader.resource(id: "cheat") else { return }
        let loader = OnDemandResourceLoader.shared
        switch loader.state(for: cheat) {
        case .ready:
            initializeCheatCatalog(completion)
            return
        case .downloading:
            return
        case .notDownloaded:
            break
        }
        guard !catalogDownloadInProgress else { return }
        catalogDownloadInProgress = true

        let title = Bundle.localizedString(forKey: cheat.titleKey)
        let activity = RetroRomActivityView(mainTitle: title)
        activity.install()
        activity.activeMessage(downloadingText(0), title: title)
        loader.startDownload(cheat, progress: { [weak self, weak activity] progress in
            activity?.activeMessage(self?.downloadingText(progress) ?? "", title: title)
        }, completion: { [weak self, weak activity] ok, error in
            guard let self else { return }
            self.catalogDownloadInProgress = false
            if ok {
                activity?.successMessage(
                    Bundle.localizedString(forKey: "odr_download_done"),
                    title: title,
                    canDismiss: true)
                self.initializeCheatCatalog(completion)
            } else {
                let message = Bundle.localizedString(forKey: "odr_download_failed")
                    + (error.map { "\n\($0.localizedDescription)" } ?? "")
                activity?.errorMessage(message, title: title, canDismiss: true)
            }
        })
    }

    private func initializeCheatCatalog(_ completion: @escaping () -> Void) {
        guard let cheat = OnDemandResourceLoader.resource(id: "cheat") else { return }
        let loader = OnDemandResourceLoader.shared
        let locPath = OnDemandResourceLoader.resource(id: "gameloc").map { loader.targetPath($0) }
        RACheatCatalogManager.shared().initialize(
            withCheatPath: loader.targetPath(cheat),
            localizationPath: locPath,
            completion: completion)
    }

    private func downloadingText(_ fraction: Double) -> String {
        let pct = Int((fraction * 100).rounded())
        return String(format: Bundle.localizedString(forKey: "odr_downloading_fmt"), pct)
    }

    private func showCatalogUnavailable() {
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "cheat_catalog_unavailable_title"),
            message: Bundle.localizedString(forKey: "cheat_catalog_unavailable_message"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension GameCheatListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        Vibration.selection.vibrate()
        guard let rowID = dataSource.itemIdentifier(for: indexPath) else { return }
        switch rowID {
        case .template(let catalogId):
            guard let item = templateItem(for: catalogId) else { return }
            navigationController?.pushViewController(GameCheatCatalogDetailViewController(cheat: item, session: session), animated: true)
        case .user(let id):
            guard let item = item(for: id) else { return }
            let editor = GameCheatEditViewController(session: session, editing: item)
            navigationController?.pushViewController(editor, animated: true)
        }
    }

    /// User cheats reorder only within their own section. Clamp any drag that
    /// strays into the read-only system-template section back to the top of the
    /// user section, preserving the template/user semantic boundary.
    func collectionView(_ collectionView: UICollectionView,
                        targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        guard let userSection = dataSource.snapshot().indexOfSection(.user) else {
            return originalIndexPath
        }
        if proposedIndexPath.section != userSection {
            return IndexPath(item: 0, section: userSection)
        }
        return proposedIndexPath
    }
}
