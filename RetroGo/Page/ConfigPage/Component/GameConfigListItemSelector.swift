//
//  GameConfigListItemSelector.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/24.
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

final class GameConfigListItemSelector: UIViewController {
    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    private var oldSelectedIndex: IndexPath?

    let entry: GameConfigEntry

    init(entry: GameConfigEntry) {
        self.entry      = entry
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = entry.title

        _ = tableView
        _ = dataSource
        applySnapshot(animated: false)
    }
}

extension GameConfigListItemSelector {
    typealias DataSource = UITableViewDiffableDataSource<String, Item>
    typealias Snapshot   = NSDiffableDataSourceSnapshot<String, Item>

    struct Item: Hashable {
        let title: String
        let value: AnyHashable
    }

    private func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
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
            guard let self = self else { return nil }
            let cell = {
                if let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell") {
                    return cell
                } else {
                    return UITableViewCell(style: .default, reuseIdentifier: "UITableViewCell")
                }
            }()
            cell.textLabel?.text = item.title
            cell.accessoryType = indexPath == oldSelectedIndex ? .checkmark : .none
            return cell
        }
        return ds
    }

    private func applySnapshot(animated: Bool) {
        guard let result = entry.getListArray?() else {
            return
        }

        oldSelectedIndex = nil
        if let selected = result.selected {
            oldSelectedIndex = IndexPath(item: selected, section: 0)
        }

        var snapshot = Snapshot()
        snapshot.appendSections(["main"])
        snapshot.appendItems(result.list.map({ Item(title: $0.title, value: $0.value) }))
        dataSource.apply(snapshot, animatingDifferences: animated)
    }
}

extension GameConfigListItemSelector: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        if let oldSelectedIndex {
            if let cell = tableView.cellForRow(at: oldSelectedIndex) {
                cell.accessoryType = .none
            }
        }

        if let cell = tableView.cellForRow(at: indexPath) {
            cell.accessoryType = .checkmark
        }
        oldSelectedIndex = indexPath

        if let item = dataSource.itemIdentifier(for: indexPath) {
            entry.setListSelectedValue?(item.value)
            entry.refresh.toggle()
        }
    }
}
