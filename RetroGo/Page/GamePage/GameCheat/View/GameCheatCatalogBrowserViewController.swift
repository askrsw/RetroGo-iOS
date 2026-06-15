//
//  GameCheatCatalogBrowserViewController.swift
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

import Combine
import UIKit
import SnapKit
import ObjcHelper
import RACoordinator

/// Browses the read-only cheat catalog for the current core's platform(s).
/// Search is intentionally limited to game names (English/RDB + localized name);
/// cheat descriptions/codes are not searched because cheat.sqlite is not indexed
/// for that workload.
final class GameCheatCatalogBrowserViewController: UIViewController {

    private enum Section {
        case match
        case templates
    }

    private enum MatchInfoRow {
        case gamerdb(entry: RAGameEntry, crc32: String)
        case binding(GameCheatTemplateBinding)
    }

    private let platformIds: [NSNumber]
    private weak var session: GameCheatSession?
    private let pageSize = 50

    private var infoRows: [MatchInfoRow] = []
    private var games: [RAGameEntry] = []
    private var totalCount = 0
    private var keyword = ""
    private var isLoading = false
    private var queryGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)
    private let searchText = PassthroughSubject<String, Never>()
    private let emptyLabel = UILabel()

    init(platformIds: [NSNumber], session: GameCheatSession? = nil) {
        self.platformIds = platformIds
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "cheat_catalog_title")
        let icon = IconRender.shared.settingsIcon(
            symbol: "star.circle",
            background: .cheatIconColor,
            size: CGSize(width: 22, height: 22))
        navigationItem.titleView = Self.makeIconTitleView(
            Bundle.localizedString(forKey: "cheat_catalog_title"),
            icon: icon)

        configureSearch()
        configureTable()
        configureEmptyLabel()
        bindSearch()
        reload(keyword: "")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A template may have been applied on the pushed game page. Keep this
        // lightweight info section in sync when the user comes back.
        reloadMatchInfo()
    }

    private func configureSearch() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.placeholder = Bundle.localizedString(forKey: "cheat_catalog_search_placeholder")
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(GameCheatCatalogTextCell.self, forCellReuseIdentifier: "Game")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func configureEmptyLabel() {
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .boldSystemFont(ofSize: UIFont.labelFontSize)
    }

    private func bindSearch() {
        searchText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.reload(keyword: text)
            }
            .store(in: &cancellables)
    }

    private func reload(keyword: String) {
        self.keyword = keyword
        queryGeneration += 1
        isLoading = false
        games = []
        totalCount = 0
        tableView.reloadData()
        loadNextPage()
    }

    private func loadNextPage() {
        guard !isLoading, totalCount == 0 || games.count < totalCount else { return }
        isLoading = true
        let generation = queryGeneration
        RACheatCatalogManager.shared().fetchGames(
            forPlatformIds: platformIds,
            keyword: keyword,
            offset: games.count,
            limit: pageSize,
            knownTotalCount: totalCount
        ) { [weak self] page, total, error in
            guard let self else { return }
            guard generation == self.queryGeneration else { return }
            self.isLoading = false
            if let error {
                self.showError(error)
                self.updateEmptyState()
                return
            }
            self.totalCount = total
            self.games.append(contentsOf: page)
            self.tableView.reloadData()
            self.updateEmptyState()
        }
    }

    private func updateEmptyState() {
        guard infoRows.isEmpty, games.isEmpty, !isLoading else {
            tableView.backgroundView = nil
            return
        }
        emptyLabel.text = keyword.isEmpty
            ? Bundle.localizedString(forKey: "cheat_catalog_empty")
            : Bundle.localizedString(forKey: "cheat_catalog_search_empty")
        tableView.backgroundView = emptyLabel
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "cheat_catalog_error_title"),
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }

    private var sections: [Section] {
        infoRows.isEmpty ? [.templates] : [.match, .templates]
    }

    private func reloadMatchInfo() {
        guard let session else {
            updateInfoRows(gamerdbEntry: nil, crc32: nil, binding: nil)
            return
        }
        session.reloadTemplateBinding()
        let binding = session.templateBinding?.isBound == true ? session.templateBinding : nil
        let game = session.game
        DispatchQueue.global(qos: .utility).async { [weak session] in
            guard session != nil else { return }
            if game.crc32LookupCandidates().isEmpty {
                do {
                    _ = try game.ensureCRC32()
                } catch {
                    print("[CheatCatalog] failed to ensure CRC32 for match info: \(error)")
                }
            }

            var matchedEntry: RAGameEntry?
            var matchedCRC32: String?
            for crc32 in game.crc32LookupCandidates() {
                guard let entry = RAGameRDBManager.shared().findGame(byCRC32: crc32) else {
                    continue
                }
                matchedEntry = entry
                matchedCRC32 = crc32
                break
            }

            DispatchQueue.main.async { [weak self] in
                self?.updateInfoRows(gamerdbEntry: matchedEntry, crc32: matchedCRC32, binding: binding)
            }
        }
    }

    private func updateInfoRows(gamerdbEntry: RAGameEntry?,
                                crc32: String?,
                                binding: GameCheatTemplateBinding?) {
        var rows: [MatchInfoRow] = []
        if let gamerdbEntry, let crc32 {
            rows.append(.gamerdb(entry: gamerdbEntry, crc32: crc32))
            if let binding {
                rows.append(.binding(binding))
            }
        }

        let hadInfo = !infoRows.isEmpty
        infoRows = rows
        if hadInfo || !rows.isEmpty {
            tableView.reloadData()
        }
        updateEmptyState()
    }
}

extension GameCheatCatalogBrowserViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText.send(searchController.searchBar.text ?? "")
    }
}

extension GameCheatCatalogBrowserViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .match:
            return infoRows.count
        case .templates:
            return games.count
        }
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Game", for: indexPath)
        switch sections[indexPath.section] {
        case .match:
            configureInfoCell(cell, row: infoRows[indexPath.row])
        case .templates:
            let game = games[indexPath.row]
            (cell as? GameCheatCatalogTextCell)?.configure(
                text: game.localizedDisplayNameWithVariantSuffix,
                secondaryText: secondaryText(for: game),
                secondaryNumberOfLines: 2)
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard sections[indexPath.section] == .templates else { return }
        let game = games[indexPath.row]
        let controller = GameCheatCatalogGameViewController(platformId: game.platformId, game: game, session: session)
        navigationController?.pushViewController(controller, animated: true)
    }

    func tableView(_ tableView: UITableView,
                   willDisplay cell: UITableViewCell,
                   forRowAt indexPath: IndexPath) {
        guard sections[indexPath.section] == .templates else { return }
        if indexPath.row >= games.count - 8 {
            loadNextPage()
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .match:
            return Bundle.localizedString(forKey: "cheat_catalog_match_section")
        case .templates:
            return infoRows.isEmpty ? nil : Bundle.localizedString(forKey: "cheat_catalog_template_section")
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard sections[section] == .match else { return nil }
        return Bundle.localizedString(forKey: "cheat_catalog_match_footer")
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // When the match section is present, give the actual template list a
        // little more breathing room so the helper footer and next title don't
        // visually collapse into one dense block.
        guard sections[section] == .templates, !infoRows.isEmpty else {
            return UITableView.automaticDimension
        }
        return 52
    }

    private func secondaryText(for game: RAGameEntry) -> String {
        let countFormat = Bundle.localizedString(forKey: "cheat_catalog_count_format")
        let countText = String(format: countFormat, game.cheatCount)
        if let english = game.authoritativeEnglishNameForDisplay, !english.isEmpty {
            return "\(english)\n\(countText)"
        }
        return countText
    }

    private func configureInfoCell(_ cell: UITableViewCell, row: MatchInfoRow) {
        cell.selectionStyle = .none
        cell.accessoryType = .none
        switch row {
        case .gamerdb(let entry, let crc32):
            (cell as? GameCheatCatalogTextCell)?.configure(
                text: entry.localizedDisplayNameWithVariantSuffix,
                secondaryText: matchedGameSecondaryText(entry: entry, crc32: crc32),
                secondaryNumberOfLines: 3)
        case .binding(let binding):
            let title = binding.catalogGameName?.isEmpty == false
                ? binding.catalogGameName!
                : Bundle.localizedString(forKey: "cheat_catalog_current_template")
            let origin = binding.origin == .manual
                ? Bundle.localizedString(forKey: "cheat_catalog_binding_manual")
                : Bundle.localizedString(forKey: "cheat_catalog_binding_auto")
            let status = String(
                format: Bundle.localizedString(forKey: "cheat_catalog_current_template_format"),
                Bundle.localizedString(forKey: "cheat_catalog_current_template"),
                origin)
            (cell as? GameCheatCatalogTextCell)?.configure(
                text: title,
                secondaryText: status,
                secondaryNumberOfLines: 2)
        }
    }

    private func matchedGameSecondaryText(entry: RAGameEntry, crc32: String) -> String {
        var lines: [String] = []
        if let english = entry.authoritativeEnglishNameForDisplay, !english.isEmpty {
            lines.append(english)
        }
        lines.append(String(format: Bundle.localizedString(forKey: "cheat_catalog_matched_crc_format"), crc32.uppercased()))
        return lines.joined(separator: "\n")
    }
}

final class GameCheatCatalogTextCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let secondaryLabel = UILabel()
    private let stackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        secondaryLabel.attributedText = nil
        secondaryLabel.text = nil
    }

    func configure(text: String,
                   secondaryText: String?,
                   secondaryNumberOfLines: Int) {
        titleLabel.text = text
        secondaryLabel.numberOfLines = secondaryNumberOfLines
        guard let secondaryText, !secondaryText.isEmpty else {
            secondaryLabel.attributedText = nil
            secondaryLabel.text = nil
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = secondaryText.contains("\n") ? 6 : 0
        secondaryLabel.attributedText = NSAttributedString(
            string: secondaryText,
            attributes: [
                .font: secondaryLabel.font as Any,
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph
            ])
    }

    private func configureViews() {
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        secondaryLabel.font = .preferredFont(forTextStyle: .subheadline)
        secondaryLabel.textColor = .secondaryLabel
        secondaryLabel.numberOfLines = 2
        secondaryLabel.adjustsFontForContentSizeCategory = true

        stackView.axis = .vertical
        stackView.spacing = 6
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(secondaryLabel)

        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }
}
