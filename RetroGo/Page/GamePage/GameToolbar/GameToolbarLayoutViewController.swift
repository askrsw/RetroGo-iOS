//
//  GameToolbarLayoutViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/2.
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

/// Lets the player customize the in-game top bar: which `GameToolbarAction`s are
/// pinned (max `GameToolbarAction.maxPinned`) and in what order. Everything else
/// is collected into the More menu. Changes are persisted immediately and the
/// live toolbar rebuilds via `.gameToolbarLayoutChanged`.
final class GameToolbarLayoutViewController: UIViewController {
    private enum SectionIndex: Int, CaseIterable {
        case pinned
        case overflow
    }

    private lazy var tableView = self.configUI()

    private var pinned: [GameToolbarAction]
    private var overflow: [GameToolbarAction]

    /// Pauses the game while the layout editor is on screen; resumed on deinit
    /// when it's dismissed.
    private let gamePauseToken = RetroArchGamePauseToken()

    init() {
        let actions = GameConfigSession.globalToolbarActions()
        self.pinned = actions.pinned
        self.overflow = actions.overflow
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "gamepage_toolbar_layout_title")
        // Close on the left to match the rest of RetroGo; restore on the right.
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeAction)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.counterclockwise"),
            style: .plain,
            target: self,
            action: #selector(restoreAction)
        )

        _ = tableView
        tableView.setEditing(true, animated: false)
        updateRestoreButtonState()
    }

    /// Restore only makes sense once the user has customized the order — disable
    /// it otherwise so there's clear feedback there's nothing to restore.
    private func updateRestoreButtonState() {
        navigationItem.rightBarButtonItem?.isEnabled = GameConfigSession.globalToolbarActions().isCustomized
    }

    @objc
    private func closeAction() {
        Vibration.selection.vibrate()
        dismiss(animated: true)
    }

    /// Restores the default order and erases the stored arrangement, so the
    /// menu reverts to the default rule (declaration order). Confirmed first
    /// since it discards the user's customization.
    @objc
    private func restoreAction() {
        Vibration.selection.vibrate()

        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "gamepage_toolbar_restore_confirm_title"),
            message: Bundle.localizedString(forKey: "gamepage_toolbar_restore_confirm_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: Bundle.localizedString(forKey: "gamepage_toolbar_restore_default"),
            style: .destructive
        ) { [weak self] _ in
            GameConfigSession.resetGlobalToolbarOrder()
            self?.reloadFromStore()
        })
        alert.view.tintColor = .mainColor
        present(alert, animated: true)
    }

    /// Reloads the local arrays from the (now default) stored layout and
    /// refreshes the table.
    private func reloadFromStore() {
        let actions = GameConfigSession.globalToolbarActions()
        pinned = actions.pinned
        overflow = actions.overflow
        tableView.reloadData()
        updateRestoreButtonState()
    }
}

extension GameToolbarLayoutViewController {
    private func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tintColor = .mainColor
        tableView.allowsSelection = false
        tableView.estimatedRowHeight = 50
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return tableView
    }

    private func actions(in section: SectionIndex) -> [GameToolbarAction] {
        switch section {
        case .pinned:   return pinned
        case .overflow: return overflow
        }
    }

    /// Squircle background color used for each action's leading icon.
    private func iconColor(for action: GameToolbarAction) -> UIColor {
        switch action {
        case .saveState: return .systemBlue
        case .loadState: return .systemTeal
        case .snap:          return .systemIndigo
        case .mute:          return .systemPink
        case .lockLandscape: return .systemCyan
        case .setting:       return .systemGray
        case .restart:       return .systemOrange
        }
    }
}

extension GameToolbarLayoutViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        SectionIndex.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = SectionIndex(rawValue: section) else { return 0 }
        return actions(in: section).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch SectionIndex(rawValue: section) {
        case .pinned:   return Bundle.localizedString(forKey: "gamepage_toolbar_layout_pinned")
        case .overflow: return Bundle.localizedString(forKey: "gamepage_toolbar_layout_overflow")
        case .none:     return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard SectionIndex(rawValue: section) == .overflow else { return nil }
        return Bundle.localizedString(forKey: "gamepage_toolbar_layout_footer")
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .default, reuseIdentifier: "cell")
        guard let section = SectionIndex(rawValue: indexPath.section) else { return cell }
        let action = actions(in: section)[indexPath.row]
        cell.imageView?.image = IconRender.shared.settingsIcon(
            symbol: action.systemImageName,
            background: iconColor(for: action),
            size: CGSize(width: 28, height: 28)
        )
        cell.textLabel?.text = action.title
        return cell
    }

    // MARK: Editing / reordering

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        // Block moving a new item into a full pinned section; keep it in overflow.
        if proposedDestinationIndexPath.section == SectionIndex.pinned.rawValue,
           sourceIndexPath.section == SectionIndex.overflow.rawValue,
           pinned.count >= GameToolbarAction.maxPinned {
            return IndexPath(row: max(0, overflow.count - 1), section: SectionIndex.overflow.rawValue)
        }
        return proposedDestinationIndexPath
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard
            let from = SectionIndex(rawValue: sourceIndexPath.section),
            let to = SectionIndex(rawValue: destinationIndexPath.section)
        else { return }

        let action: GameToolbarAction
        switch from {
        case .pinned:   action = pinned.remove(at: sourceIndexPath.row)
        case .overflow: action = overflow.remove(at: sourceIndexPath.row)
        }

        switch to {
        case .pinned:   pinned.insert(action, at: min(destinationIndexPath.row, pinned.count))
        case .overflow: overflow.insert(action, at: min(destinationIndexPath.row, overflow.count))
        }

        GameConfigSession.setGlobalToolbar(pinned: pinned, overflow: overflow)
        updateRestoreButtonState()
    }
}

extension GameToolbarLayoutViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        50
    }
}
