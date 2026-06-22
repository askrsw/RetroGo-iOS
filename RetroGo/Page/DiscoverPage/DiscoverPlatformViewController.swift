//
//  DiscoverPlatformViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/20.
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

final class DiscoverPlatformViewController: UIViewController {

    // MARK: - Types

    private enum Section: Hashable { case main }
    private typealias DataSource = UITableViewDiffableDataSource<Section, NSNumber>
    private typealias Snapshot   = NSDiffableDataSourceSnapshot<Section, NSNumber>

    // MARK: - State

    /// Cache fetched from SQLite; keyed by platformId for diffable uniqueness.
    private var platforms: [RAPlatformItem] = []

    /// KVO token — keeps observation alive as long as the VC is alive.
    private var rdbReadyObservation: NSKeyValueObservation?

    // MARK: - Views

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.delegate        = self
        tv.rowHeight       = DiscoverPlatformCell.rowHeight
        tv.tintColor       = .mainColor
        tv.isHidden        = true
        tv.register(DiscoverPlatformCell.self,
                    forCellReuseIdentifier: DiscoverPlatformCell.reuseID)
        view.addSubview(tv)
        tv.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return tv
    }()

    private lazy var dataSource: DataSource = {
        DataSource(tableView: tableView) { [weak self] tableView, indexPath, platformId in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DiscoverPlatformCell.reuseID,
                for: indexPath) as! DiscoverPlatformCell
            if let platform = self?.platforms.first(where: { $0.platformId == platformId.intValue }) {
                cell.configure(with: platform)
            }
            return cell
        }
    }()

    /// Shown while rdbReady == false.
    private lazy var loadingView: UIView = {
        let container = UIView()
        container.isHidden = true
        view.addSubview(container)
        container.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()

        let label = UILabel()
        label.text = Bundle.localizedString(forKey: "discover_building_database")
        label.textColor = .secondaryLabel
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis      = .vertical
        stack.spacing   = 20
        stack.alignment = .center

        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(100)
        }
        return container
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "discover_main_title")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        // Trigger lazy view/dataSource initialisation
        _ = tableView
        _ = dataSource
        _ = loadingView

    #if DEBUG
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(debugExportDatabase))
    #endif

        observeRdbReady()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh on every appearance to pick up newly imported platforms.
        if OnDemandResourceLoader.shared.rdbReady {
            reloadPlatforms()
        }
    }

    // MARK: - KVO

    private func observeRdbReady() {
        let loader = OnDemandResourceLoader.shared

        // In viewDidLoad the view is NOT yet in the window hierarchy.
        // Applying a diffable snapshot here forces a layout pass and triggers
        // "UITableView was told to layout its visible cells … without being in
        // the view hierarchy." — Fix: only update visibility here; actual data
        // is loaded in viewWillAppear once the view is in the hierarchy.
        let isReady = loader.rdbReady
        loadingView.isHidden = isReady
        tableView.isHidden   = !isReady

        // Observe future changes (e.g. database finishes building while this
        // VC is on screen). By the time rdbReady flips, the view IS in the
        // window, so applyReadyState is safe.
        rdbReadyObservation = loader.observe(\.rdbReady, options: [.new]) { [weak self] _, change in
            guard let self, let isReady = change.newValue else { return }
            // rdbReady is set on the main thread, so this fires on main thread.
            self.applyReadyState(isReady)
        }
    }

    // MARK: - State transitions

    private func applyReadyState(_ isReady: Bool) {
        if isReady {
            loadingView.isHidden = true
            tableView.isHidden   = false
            reloadPlatforms()
        } else {
            loadingView.isHidden = false
            tableView.isHidden   = true
        }
    }

    private func reloadPlatforms() {
        // allPlatforms() is synchronous and fast (small result set).
        platforms = RAGameRDBManager.shared().allPlatforms()

        var snapshot = Snapshot()
        snapshot.appendSections([.main])
        // Use platformId (wrapped as NSNumber) as the diffable identifier.
        snapshot.appendItems(platforms.map { NSNumber(value: $0.platformId) }, toSection: .main)
        // Only animate when the view is actually visible; otherwise a layout
        // pass outside the window hierarchy would reproduce the same warning.
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
    }
}

// MARK: - UITableViewDelegate

extension DiscoverPlatformViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()

        guard let platformId = dataSource.itemIdentifier(for: indexPath),
              let platform   = platforms.first(where: { $0.platformId == platformId.intValue })
        else { return }

        let vc = DiscoverGameListViewController(platform: platform)
        navigationController?.pushViewController(vc, animated: true)
    }
}

#if DEBUG
// MARK: - DEBUG：离线生成预制 sqlite

extension DiscoverPlatformViewController {

    @objc fileprivate func debugExportDatabase() {
        let progress = UIAlertController(title: "正在导出…",
                                         message: "从 .rdb 构建预制库，请稍候",
                                         preferredStyle: .alert)
        present(progress, animated: true)

        OnDemandResourceLoader.shared.debugExportCombinedDatabase { [weak self] path, error in
            // completion 已在主线程回调
            progress.dismiss(animated: true) {
                let title: String
                let message: String
                if let path {
                    title = "导出成功"
                    message = "已生成预制库：\n\(path)\n\n用 Devices and Simulators 或容器路径取出 gamerdb.sqlite，重命名后作为 ODR 资源打包。"
                } else {
                    title = "导出失败"
                    message = error?.localizedDescription ?? "未知错误"
                }
                let done = UIAlertController(title: title, message: message, preferredStyle: .alert)
                done.addAction(UIAlertAction(title: "好", style: .default))
                self?.present(done, animated: true)
            }
        }
    }
}
#endif // DEBUG
