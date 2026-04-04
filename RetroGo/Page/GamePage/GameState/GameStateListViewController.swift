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
    private let tableView = UITableView(frame: .zero, style: .plain)

    private let showClose: Bool

    private var gameStateItems: [RetroRomGameStateItem] {
        didSet {
            updateTipLabel()
        }
    }

    weak var activeTextField: UITextField?

    private let tipLabel = UILabel(frame: .zero)

    init(gameStateItems: [RetroRomGameStateItem], showClose: Bool = true) {
        self.gameStateItems = gameStateItems
        self.showClose = showClose
        super.init(nibName: nil, bundle: nil)

        RetroArchX.shared().pause()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        RetroArchX.shared().resume()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "gamestate_load_state")

        if showClose {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), landscapeImagePhone: UIImage(systemName: "xmark.circle"), style: .plain, target: self, action: #selector(closeAction(_:)))
            navigationItem.leftBarButtonItem?.tintColor = .mainColor
        }

        tableView.dataSource = self
        tableView.delegate   = self
        tableView.rowHeight  = GameStateTableViewCell.cellHeight
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }

        updateTipLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    func deleteGameState(_ item: RetroRomGameStateItem) {
        activeTextField?.resignFirstResponder()
        activeTextField = nil

        guard let row = gameStateItems.firstIndex(where: { $0.coreId == item.coreId && $0.sha256 == item.sha256 && $0.rawName == item.rawName }) else {
            return
        }
        let indexPath = IndexPath(row: row, section: 0)

        DispatchQueue.global().async { [self] in
            RetroRomFileManager.shared.deleteGameStateItem(item)
            DispatchQueue.main.async { [self] in
                gameStateItems.remove(at: row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
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

    private func updateTipLabel() {
        if gameStateItems.count == 0 {
            tipLabel.text = Bundle.localizedString(forKey: "gamestate_empty_tip")
            tipLabel.textAlignment = .center
            tipLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
            view.addSubview(tipLabel)
            tipLabel.snp.makeConstraints { make in
                make.center.equalToSuperview()
            }
            view.bringSubviewToFront(tipLabel)
        } else {
            tipLabel.removeFromSuperview()
        }
    }

    @objc
    private func closeAction(_ sender: Any) {
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
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        gameStateItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = { () -> GameStateTableViewCell in
            let cellId = "GameStateTableViewCell"
            if let cell = tableView.dequeueReusableCell(withIdentifier: cellId) as? GameStateTableViewCell {
                return cell
            } else {
                let cell = GameStateTableViewCell(style: .default, reuseIdentifier: cellId)
                return cell
            }
        }()

        cell.item = gameStateItems[indexPath.row]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        activeTextField?.resignFirstResponder()
        activeTextField = nil

        let str: String
        let item = gameStateItems[indexPath.row]
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
