//
//  DiscoverGameListViewController.swift
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

final class DiscoverGameListViewController: UIViewController {

    // MARK: - Types

    private enum Section: Hashable { case main }
    private typealias DataSource = UITableViewDiffableDataSource<Section, NSNumber>
    private typealias Snapshot   = NSDiffableDataSourceSnapshot<Section, NSNumber>

    // MARK: - Constants

    private let pageSize = 50

    // MARK: - Platform

    let platform: RAPlatformItem

    // MARK: - Browse state

    private var browseGames:      [RAGameEntry] = []
    private var browseOffset:     Int           = 0
    private var browseTotalCount: Int           = 0
    private var isLoadingPage:    Bool          = false
    private var hasMorePages:     Bool          { browseGames.count < browseTotalCount }

    // MARK: - Search state

    private var isSearchActive:   Bool          = false
    private var searchResults:    [RAGameEntry] = []
    private var searchDebounce:   DispatchWorkItem?

    // MARK: - Notification token

    /// Retained token for the cover-did-load observer; removed in deinit.
    private var coverObserverToken: NSObjectProtocol?

    // MARK: - Lookup (gameId → entry)

    private var gameById: [Int: RAGameEntry] = [:]

    // MARK: - Views

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.delegate      = self
        tv.rowHeight     = DiscoverGameCell.rowHeight
        tv.tintColor     = .mainColor
        tv.refreshControl = refreshControl
        tv.register(DiscoverGameCell.self,
                    forCellReuseIdentifier: DiscoverGameCell.reuseID)
        view.addSubview(tv)
        tv.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return tv
    }()

    private lazy var dataSource: DataSource = {
        DataSource(tableView: tableView) { [weak self] tableView, indexPath, gameId in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DiscoverGameCell.reuseID,
                for: indexPath) as! DiscoverGameCell
            if let self, let game = self.gameById[gameId.intValue] {
                cell.configure(with: game, platform: self.platform)
            }
            return cell
        }
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return rc
    }()

    // MARK: - Init

    init(platform: RAPlatformItem) {
        self.platform = platform
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = platform.displayName
        // Prevent the long platform name from becoming the back button title
        // on the next level (Game Detail), which causes a width-==0 layout conflict.
        navigationItem.backButtonDisplayMode = .minimal

        setupSearch()

        _ = tableView
        _ = dataSource

        // Observe cover-loaded events posted by DiscoverGameDetailViewController.
        // Use the block-based API (returns a token) so we can capture [weak self]
        // without needing an @objc selector.  The token is stored so deinit can
        // cleanly remove only this observer.
        coverObserverToken = NotificationCenter.default.addObserver(
            forName:  .discoverCoverDidLoad,
            object:   nil,
            queue:    .main
        ) { [weak self] notification in
            self?.handleCoverDidLoad(notification)
        }

        loadFirstPage()
    }

    deinit {
        if let token = coverObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Restore pinned search bar when coming back from detail page.
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // ⚠️ UIKit bug workaround: with hidesSearchBarWhenScrolling = false,
        // pushing a child VC causes UISearchController to float to the screen
        // bottom and blocks the navigation transition for ~3 seconds.
        // Temporarily re-enabling scroll-hide lets the search bar animate away
        // cleanly before the push completes.
        navigationItem.hidesSearchBarWhenScrolling = true
    }

    // MARK: - Search setup

    private func setupSearch() {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = Bundle.localizedString(forKey: "discover_search_placeholder")
        sc.delegate = self
        navigationItem.searchController = sc
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    // MARK: - Browse: load pages

    private func loadFirstPage() {
        browseGames      = []
        browseOffset     = 0
        browseTotalCount = 0
        isLoadingPage    = false
        gameById.removeAll()
        loadNextPage()
    }

    private func loadNextPage() {
        guard !isLoadingPage, !isSearchActive else { return }
        guard browseOffset == 0 || hasMorePages   else { return }

        isLoadingPage = true
        let offset    = browseOffset

        RAGameRDBManager.shared().fetchGames(
            forPlatformId:  platform.platformId,
            offset:         offset,
            limit:          pageSize,
            knownTotalCount: platform.gameCount   // skip redundant COUNT(*) query
        ) { [weak self] games, totalCount, error in
            guard let self else { return }
            self.isLoadingPage    = false
            self.refreshControl.endRefreshing()

            if let error {
                NSLog("[DiscoverGameList] fetchGames error: %@", error.localizedDescription)
                return
            }

            self.browseTotalCount = totalCount
            self.browseOffset    += games.count
            self.browseGames     += games
            games.forEach { self.gameById[$0.gameId] = $0 }

            // Append-only: no animation on initial load, animate only when
            // adding subsequent pages (avoids visual jump on first render).
            self.applyBrowseSnapshot(animated: offset > 0)
        }
    }

    // MARK: - Search

    private func performSearch(keyword: String) {
        RAGameRDBManager.shared().searchGames(
            withKeyword: keyword,
            platformId: platform.platformId
        ) { [weak self] games, error in
            guard let self else { return }
            if let error {
                NSLog("[DiscoverGameList] search error: %@", error.localizedDescription)
                return
            }
            self.searchResults = games
            games.forEach { self.gameById[$0.gameId] = $0 }
            self.applySearchSnapshot()
        }
    }

    // MARK: - Snapshots

    private func applyBrowseSnapshot(animated: Bool = false) {
        var snap = Snapshot()
        snap.appendSections([.main])
        snap.appendItems(browseGames.map { NSNumber(value: $0.gameId) }, toSection: .main)
        dataSource.apply(snap, animatingDifferences: animated)
    }

    private func applySearchSnapshot() {
        var snap = Snapshot()
        snap.appendSections([.main])
        snap.appendItems(searchResults.map { NSNumber(value: $0.gameId) }, toSection: .main)
        dataSource.apply(snap, animatingDifferences: true)
    }

    // MARK: - Actions

    @objc
    private func pullToRefresh() {
        guard !isSearchActive else {
            refreshControl.endRefreshing()
            return
        }
        loadFirstPage()
    }

    // MARK: - Cover notification

    /// Called on the main queue when a cover image has been successfully loaded
    /// in DiscoverGameDetailViewController.  Only updates the currently visible
    /// cell for the matching game — no network work is performed here.
    private func handleCoverDidLoad(_ notification: Notification) {
        guard
            let gameId = notification.userInfo?[DiscoverCoverNotificationKey.gameId] as? Int,
            let image  = notification.userInfo?[DiscoverCoverNotificationKey.image]  as? UIImage
        else { return }

        // Find the index path for this game in the current snapshot.
        guard let indexPath = dataSource.indexPath(for: NSNumber(value: gameId)) else { return }

        // Only update if the cell is currently visible — dequeued cells will
        // read from the memory cache in configure(with:platform:) when they scroll in.
        guard let cell = tableView.cellForRow(at: indexPath) as? DiscoverGameCell else { return }

        cell.setCoverImage(image)
    }
}

// MARK: - UITableViewDelegate

extension DiscoverGameListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()

        guard let gameId = dataSource.itemIdentifier(for: indexPath),
              let game   = gameById[gameId.intValue]
        else { return }

        let vc = DiscoverGameDetailViewController(game: game, platform: platform)
        navigationController?.pushViewController(vc, animated: true)
    }

    func tableView(_ tableView: UITableView,
                   willDisplay cell: UITableViewCell,
                   forRowAt indexPath: IndexPath) {
        guard !isSearchActive, !isLoadingPage, hasMorePages else { return }
        if indexPath.row >= browseGames.count - 10 {
            loadNextPage()
        }
    }
}

// MARK: - UISearchResultsUpdating

extension DiscoverGameListViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        let keyword = searchController.searchBar.text?
            .trimmingCharacters(in: .whitespaces) ?? ""

        searchDebounce?.cancel()

        if keyword.isEmpty {
            applyBrowseSnapshot()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.performSearch(keyword: keyword)
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

// MARK: - UISearchControllerDelegate

extension DiscoverGameListViewController: UISearchControllerDelegate {

    func willPresentSearchController(_ searchController: UISearchController) {
        isSearchActive = true
    }

    func willDismissSearchController(_ searchController: UISearchController) {
        isSearchActive = false
        searchResults  = []
        applyBrowseSnapshot()
    }
}
