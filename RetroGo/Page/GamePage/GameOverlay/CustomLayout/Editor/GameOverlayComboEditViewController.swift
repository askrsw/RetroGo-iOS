//
//  GameOverlayComboEditViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/9.
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

/// Makes or edits a combo of the layout being edited: which native buttons it
/// presses and whether it fires turbo. The buttons keep the platform's order,
/// so the same set always gets the same name.
final class GameOverlayComboEditViewController: UITableViewController {
    private let keys: [GameOverlayComboKey]
    private let combo: GameOverlayLayoutData.Combo?
    /// Another combo that already presses these buttons, turbo or not, if any.
    private let existingCombo: ([String]) -> Existing?

    /// A combo the new one would duplicate: its name, and whether this view shows it.
    struct Existing {
        let title: String
        let isTurbo: Bool
        let isShown: Bool
    }

    var onSave: ((GameOverlayLayoutData.Combo) -> Void)?
    var onDelete: (() -> Void)?

    private var selected: Set<String>
    private var turbo: Bool

    private enum Section: Int, CaseIterable {
        case preview, keys, turbo, delete
    }

    private var sections: [Section] {
        combo == nil ? [.preview, .keys, .turbo] : Section.allCases
    }

    init(keys: [GameOverlayComboKey], combo: GameOverlayLayoutData.Combo?, existingCombo: @escaping ([String]) -> Existing?) {
        self.keys = keys
        self.combo = combo
        self.existingCombo = existingCombo
        self.selected = Set(combo?.binds ?? [])
        self.turbo = combo?.turbo ?? false
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Bundle.localizedString(forKey: combo == nil ? "overlay_combo_new" : "overlay_combo_edit_title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: Bundle.localizedString(forKey: "overlay_layout_save"),
            primaryAction: UIAction { [weak self] _ in self?.save() }
        )
        navigationItem.rightBarButtonItem?.style = .done
        updateSaveState()
    }

    /// Selected buttons in the platform's order.
    private var binds: [String] {
        keys.map(\.bind.rawValue).filter(selected.contains)
    }

    private var previewTitle: GameOverlayComboTitle? {
        let parts = keys.filter { selected.contains($0.bind.rawValue) }.map(\.titlePart)
        return parts.isEmpty ? nil : GameOverlayComboTitle(parts: parts)
    }

    private var isComplete: Bool {
        GameOverlayLayoutData.Combo.keyRange.contains(selected.count)
    }

    /// The combo this one would duplicate; saving is blocked while there is one.
    private var duplicate: Existing? {
        isComplete ? existingCombo(binds) : nil
    }

    private var isDuplicate: Bool {
        duplicate != nil
    }

    /// Why Save is off: names the combo that already does this and, when it is hidden, how to show it.
    private var duplicateMessage: String? {
        guard let duplicate else { return nil }
        let name = duplicate.isTurbo
            ? String(format: Bundle.localizedString(forKey: "overlay_combo_turbo_name_format"), duplicate.title)
            : duplicate.title
        let key = duplicate.isShown ? "overlay_combo_taken_format" : "overlay_combo_taken_hidden_format"
        return String(format: Bundle.localizedString(forKey: key), name)
    }

    private func updateSaveState() {
        navigationItem.rightBarButtonItem?.isEnabled = isComplete && !isDuplicate
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section] == .keys ? keys.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        switch sections[indexPath.section] {
        case .preview:
            cell.selectionStyle = .none
            configurePreview(cell)
            return cell
        case .keys:
            let key = keys[indexPath.row]
            // Rows show the symbol a combo draws for the button; a PlayStation shape needs no name next to it.
            content.text = key.symbolReplacesTitle ? nil : key.title
            if let symbol = key.symbol {
                content.image = UIImage(systemName: symbol)
                content.imageProperties.tintColor = .label
            }
            cell.accessoryType = selected.contains(key.bind.rawValue) ? .checkmark : .none
            cell.tintColor = .mainColor
        case .turbo:
            cell.selectionStyle = .none
            content.text = Bundle.localizedString(forKey: "overlay_combo_turbo")
            let toggle = UISwitch()
            toggle.isOn = turbo
            toggle.onTintColor = .mainColor
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }
                turbo = toggle.isOn
                refreshPreview()
            }, for: .valueChanged)
            cell.accessoryView = toggle
        case .delete:
            content.text = Bundle.localizedString(forKey: "overlay_combo_delete")
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section] == .keys ? Bundle.localizedString(forKey: "overlay_combo_keys") : nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch sections[section] {
        case .keys:
            return Bundle.localizedString(forKey: "overlay_combo_keys_footer")
        case .turbo:
            return Bundle.localizedString(forKey: "overlay_combo_turbo_footer")
        case .preview, .delete:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .keys:
            let bind = keys[indexPath.row].bind.rawValue
            if selected.contains(bind) {
                selected.remove(bind)
            } else if selected.count < GameOverlayLayoutData.Combo.keyRange.upperBound {
                selected.insert(bind)
            } else {
                Vibration.error.vibrate()
                return
            }
            Vibration.selection.vibrate()
            tableView.cellForRow(at: indexPath)?.accessoryType = selected.contains(bind) ? .checkmark : .none
            refreshPreview()
        case .delete:
            onDelete?()
            dismiss(animated: true)
        case .preview, .turbo:
            break
        }
    }

    private func configurePreview(_ cell: UITableViewCell) {
        var content = cell.defaultContentConfiguration()
        let font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        if let previewTitle {
            let text = NSMutableAttributedString(attributedString: previewTitle.attributedString(font: font))
            text.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.length))
            content.attributedText = text
        } else {
            content.text = Bundle.localizedString(forKey: "overlay_combo_preview_empty")
            content.textProperties.font = font
            content.textProperties.color = .tertiaryLabel
        }
        content.textProperties.alignment = .center
        if let duplicateMessage {
            content.secondaryText = duplicateMessage
            content.secondaryTextProperties.color = .systemOrange
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
            content.secondaryTextProperties.alignment = .center
            content.textToSecondaryTextVerticalPadding = 6
        }
        cell.contentConfiguration = content
    }

    /// The preview row carries the duplicate warning, so it is seen without scrolling.
    private func refreshPreview() {
        updateSaveState()
        guard let index = sections.firstIndex(of: .preview) else { return }
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: index)) {
            configurePreview(cell)
        }
        // The warning changes the row height.
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    private func save() {
        guard isComplete, !isDuplicate else { return }
        let id = combo?.id ?? GameOverlayLayoutData.Combo.makeId()
        onSave?(GameOverlayLayoutData.Combo(id: id, binds: binds, turbo: turbo))
        dismiss(animated: true)
    }
}
