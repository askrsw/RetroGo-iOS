//
//  GameSettingViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/3/23.
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

final class GameSettingViewController: UIViewController {
    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
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
        navigationItem.title = Bundle.localizedString(forKey: "gamesetting_title")

        let icon = UIImage(systemName: "xmark.circle")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: icon, landscapeImagePhone: icon, style: .plain, target: self, action: #selector(closeAction(_:)))
        navigationItem.leftBarButtonItem?.tintColor = .mainColor

        _ = tableView
        _ = dataSource

        applySnapshot(animated: false)
    }
}

extension GameSettingViewController {
    typealias DataSource = UITableViewDiffableDataSource<Section, Item>
    typealias Snapshot   = NSDiffableDataSourceSnapshot<Section, Item>

    enum Section: Hashable {
        case test
    }

    enum Item: Hashable {
        case retroArchOverlay
        case spritkitOverlay
    }

    private func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.estimatedRowHeight = 50
        tableView.tintColor = .mainColor
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        return tableView
    }

    private  func configDS() -> DataSource {
        let ds = DataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self = self else { return nil }

            let cellBuilder = {
                if let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell") {
                    return cell
                } else {
                    return UITableViewCell(style: .default, reuseIdentifier: "UITableViewCell")
                }
            }

            switch item {
                case .retroArchOverlay:
                    let switchControl = UISwitch()
                    switchControl.isOn = GamePageViewController.instance?.useRetroArchOverlay ?? false
                    switchControl.onTintColor = .mainColor
                    switchControl.addTarget(self, action: #selector(useRetroArchOverlayChanged(_:)), for: .valueChanged)
                    let cell = cellBuilder()
                    cell.imageView?.image = UIImage(systemName: "circle.grid.3x3.fill")
                    cell.textLabel?.text = "RetroArch Overlay"
                    cell.accessoryView = switchControl
                    return cell
                case .spritkitOverlay:
                    let switchControl = UISwitch()
                    switchControl.isOn = GamePageViewController.instance?.useSpriteKitOverlay ?? true
                    switchControl.onTintColor = .mainColor
                    switchControl.addTarget(self, action: #selector(useSpriteKitOverlayChanged(_:)), for: .valueChanged)
                    let cell = cellBuilder()
                    cell.imageView?.image = UIImage(systemName: "square.stack.3d.down.right")
                    cell.textLabel?.text = "SpriteKit Overlay"
                    cell.accessoryView = switchControl
                    return cell
            }
        }
        return ds
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = Snapshot()
        snapshot.appendSections([.test])

        let testItems: [Item] = [.retroArchOverlay, .spritkitOverlay]
        snapshot.appendItems(testItems, toSection: .test)

        dataSource.apply(snapshot, animatingDifferences: animated)
    }
}

extension GameSettingViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        50
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        default: return false
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension GameSettingViewController {

    @objc
    private func useSpriteKitOverlayChanged(_ sender: UISwitch) {
        GamePageViewController.instance?.useSpriteKitOverlay = sender.isOn
    }

    @objc
    private func useRetroArchOverlayChanged(_ sender: UISwitch) {
        GamePageViewController.instance?.useRetroArchOverlay = sender.isOn
    }

    @objc
    private func closeAction(_ sender: Any) {
        navigationController?.dismiss(animated: true)
    }
}
