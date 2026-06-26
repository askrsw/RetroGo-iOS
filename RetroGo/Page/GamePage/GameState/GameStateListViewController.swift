//
//  GameStateListViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

final class GameStateListViewController: UIViewController {

    enum Mode {
        /// Returns the persisted item on success (nil on failure) so the list can
        /// reflect the save before dismissing.
        case load
        case save(onSave: (_ rawName: String, _ showName: String, _ isOverwrite: Bool) -> RetroRomGameStateItem?)
    }

    private enum Section {
        case newSave
        case manualSaves
        case autoSaves
    }

    private var gamePauseLease: GamePauseCoordinator.Lease?

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let showClose: Bool
    private let mode: Mode

    private var gameStateItems: [RetroRomGameStateItem] {
        didSet {
            updateEmptyState()
        }
    }

    weak var activeTextField: UITextField?

    private let emptyLabel = UILabel()

    private var isSaveMode: Bool {
        if case .save = mode { return true }
        return false
    }

    private var manualItems: [RetroRomGameStateItem] {
        gameStateItems.filter { !$0.isAutoSaved }
    }

    private var autoItems: [RetroRomGameStateItem] {
        gameStateItems.filter { $0.isAutoSaved }
    }

    private var activeSections: [Section] {
        var result: [Section] = []
        if isSaveMode {
            result.append(.newSave)
            result.append(.manualSaves)
        } else {
            // Auto save goes first: it is usually the most recent capture and there
            // is only one of it, so it shouldn't be buried below a long manual list.
            if !autoItems.isEmpty { result.append(.autoSaves) }
            if !manualItems.isEmpty { result.append(.manualSaves) }
        }
        return result
    }

    init(gameStateItems: [RetroRomGameStateItem], showClose: Bool = true, mode: Mode = .load) {
        self.gameStateItems = gameStateItems
        self.showClose = showClose
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        gamePauseLease = acquireGamePause(reason: "game-state-list")
        attachGamePauseLeaseToPresentation(gamePauseLease)

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: isSaveMode ? "gamestate_save_state" : "gamestate_load_state")

        if showClose {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), landscapeImagePhone: UIImage(systemName: "xmark.circle"), style: .plain, target: self, action: #selector(closeAction(_:)))
            navigationItem.leftBarButtonItem?.tintColor = .label
        }

        tableView.dataSource = self
        tableView.delegate   = self
        tableView.rowHeight  = GameStateTableViewCell.cellHeight
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "HintFooter")
        tableView.estimatedSectionFooterHeight = 32
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .boldSystemFont(ofSize: UIFont.labelFontSize)

        updateEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        attachGamePauseLeaseToPresentation(gamePauseLease)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)

        if isClosingOrBeingDismissedFromGamePauseContext() {
            gamePauseLease?.release()
            gamePauseLease = nil
        }
    }

    func deleteGameState(_ item: RetroRomGameStateItem) {
        activeTextField?.resignFirstResponder()
        activeTextField = nil

        guard let row = gameStateItems.firstIndex(where: { $0.coreId == item.coreId && $0.sha256 == item.sha256 && $0.rawName == item.rawName }) else {
            return
        }

        let section: Int
        if item.isAutoSaved {
            section = activeSections.firstIndex(of: .autoSaves) ?? 0
        } else {
            section = activeSections.firstIndex(of: .manualSaves) ?? 0
        }
        let rowInSection = item.isAutoSaved
            ? autoItems.firstIndex(where: { $0.rawName == item.rawName }) ?? 0
            : manualItems.firstIndex(where: { $0.rawName == item.rawName }) ?? 0
        let indexPath = IndexPath(row: rowInSection, section: section)

        DispatchQueue.global().async { [self] in
            RetroRomFileManager.shared.deleteGameStateItem(item)
            DispatchQueue.main.async { [self] in
                gameStateItems.remove(at: row)
                if activeSections.contains(item.isAutoSaved ? .autoSaves : .manualSaves) {
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                } else {
                    tableView.reloadData()
                }
                NotificationCenter.default.post(name: .deleteGameState, object: item)
            }
        }
    }

    func updateGameState(_ item: RetroRomGameStateItem) {
        guard let row = gameStateItems.firstIndex(where: { $0.coreId == item.coreId && $0.sha256 == item.sha256 && $0.rawName == item.rawName }) else {
            return
        }
        gameStateItems[row] = item
    }
}

extension GameStateListViewController {

    private func updateEmptyState() {
        if gameStateItems.isEmpty && !isSaveMode {
            emptyLabel.text = Bundle.localizedString(forKey: "gamestate_empty_tip")
            tableView.backgroundView = emptyLabel
        } else {
            tableView.backgroundView = nil
        }
    }

    // MARK: - Save mode

    private func newSaveCell(for indexPath: IndexPath) -> UITableViewCell {
        let cellId = "NewSaveCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId) ?? UITableViewCell(style: .default, reuseIdentifier: cellId)
        var config = cell.defaultContentConfiguration()
        config.image = UIImage(systemName: "plus.circle.fill")
        config.imageProperties.tintColor = .systemBlue
        config.text = Bundle.localizedString(forKey: "gamestate_new_save")
        config.textProperties.font = .boldSystemFont(ofSize: UIFont.labelFontSize + 1)
        cell.contentConfiguration = config
        cell.accessoryType = .none
        return cell
    }

    private func presentNewSaveAlert() {
        guard case .save(let onSave) = mode else { return }

        if !gameStateItems.isEmpty,
           !AppStoreProFeatureGate.shared.requirePro(feature: .manualSaveSlot, presentation: .alert) {
            return
        }

        let title = Bundle.localizedString(forKey: "gamepage_save_state")
        let message = Bundle.localizedString(forKey: "gamepage_input_state_name")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            let nowString = DateFormatter.yyyyMMddHHmmss().string(from: Date())
            textField.placeholder = Bundle.localizedString(forKey: "gamepage_name_state")
            textField.text = nowString
        }
        let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel)
        alert.addAction(cancelAction)
        let okAction = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let rawName = DateFormatter.yyyyMMddHHmmss().string(from: Date())
            let input = alert?.textFields?.first?.text ?? ""
            let showName = input.isEmpty ? rawName : input
            let saved = onSave(rawName, showName, false)
            self.finishSave(saved, isOverwrite: false)
        }
        alert.addAction(okAction)
        alert.view.tintColor = .label
        present(alert, animated: true)
    }

    private func presentOverwriteConfirm(for item: RetroRomGameStateItem) {
        guard case .save(let onSave) = mode else { return }

        let title = String(format: Bundle.localizedString(forKey: "gamestate_overwrite_confirm"), item.itemName)
        let message = Bundle.localizedString(forKey: "gamestate_overwrite_message")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel)
        alert.addAction(cancelAction)
        let overwriteAction = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            let saved = onSave(item.rawName, item.itemName, true)
            self.finishSave(saved, isOverwrite: true)
        }
        alert.addAction(overwriteAction)
        alert.view.tintColor = .label
        present(alert, animated: true)
    }

    /// Reflect the save in the list (insert for new, refresh row for overwrite),
    /// let the user see it land, then dismiss.
    private func finishSave(_ item: RetroRomGameStateItem?, isOverwrite: Bool) {
        guard let item else {
            navigationController?.dismiss(animated: true)
            return
        }
        applySavedItem(item, isOverwrite: isOverwrite)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.navigationController?.dismiss(animated: true)
        }
    }

    private func applySavedItem(_ item: RetroRomGameStateItem, isOverwrite: Bool) {
        guard let manualSection = activeSections.firstIndex(of: .manualSaves) else {
            tableView.reloadData()
            return
        }

        if isOverwrite,
           let row = gameStateItems.firstIndex(where: { $0.coreId == item.coreId && $0.sha256 == item.sha256 && $0.rawName == item.rawName }) {
            // Refresh the tapped row in place (new timestamp) so the user's eyes
            // stay on the save they just overwrote.
            gameStateItems[row] = item
            let rowInSection = manualItems.firstIndex(where: { $0.rawName == item.rawName }) ?? 0
            tableView.reloadRows(at: [IndexPath(row: rowInSection, section: manualSection)], with: .fade)
        } else {
            let wasEmpty = manualItems.isEmpty
            gameStateItems.insert(item, at: 0)
            if wasEmpty {
                // First manual save: the section gains its header/footer too.
                tableView.reloadData()
            } else {
                tableView.insertRows(at: [IndexPath(row: 0, section: manualSection)], with: .automatic)
            }
        }
    }

    @objc
    private func closeAction(_ sender: Any) {
        Vibration.selection.vibrate()
        navigationController?.dismiss(animated: true)
    }

    @objc
    private func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0)
        }
    }

    @objc
    private func keyboardWillHide(notification: NSNotification) {
        tableView.contentInset = UIEdgeInsets.zero
    }
}

extension GameStateListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        activeSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch activeSections[section] {
        case .newSave:     return 1
        case .manualSaves: return manualItems.count
        case .autoSaves:   return autoItems.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch activeSections[indexPath.section] {
        case .newSave:
            return newSaveCell(for: indexPath)
        case .manualSaves:
            let cell = dequeueStateCell()
            cell.item = manualItems[indexPath.row]
            if isSaveMode {
                cell.deleteButton.isHidden = true
                cell.titleTextField.isEnabled = false
            }
            return cell
        case .autoSaves:
            let cell = dequeueStateCell()
            cell.item = autoItems[indexPath.row]
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        activeTextField?.resignFirstResponder()
        activeTextField = nil

        switch activeSections[indexPath.section] {
        case .newSave:
            presentNewSaveAlert()
        case .manualSaves where isSaveMode:
            presentOverwriteConfirm(for: manualItems[indexPath.row])
        case .manualSaves:
            loadState(manualItems[indexPath.row])
        case .autoSaves:
            loadState(autoItems[indexPath.row])
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let key: String
        switch activeSections[section] {
        case .newSave:
            return nil
        case .manualSaves:
            key = isSaveMode ? "gamestate_section_existing" : "gamestate_section_manual"
        case .autoSaves:
            key = "gamestate_section_auto"
        }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as? RGSectionHeaderView
            ?? RGSectionHeaderView(reuseIdentifier: RGSectionHeaderView.className)
        view.text = Bundle.localizedString(forKey: key)
        view.horizontalInset = 20
        // In a plain-style table the header floats/pins, so give it a solid
        // background to keep scrolling rows from showing through behind the title.
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .systemBackground
        view.backgroundConfiguration = background
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        activeSections[section] == .newSave ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        // Hint sits under the "new save" row (and above the existing list) so the
        // user learns about overwrite before tapping any existing save.
        guard isSaveMode, activeSections[section] == .newSave, !manualItems.isEmpty else { return nil }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "HintFooter")
            ?? UITableViewHeaderFooterView(reuseIdentifier: "HintFooter")
        var config = UIListContentConfiguration.plainFooter()
        config.text = Bundle.localizedString(forKey: "gamestate_overwrite_hint")
        view.contentConfiguration = config
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .systemBackground
        view.backgroundConfiguration = background
        return view
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if isSaveMode, activeSections[section] == .newSave, !manualItems.isEmpty {
            return UITableView.automaticDimension
        }
        return .leastNormalMagnitude
    }

    // MARK: - Helpers

    private func dequeueStateCell() -> GameStateTableViewCell {
        let cellId = "GameStateTableViewCell"
        if let cell = tableView.dequeueReusableCell(withIdentifier: cellId) as? GameStateTableViewCell {
            cell.deleteButton.isHidden = false
            cell.titleTextField.isEnabled = true
            return cell
        }
        return GameStateTableViewCell(style: .default, reuseIdentifier: cellId)
    }

    private func loadState(_ item: RetroRomGameStateItem) {
        let str: String
        if RetroArchX.shared().loadState(from: item.statePath) {
            str = String(format: Bundle.localizedString(forKey: "gamestate_state_loaded"), item.itemName)
        } else {
            str = String(format: Bundle.localizedString(forKey: "gamestate_state_load_failed"), item.itemName)
        }

        let msg = EmuInGameMessage(message: str, title: nil, type: .info, duration: 3.5, priority: 0)
        NotificationCenter.default.post(name: .showInGameMessage, object: msg)

        navigationController?.dismiss(animated: true)
    }
}
