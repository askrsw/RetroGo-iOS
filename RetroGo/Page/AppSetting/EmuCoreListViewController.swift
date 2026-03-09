//
//  EmuCoreListViewController.swift
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

final class EmuCoreListViewController: UIViewController {
    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "corelist_core_list")

        _ = tableView
        _ = dataSource

        applySnapshot()
    }
}

extension EmuCoreListViewController {
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
}

extension EmuCoreListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()
        if let item = dataSource.itemIdentifier(for: indexPath) {
            let controller = RetroRomCoreInfoViewController(coreInfoItem: item, showCloseButton: false, interactive: true)
            navigationController?.pushViewController(controller, animated: true)
        }
    }
}
