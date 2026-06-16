//
//  GameCheatCatalogGameViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/11.
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

final class GameCheatCatalogGameViewController: UIViewController {

    private let platformId: Int
    private let game: RAGameEntry
    private weak var session: GameCheatSession?
    private var cheats: [RACheatItem] = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private let applyContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let applyButton = UIButton(type: .system)

    init(platformId: Int, game: RAGameEntry, session: GameCheatSession? = nil) {
        self.platformId = platformId
        self.game = game
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = game.localizedDisplayNameWithVariantSuffix
        configureTable()
        configureApplyButton()
        loadCheats()
    }

    private func configureTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70
        tableView.register(GameCheatCatalogTextCell.self, forCellReuseIdentifier: "Cheat")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        tableView.contentInset.bottom = session == nil ? 0 : 92
        tableView.verticalScrollIndicatorInsets.bottom = session == nil ? 0 : 92

        emptyLabel.text = Bundle.localizedString(forKey: "cheat_catalog_game_empty")
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .boldSystemFont(ofSize: UIFont.labelFontSize)
    }

    private func configureApplyButton() {
        guard session != nil else { return }

        applyContainer.layer.cornerRadius = 24
        applyContainer.layer.masksToBounds = true
        applyContainer.alpha = 0.90
        applyContainer.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.16)
        applyContainer.layer.borderColor = UIColor.separator.withAlphaComponent(0.55).cgColor
        applyContainer.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.addSubview(applyContainer)
        applyContainer.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(20)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(12)
            make.height.equalTo(56)
        }

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "checkmark.circle")
        config.imagePadding = 10
        config.baseForegroundColor = .mainColor
        config.title = Bundle.localizedString(forKey: "cheat_catalog_use_template")
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .boldSystemFont(ofSize: 18)
            return outgoing
        }
        applyButton.configuration = config
        applyButton.addTarget(self, action: #selector(applyTemplateAction), for: .touchUpInside)
        applyContainer.contentView.addSubview(applyButton)
        applyButton.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func loadCheats() {
        guard game.gameId > 0 else {
            tableView.backgroundView = emptyLabel
            return
        }
        RACheatCatalogManager.shared().fetchCheats(forGameId: game.gameId) { [weak self] cheats, error in
            guard let self else { return }
            if let error {
                self.showError(error)
                return
            }
            self.cheats = cheats
            self.tableView.reloadData()
            self.tableView.backgroundView = cheats.isEmpty ? self.emptyLabel : nil
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "cheat_catalog_error_title"),
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }

    @objc
    private func applyTemplateAction() {
        Vibration.selection.vibrate()
        guard let session else { return }
        if let binding = session.templateBinding,
           binding.isBound,
           !binding.matches(catalogGame: game) {
            let alert = UIAlertController(
                title: Bundle.localizedString(forKey: "cheat_catalog_replace_title"),
                message: Bundle.localizedString(forKey: "cheat_catalog_replace_message"),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
            alert.addAction(UIAlertAction(
                title: Bundle.localizedString(forKey: "cheat_catalog_replace_action"),
                style: .destructive) { [weak self] _ in
                    self?.bindCurrentTemplate()
                })
            present(alert, animated: true)
            return
        }
        bindCurrentTemplate()
    }

    private func bindCurrentTemplate() {
        guard let session else { return }
        guard session.bindTemplate(game) else {
            showError(NSError(
                domain: "GameCheatCatalog",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: Bundle.localizedString(forKey: "cheat_catalog_bind_failed")]))
            return
        }
        session.reloadTemplateItems {}
        AppToastManager.shared.toast(Bundle.localizedString(forKey: "cheat_catalog_bind_done"), context: .ui, level: .success)
        navigationController?.popViewController(animated: true)
    }
}

extension GameCheatCatalogGameViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cheats.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cheat", for: indexPath)
        let cheat = cheats[indexPath.row]
        (cell as? GameCheatCatalogTextCell)?.configure(
            text: cheat.desc,
            secondaryText: Self.subtitle(for: cheat),
            secondaryNumberOfLines: 2)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()
        navigationController?.pushViewController(
            GameCheatCatalogDetailViewController(cheat: cheats[indexPath.row], session: session),
            animated: true)
    }

    private static func subtitle(for cheat: RACheatItem) -> String {
        if cheat.handler == .RETRO {
            return String(
                format: Bundle.localizedString(forKey: "cheat_retro_subtitle_format"),
                hex(cheat.address),
                hex(cheat.value))
        }
        return cheat.code
    }

    private static func hex(_ value: UInt) -> String {
        String(format: "%X", value)
    }
}
