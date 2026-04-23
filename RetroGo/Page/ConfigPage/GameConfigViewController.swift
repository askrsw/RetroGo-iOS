//
//  GameConfigViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/18.
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

final class GameConfigViewController: UIViewController {
    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    let showCloseButton: Bool
    let session: GameConfigSession
    let sections: [GameConfigSection]
    let items: [[GameConfigItem]]

    init(session: GameConfigSession, showCloseButton: Bool = false) {
        self.showCloseButton = showCloseButton
        self.session  = session
        (self.sections, self.items) = GameConfigSection.makeConfigData(session: session)
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
        navigationItem.title = getMainTitle()

        if showCloseButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeAction))
            navigationItem.leftBarButtonItem?.tintColor = .label
        }

        _ = tableView
        _ = dataSource

        applySnapshot(animated: false)
    }
}

extension GameConfigViewController {
    @objc
    func closeAction() {
        dismiss(animated: true)
    }

    func getMainTitle() -> String {
        switch session.scope {
            case .global: return Bundle.localizedString(forKey: "configpage_global_setting")
            case .core: return Bundle.localizedString(forKey: "configpage_core_setting")
            case .game: return Bundle.localizedString(forKey: "configpage_rom_setting")
        }
    }
}

extension GameConfigViewController {
    typealias DataSource = UITableViewDiffableDataSource<GameConfigSection, GameConfigItem>
    typealias Snapshot   = NSDiffableDataSourceSnapshot<GameConfigSection, GameConfigItem>

    private func applySnapshot(animated: Bool) {
        guard sections.count == items.count else {
            return
        }

        var snapshot = Snapshot()
        snapshot.appendSections(sections)

        for index in 0 ..< sections.count {
            let section = sections[index]
            let sectionItems = items[index]
            snapshot.appendItems(sectionItems, toSection: section)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.estimatedRowHeight = 50
        tableView.estimatedSectionFooterHeight = 44
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.tintColor = .mainColor
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        return tableView
    }

    private func configDS() -> DataSource {
        let ds = DataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self = self else { return nil}
            switch item.type {
            case .game, .core: return makeCell(GameConfigTitleViewCell.self, config: item)
            case .logicThread: return makeCell(GameConfigSwitchViewCell.self, config: item)
            case .retroArchOverlay: return makeCell(GameConfigSwitchViewCell.self, config: item)
            case .spritkitOverlay: return makeCell(GameConfigSwitchViewCell.self, config: item)
            case .fastForwardMultiplier: return makeCell(GameConfigSegmentViewCell.self, config: item)
            }
        }
        return ds
    }

    private func dequeueCell<T: GameConfigBaseViewCell>(_ cellType: T.Type) -> T {
        let cellId = String(describing: cellType)
        if let cell = tableView.dequeueReusableCell(withIdentifier: cellId) as? T {
            return cell
        }
        return T(style: .default, reuseIdentifier: cellId)
    }

    private func makeCell<T: GameConfigBaseViewCell>(_ cellType: T.Type, config: GameConfigItem) -> UITableViewCell {
        let cell: T = dequeueCell(cellType)
        cell.config = config
        return cell
    }
}

extension GameConfigViewController: UITableViewDelegate {
    private func makeFooterView(_ text: String) -> UITableViewHeaderFooterView {
        let footer = {
            let viewId = "RetroRomConfigFooterView"
            if let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: viewId) as? GameConfigFooterView {
                return view
            } else {
                return GameConfigFooterView(reuseIdentifier: viewId)
            }
        }()
        footer.text = text
        return footer
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section < sections.count else { return nil }

        let text = sections[section].getSectionFooterText(session: session)
        guard let text, !text.isEmpty else { return nil }

        return makeFooterView(text)
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard section < sections.count else { return .leastNormalMagnitude }

        let text = sections[section].getSectionFooterText(session: session)
        if text?.isEmpty == false {
            return UITableView.automaticDimension
        }

        // Keep visual spacing between sections even when no footer text exists.
        return 20
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        false
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
