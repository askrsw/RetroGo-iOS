//
//  RetroRomCoreListViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/26.
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

final class RetroRomCoreListViewController: UIViewController {
    enum Action {
        case showCoreInfo      // 进入 RetroRomCoreInfoViewController
        case configureCore     // 进入 GameConfigViewController（核心设置）

        var desc: String {
            switch self {
            case .showCoreInfo: return Bundle.localizedString(forKey: "info")
            case .configureCore: return Bundle.localizedString(forKey: "setting")
            }
        }

        var icon: UIImage {
            switch self {
            case .showCoreInfo:
                return IconRender.shared.settingsIcon(symbol: "cpu.fill", background: .systemOrange, size: CGSize(width: 22, height: 22))
            case .configureCore:
                return IconRender.shared.settingsIcon(symbol: "slider.horizontal.3", background: .systemGray, size: CGSize(width: 22, height: 22))
            }
        }
    }

    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    let action: Action

    init(action: Action) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "corelist_core_list") + " - \(action.desc)"
        navigationItem.titleView = makeTitleView()
        navigationItem.largeTitleDisplayMode = .never

        _ = tableView
        _ = dataSource

        applySnapshot()
    }
}

extension RetroRomCoreListViewController {
    enum Section: Hashable {
        case main
    }

    typealias DataSource = UITableViewDiffableDataSource<Section, EmuCoreInfoItem>
    typealias Snapshot   = NSDiffableDataSourceSnapshot<Section, EmuCoreInfoItem>

    private func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.delegate = self
        tableView.rowHeight = 60
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
        let ds = DataSource(tableView: tableView) { tableView, indexPath, item in
            let cell = {
                if let cell = tableView.dequeueReusableCell(withIdentifier: "RetroRomCoreItemTableViewCell") as? RetroRomCoreItemTableViewCell {
                    return cell
                } else {
                    return RetroRomCoreItemTableViewCell(style: .default, reuseIdentifier: "RetroRomCoreItemTableViewCell")
                }
            }()
            cell.coreInfoItem = item
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        return ds
    }

    private func applySnapshot() {
        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(RetroArchX.shared().allCores, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func makeTitleView() -> UIView? {
        let title = Bundle.localizedString(forKey: "corelist_core_list") + " - \(action.desc)"
        let icon  = action.icon
        return Self.makeIconTitleView(title, icon: icon)
    }
}

extension RetroRomCoreListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()
        if let item = dataSource.itemIdentifier(for: indexPath) {
            let controller: UIViewController
            switch action {
            case .showCoreInfo:
                controller = RetroRomCoreInfoViewController(coreInfoItem: item, showCloseButton: false, interactive: true)
            case .configureCore:
                let session = GameConfigSession(scope: .core, core: item, game: nil)
                controller = GameConfigViewController(session: session, applyInputBinding: true, showCloseButton: false)
            }
            navigationController?.pushViewController(controller, animated: true)
        }
    }
}
