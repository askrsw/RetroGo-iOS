//
//  GameOverlayLayoutListViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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
import ObjcHelper

/// The control layouts of one platform: the built-in layout first, then the
/// user's layouts, then "New Layout". Picking a row uses it right away, for
/// this game or, with the switch on, for the whole platform; in game the
/// controls behind the list show it at once.
///
/// Editing and creating need the game screen, so they are only offered when
/// `editHandler` is set (opened from the game); from the settings pages the
/// list chooses, renames, duplicates and deletes.
final class GameOverlayLayoutListViewController: UITableViewController {
    enum EditRequest {
        case create
        case edit(GameOverlayLayoutItem)
    }

    private let session: GameOverlayLayoutSession
    /// Set in game: closes the list and opens the editor.
    var editHandler: ((EditRequest) -> Void)?

    private var layouts: [GameOverlayLayoutItem] = []

    private enum Section {
        case layouts
        case create
        case scope
    }

    private enum ScopeRow {
        case applyToPlatform
        case followPlatform
    }

    private var sections: [Section] {
        var sections: [Section] = [.layouts]
        if editHandler != nil { sections.append(.create) }
        if session.game != nil { sections.append(.scope) }
        return sections
    }

    private var scopeRows: [ScopeRow] {
        session.gameChoice() == .followPlatform ? [.applyToPlatform] : [.applyToPlatform, .followPlatform]
    }

    /// Picking a layout in a game changes only that game: someone switching
    /// layouts mid-game rarely means every game. Without a game (core settings)
    /// every choice is the platform's.
    private var choosesForPlatform: Bool {
        session.game == nil
    }

    /// The "use for all games" switch shows the real state, not a mode for the
    /// next tap: on while this game has no layout of its own, so the checked
    /// layout is the platform's. Picking a layout turns it off.
    private var usesPlatformLayout: Bool {
        session.gameChoice() == .followPlatform
    }

    /// On: the checked layout becomes the platform's and this game follows it.
    /// Off: the checked layout stays, for this game only; the platform keeps its layout.
    private func setUsesPlatformLayout(_ on: Bool) {
        let current = session.resolvedLayout().item?.id
        session.choose(layoutId: current, applyToPlatform: on)
    }

    init(session: GameOverlayLayoutSession) {
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Bundle.localizedString(forKey: "overlay_layout_list_title")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        NotificationCenter.default.addObserver(self, selector: #selector(layoutsChanged(_:)), name: .overlayLayoutChanged, object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func layoutsChanged(_ notification: Notification) {
        guard notification.object as? String == session.overlayName else { return }
        reload()
    }

    private func reload() {
        layouts = session.layouts()
        tableView.reloadData()
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .layouts: return layouts.count + 1
        case .create: return 1
        case .scope: return scopeRows.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sections[section] == .layouts else { return nil }
        return currentChoiceText
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch sections[section] {
        case .layouts:
            return editHandler == nil ? Bundle.localizedString(forKey: "overlay_layout_manage_hint") : nil
        case .scope:
            return Bundle.localizedString(forKey: "overlay_layout_apply_to_platform_footer")
        case .create:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .secondaryLabel

        switch sections[indexPath.section] {
        case .layouts:
            let item = layoutItem(at: indexPath.row)
            content.text = item?.name ?? Bundle.localizedString(forKey: "overlay_layout_builtin")
            content.secondaryText = item.flatMap(usageText)
            cell.accessoryType = isChosen(item) ? .checkmark : .none
            cell.tintColor = .mainColor
            if let item {
                cell.accessoryView = makeMoreButton(for: item, checked: isChosen(item))
            }
        case .create:
            content = cell.defaultContentConfiguration()
            content.text = Bundle.localizedString(forKey: "overlay_layout_new")
            content.textProperties.color = .mainColor
            content.image = UIImage(systemName: "plus.circle.fill")
            content.imageProperties.tintColor = .mainColor
        case .scope:
            content = cell.defaultContentConfiguration()
            switch scopeRows[indexPath.row] {
            case .applyToPlatform:
                content.text = applyToPlatformTitle
                let toggle = UISwitch()
                toggle.isOn = usesPlatformLayout
                toggle.onTintColor = .mainColor
                toggle.addAction(UIAction { [weak self, weak toggle] _ in
                    Vibration.selection.vibrate()
                    self?.setUsesPlatformLayout(toggle?.isOn ?? false)
                }, for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
            case .followPlatform:
                content.text = Bundle.localizedString(forKey: "overlay_layout_follow_platform")
                content.textProperties.color = .mainColor
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        !(sections[indexPath.section] == .scope && scopeRows[indexPath.row] == .applyToPlatform)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()
        switch sections[indexPath.section] {
        case .layouts:
            session.choose(layoutId: layoutItem(at: indexPath.row)?.id, applyToPlatform: choosesForPlatform)
        case .create:
            editHandler?(.create)
        case .scope:
            if scopeRows[indexPath.row] == .followPlatform {
                session.followPlatform()
            }
        }
    }

    // MARK: Texts

    private func layoutItem(at row: Int) -> GameOverlayLayoutItem? {
        row == 0 ? nil : layouts[row - 1]
    }

    /// The checkmark: what this game ends up with, or the platform choice without a game.
    private func isChosen(_ item: GameOverlayLayoutItem?) -> Bool {
        if session.game == nil {
            return session.platformLayoutId() == item?.id
        }
        return session.resolvedLayout().item?.id == item?.id
    }

    private var currentChoiceText: String {
        let resolved = session.resolvedLayout()
        let name = resolved.item?.name ?? Bundle.localizedString(forKey: "overlay_layout_builtin")
        if session.game == nil {
            let format = session.platformTitle.map { _ in Bundle.localizedString(forKey: "overlay_layout_platform_uses_format") }
            if let format, let platform = session.platformTitle {
                return String(format: format, platform, name)
            }
            return String(format: Bundle.localizedString(forKey: "overlay_layout_platform_uses_generic_format"), name)
        }
        let sourceKey: String
        switch resolved.source {
        case .game: sourceKey = "overlay_layout_source_game"
        case .platform: sourceKey = "overlay_layout_source_platform"
        case .builtIn: return Bundle.localizedString(forKey: "overlay_layout_current_game_builtin")
        }
        return String(format: Bundle.localizedString(forKey: "overlay_layout_current_game_format"),
                      name, Bundle.localizedString(forKey: sourceKey))
    }

    private var applyToPlatformTitle: String {
        if let platform = session.platformTitle {
            return String(format: Bundle.localizedString(forKey: "overlay_layout_apply_to_platform"), platform)
        }
        return Bundle.localizedString(forKey: "overlay_layout_apply_to_platform_generic")
    }

    private func usageText(_ item: GameOverlayLayoutItem) -> String? {
        let usage = session.usage(of: item.id)
        var parts: [String] = []
        if usage.platform {
            if let platform = session.platformTitle {
                parts.append(String(format: Bundle.localizedString(forKey: "overlay_layout_usage_platform"), platform))
            } else {
                parts.append(Bundle.localizedString(forKey: "overlay_layout_usage_platform_generic"))
            }
        }
        if usage.games == 1 {
            parts.append(Bundle.localizedString(forKey: "overlay_layout_usage_one_game"))
        } else if usage.games > 1 {
            parts.append(String(format: Bundle.localizedString(forKey: "overlay_layout_usage_games"), usage.games))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Row actions

    private func makeMoreButton(for item: GameOverlayLayoutItem, checked: Bool) -> UIView {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.tintColor = .secondaryLabel
        button.showsMenuAsPrimaryAction = true
        button.menu = makeMenu(for: item)
        button.frame = CGRect(x: 0, y: 0, width: 32, height: 32)

        guard checked else { return button }
        // The checkmark sits before the menu button, as the accessory view replaces the accessory type.
        let check = UIImageView(image: UIImage(systemName: "checkmark"))
        check.tintColor = .mainColor
        check.contentMode = .center
        let stack = UIStackView(arrangedSubviews: [check, button])
        stack.spacing = 8
        stack.frame = CGRect(x: 0, y: 0, width: 32 + 8 + 20, height: 32)
        return stack
    }

    private func makeMenu(for item: GameOverlayLayoutItem) -> UIMenu {
        var actions: [UIMenuElement] = []
        if let editHandler {
            actions.append(UIAction(title: Bundle.localizedString(forKey: "overlay_layout_edit"), image: UIImage(systemName: "slider.horizontal.3")) { _ in
                editHandler(.edit(item))
            })
        }
        actions.append(UIAction(title: Bundle.localizedString(forKey: "overlay_layout_rename"), image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.rename(item)
        })
        actions.append(UIAction(title: Bundle.localizedString(forKey: "overlay_layout_duplicate"), image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
            self?.duplicate(item)
        })
        let delete = UIAction(title: Bundle.localizedString(forKey: "overlay_layout_delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.confirmDelete(item)
        }
        return UIMenu(children: [UIMenu(options: .displayInline, children: actions), delete])
    }

    private func rename(_ item: GameOverlayLayoutItem) {
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "overlay_layout_rename"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = item.name
            field.placeholder = Bundle.localizedString(forKey: "overlay_layout_name_placeholder")
            field.clearButtonMode = .whileEditing
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != item.name, !trimmed.isEmpty else { return }
            if !session.renameLayout(id: item.id, name: trimmed) {
                showMessage(Bundle.localizedString(forKey: session.isNameTaken(trimmed, excluding: item.id) ? "overlay_layout_name_taken" : "overlay_layout_save_failed"))
            }
        })
        present(alert, animated: true)
    }

    private func duplicate(_ item: GameOverlayLayoutItem) {
        let base = "\(item.name) \(Bundle.localizedString(forKey: "overlay_layout_copy_suffix"))"
        let name = session.isNameTaken(base) ? session.suggestedName(prefix: base) : base
        if session.duplicateLayout(id: item.id, name: name) == nil {
            showMessage(Bundle.localizedString(forKey: "overlay_layout_save_failed"))
        }
    }

    private func confirmDelete(_ item: GameOverlayLayoutItem) {
        let usage = session.usage(of: item.id)
        let inUse = usage.platform || usage.games > 0
        let alert = UIAlertController(
            title: String(format: Bundle.localizedString(forKey: "overlay_layout_delete_title"), item.name),
            message: inUse ? Bundle.localizedString(forKey: "overlay_layout_delete_in_use") : nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "overlay_layout_delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            if !session.deleteLayout(id: item.id) {
                showMessage(Bundle.localizedString(forKey: "overlay_layout_save_failed"))
            }
        })
        present(alert, animated: true)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }
}
