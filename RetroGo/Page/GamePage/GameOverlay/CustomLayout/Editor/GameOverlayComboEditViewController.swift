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
final class GameOverlayComboEditViewController: UITableViewController, UIAdaptivePresentationControllerDelegate {
    private let keys: [GameOverlayComboKey]
    private let combo: GameOverlayLayoutData.Combo?
    private let reservedIds: Set<String>
    /// Another combo that already presses these buttons, turbo or not, if any.
    private let existingCombo: ([String]) -> Existing?

    /// A combo the new one would duplicate: its name, and whether this view shows it.
    struct Existing {
        let title: String
        let isTurbo: Bool
        let isShown: Bool
    }

    var onSave: ((GameOverlayLayoutData.Combo, Bool) -> Void)?
    var onDelete: (() -> Void)?

    private var selected: [String]
    private var turbo: Bool
    private var multiKeyTurbo: Bool
    private var shown: Bool
    private var didFinish = false

    private enum Section: Int, CaseIterable {
        case preview, keys, turbo, visibility, delete
    }

    private var sections: [Section] {
        combo == nil ? [.preview, .keys, .turbo] : Section.allCases
    }

    init(keys: [GameOverlayComboKey], combo: GameOverlayLayoutData.Combo?, suggestedBinds: [String] = [], suggestedTurbo: Bool = true,
         shown: Bool = true, reservedIds: Set<String> = [], existingCombo: @escaping ([String]) -> Existing?) {
        self.keys = keys
        self.combo = combo
        self.reservedIds = reservedIds
        self.existingCombo = existingCombo
        self.selected = combo?.binds ?? suggestedBinds
        self.turbo = combo?.turbo ?? (!suggestedBinds.isEmpty && suggestedTurbo)
        self.multiKeyTurbo = combo?.binds.count == 1 ? false : (combo?.turbo ?? (!suggestedBinds.isEmpty && suggestedTurbo))
        self.shown = shown
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.estimatedSectionFooterHeight = 60
        tableView.separatorInset = .zero
        tableView.separatorInsetReference = .fromCellEdges
        title = Bundle.localizedString(forKey: combo == nil ? "overlay_combo_new" : "overlay_combo_edit_title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.didFinish = true
            self?.closeSheet()
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: Bundle.localizedString(forKey: "overlay_layout_save"),
            primaryAction: UIAction { [weak self] _ in self?.save() }
        )
        navigationItem.rightBarButtonItem?.style = .done
        updateSaveState()
    }

    /// Saved/template order initially; new selections append in tap order.
    private var binds: [String] {
        selected
    }

    private func toggleSelection(_ bind: String) -> Bool {
        if let index = selected.firstIndex(of: bind) {
            selected.remove(at: index)
        } else {
            guard selected.count < GameOverlayLayoutData.Combo.keyRange.upperBound else { return false }
            selected.append(bind)
        }
        return true
    }

    private var previewTitle: GameOverlayComboTitle? {
        let parts = binds.compactMap { bind in keys.first { $0.bind.rawValue == bind }?.titlePart }
        return parts.isEmpty ? nil : GameOverlayComboTitle(parts: parts)
    }

    private var isComplete: Bool {
        GameOverlayLayoutData.Combo.keyRange.contains(selected.count) && (selected.count != 1 || turbo)
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

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let text = headerTitle(for: section) else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as! RGSectionHeaderView
        header.text = text
        return header
    }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let text = footerTitle(for: section) else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as! RGSectionFooterView
        footer.text = text
        return footer
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section] == .keys ? keys.count : 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.separatorInset = .zero
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
            toggle.isEnabled = selected.count != 1
            toggle.onTintColor = .mainColor
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }
                turbo = toggle.isOn
                multiKeyTurbo = turbo
                refreshPreview()
            }, for: .valueChanged)
            cell.accessoryView = toggle
        case .visibility:
            cell.selectionStyle = .none
            content.text = Bundle.localizedString(forKey: "overlay_combo_show_current_orientation")
            let toggle = UISwitch()
            toggle.isOn = shown
            toggle.onTintColor = .mainColor
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                self?.shown = toggle?.isOn ?? true
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

    private func headerTitle(for section: Int) -> String? {
        sections[section] == .keys ? Bundle.localizedString(forKey: "overlay_combo_keys") : nil
    }

    private func footerTitle(for section: Int) -> String? {
        switch sections[section] {
        case .keys:
            return Bundle.localizedString(forKey: "overlay_combo_keys_footer")
        case .turbo:
            return Bundle.localizedString(forKey: "overlay_combo_turbo_footer")
        case .preview, .visibility, .delete:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .keys:
            let bind = keys[indexPath.row].bind.rawValue
            guard toggleSelection(bind) else {
                Vibration.error.vibrate()
                return
            }
            Vibration.selection.vibrate()
            turbo = selected.count == 1 ? true : multiKeyTurbo
            updateSaveState()
            tableView.reloadData()
        case .delete:
            didFinish = true
            onDelete?()
            closeSheet()
        case .preview, .turbo, .visibility:
            break
        }
    }

    private func configurePreview(_ cell: UITableViewCell) {
        var content = cell.defaultContentConfiguration()
        let font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        if let previewTitle {
            let title = GameOverlayComboTitle(parts: previewTitle.parts + (turbo ? [.symbol("bolt.fill", text: "⚡")] : []))
            let text = NSMutableAttributedString(attributedString: title.attributedString(font: font, joined: false, minimumSpacing: 0.25))
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

    /// Commit once, whether saved explicitly or by dismissing an existing button.
    @discardableResult
    private func commit() -> Bool {
        guard !didFinish, isComplete, !isDuplicate else { return false }
        didFinish = true
        let id = combo?.id ?? GameOverlayLayoutData.Combo.makeId(binds: binds, reservedIds: reservedIds)
        onSave?(GameOverlayLayoutData.Combo(id: id, binds: binds, turbo: turbo), shown)
        return true
    }

    private func save() {
        guard commit() else { return }
        closeSheet()
    }

    private func closeSheet() {
        // Dismiss the entire navigation sheet even if the unsaved-draft alert
        // is still being dismissed by UIKit.
        if let presenter = navigationController?.presentingViewController {
            presenter.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        if didFinish { return true }
        if combo != nil { return isComplete && !isDuplicate }
        // An empty new form may be dismissed directly; recommendations and
        // selected keys are drafts that must be explicitly saved or discarded.
        return selected.isEmpty && !turbo
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if combo != nil { commit() }
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        guard !didFinish else { return }
        if combo != nil {
            // Invalid/duplicate edits stay open; the existing preview explains why.
            refreshPreview()
            Vibration.error.vibrate()
            return
        }
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "overlay_combo_unsaved_title"),
                                      message: Bundle.localizedString(forKey: "overlay_combo_unsaved_message"), preferredStyle: .alert)
        let save = UIAlertAction(title: Bundle.localizedString(forKey: "overlay_layout_save"), style: .default) { [weak self] _ in
            self?.save()
        }
        save.isEnabled = isComplete && !isDuplicate
        alert.addAction(save)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "overlay_combo_discard"), style: .destructive) { [weak self] _ in
            self?.didFinish = true
            self?.closeSheet()
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        present(alert, animated: true)
    }
}
