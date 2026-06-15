//
//  DiscoverGameDetailViewController.swift
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

// ---------------------------------------------------------------------------
// MARK: - Cover-did-load notification
//
// Posted on MainActor after DiscoverGameDetailViewController successfully sets
// a cover image for the first time.  DiscoverGameListViewController observes
// this notification to update the corresponding visible cell without performing
// any additional network work of its own.
// ---------------------------------------------------------------------------

extension Notification.Name {
    /// Posted when a game cover is loaded successfully in the detail page.
    static let discoverCoverDidLoad = Notification.Name("RetroGoDiscoverCoverDidLoad")
}

enum DiscoverCoverNotificationKey {
    /// `Int` — the `RAGameEntry.gameId` that received the cover.
    static let gameId = "gameId"
    /// `UIImage` — the downloaded/cached cover image.
    static let image  = "image"
}

// ---------------------------------------------------------------------------
// MARK: - DiscoverGameDetailViewController
//
// Third-level page in the Discover flow.
// Layout:
//   tableHeaderView  → DiscoverGameHeaderView (cover art + game title + platform)
//   Section 0        → 基本信息  (developer, publisher, year, genre, region, ...)
//   Section 1        → 游戏简介  (description — only when non-empty)
//   Section 2        → 更多信息  (franchise, serial, max players)
//   Section 3        → ROM 信息  (file name, file size, CRC32, MD5, SHA1)
// ---------------------------------------------------------------------------

final class DiscoverGameDetailViewController: UIViewController {

    // MARK: - Types

    private struct InfoRow {
        let title: String
        let value: String
    }

    private struct SectionData {
        let header: String
        let rows:   [InfoRow]
    }

    // MARK: - Data

    /// Currently displayed entry. Starts as the group's representative variant and
    /// is swapped in place when the user picks another variant from the 变体 menu.
    private var game: RAGameEntry
    let platform: RAPlatformItem

    /// Group context, captured once from the entry the page was opened with.
    /// Kept separate from `game` because after switching to a concrete variant
    /// (variantCount == 0) we still need these to drive the 变体 menu.
    private let groupName:    String?
    private let variantCount: Int

    /// Stable seed for the cover placeholder colour/initial — the group name, so the
    /// colour matches the list cell and stays fixed while switching variants.
    /// Also used as the cover cache key so all variants share one cover.
    private let placeholderSeed: String

    /// The group representative's gameId — the row the list page shows. Used when
    /// posting the cover-loaded notification so the correct list cell updates.
    private let representativeGameId: Int

    /// Rebuilt whenever `game` changes.
    private var sections: [SectionData] = []

    private var didStartInitialCoverLoad = false
    private var headerNeedsSizing = true
    private var lastHeaderFittingWidth: CGFloat = 0
    private var coverRequestID = 0
    private var coverIndicatorTask: Task<Void, Never>?

    // MARK: - Views

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.delegate   = self
        tv.dataSource = self
        tv.rowHeight  = UITableView.automaticDimension
        tv.estimatedRowHeight = 60
        tv.register(DiscoverInfoCell.self,
                    forCellReuseIdentifier: DiscoverInfoCell.reuseID)
        tv.register(DiscoverDescriptionCell.self,
                    forCellReuseIdentifier: DiscoverDescriptionCell.reuseID)
        view.addSubview(tv)
        tv.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return tv
    }()

    private lazy var headerView: DiscoverGameHeaderView = {
        let h = DiscoverGameHeaderView(frame: CGRect(
            x: 0, y: 0,
            width: view.bounds.width,
            height: DiscoverGameHeaderView.totalHeight))
        h.configure(game: game, platformName: platform.displayName, placeholderSeed: placeholderSeed)
        return h
    }()

    // MARK: - Init

    init(game: RAGameEntry, platform: RAPlatformItem) {
        self.game            = game
        self.platform        = platform
        self.groupName       = game.groupName
        self.variantCount    = game.variantCount
        // Landing entry's name is the clean group name (for group representatives),
        // which is exactly the seed the list cell used.
        self.placeholderSeed      = game.groupName ?? game.name
        self.representativeGameId  = game.gameId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor   = .systemGroupedBackground
        updateNavigationTitle()

        navigationItem.largeTitleDisplayMode = .never

        setupVariantButton()
        buildSections()

        _ = tableView

        tableView.tableHeaderView = headerView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .languageChanged,
            object: nil)
    }

    deinit {
        coverIndicatorTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartInitialCoverLoad else { return }
        didStartInitialCoverLoad = true
        // Cover cache/network work can compete with the push transition on older
        // devices. Start it after the first frame of the detail page is on screen.
        fetchCover()
    }

    // MARK: - Variant menu

    /// Adds the top-right 变体 button only when this group has more than one variant.
    /// The menu lazily loads the variant list when opened (UIDeferredMenuElement).
    private func setupVariantButton() {
        guard variantCount > 1, let group = groupName, !group.isEmpty else { return }

        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { completion([]); return }
            RAGameRDBManager.shared().fetchVariants(
                forPlatformId: self.platform.platformId,
                groupName:     group
            ) { variants, _ in
                // completion is delivered on the main thread by RAGameRDBManager.
                let actions: [UIMenuElement] = variants.map { variant in
                    UIAction(
                        title: variant.localizedDisplayNameWithVariantSuffix,
                        state: variant.gameId == self.game.gameId ? .on : .off
                    ) { [weak self] _ in
                        self?.switchToVariant(variant)
                    }
                }
                completion(actions)
            }
        }

        let menu = UIMenu(title: group, children: [deferred])
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: Bundle.localizedString(forKey: "detail_variants"),
            image: nil,
            primaryAction: nil,
            menu: menu)
    }

    /// Swap the displayed entry in place and re-render header, sections and cover.
    private func switchToVariant(_ variant: RAGameEntry) {
        guard variant.gameId != game.gameId else { return }
        Vibration.selection.vibrate()

        game = variant
        updateNavigationTitle()
        headerView.configure(game: variant, platformName: platform.displayName, placeholderSeed: placeholderSeed)
        buildSections()
        tableView.reloadData()
        markHeaderNeedsSizing()
        fetchCover()
    }

    @objc
    private func languageChanged() {
        updateNavigationTitle()
        setupVariantButton()
        headerView.updateText(game: game, platformName: platform.displayName)
        buildSections()
        tableView.reloadData()
        markHeaderNeedsSizing()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderViewToFit()
    }

    // MARK: - Header sizing
    //
    // tableHeaderView needs explicit height; recalculate after layout passes
    // so multi-line nameLabel is measured correctly.

    private func sizeHeaderViewToFit() {
        let targetWidth = tableView.bounds.width
        guard targetWidth > 0 else { return }
        guard headerNeedsSizing || abs(lastHeaderFittingWidth - targetWidth) > 1 else { return }

        let fittingSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        let height      = headerView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority:       .fittingSizeLevel
        ).height

        headerNeedsSizing = false
        lastHeaderFittingWidth = targetWidth

        guard abs(headerView.frame.height - height) > 1 else { return }

        var frame            = headerView.frame
        frame.size.height    = height
        headerView.frame     = frame
        tableView.tableHeaderView = headerView   // triggers internal re-layout
    }

    private func markHeaderNeedsSizing() {
        headerNeedsSizing = true
        sizeHeaderViewToFit()
    }

    // MARK: - Cover art

    private func fetchCover() {
        coverRequestID += 1
        let requestID = coverRequestID
        coverIndicatorTask?.cancel()
        coverIndicatorTask = nil

        // All variants of a group share one cover — always key by the group name so
        // switching variants never triggers a second download (it hits the same cache).
        let coverName = placeholderSeed
        let coverRdb  = platform.rdbName

        guard !GameCoverService.shared.isDefinitelyUnavailable(gameName: coverName, rdbName: coverRdb) else {
            return
        }

        // ── Memory cache hit: zero latency, show cover immediately ─────────────
        if let cached = GameCoverService.shared.memoryCachedImage(gameName: coverName, rdbName: coverRdb) {
            headerView.setCoverImage(cached)
            sizeHeaderViewToFit()
            return
        }

        // ── Async path (disk cache or network) ──────────────────────────────────
        // Defer the loading indicator by 0.2 s: disk-cache reads typically finish
        // in < 100 ms and won't see the spinner at all; slow network loads will.
        let indicatorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self, self.coverRequestID == requestID else { return }
            self.headerView.showLoadingIndicator()
        }
        coverIndicatorTask = indicatorTask

        GameCoverService.shared.loadCover(
            gameName: coverName,
            rdbName:  coverRdb,
            into:     headerView.coverImageView
        ) { [weak self] image in
            // completion is @Sendable; hop to @MainActor before touching UIKit.
            Task { @MainActor [weak self] in
                guard let self else { indicatorTask.cancel(); return }
                guard self.coverRequestID == requestID else {
                    indicatorTask.cancel()
                    return
                }
                indicatorTask.cancel()
                self.coverIndicatorTask = nil

                if let image {
                    self.headerView.setCoverImage(image)
                    self.sizeHeaderViewToFit()
                    // Notify the list page so the corresponding cell can show the
                    // cover without any extra network work. Always use the group's
                    // representative gameId — that's the row the list shows.
                    NotificationCenter.default.post(
                        name: .discoverCoverDidLoad,
                        object: nil,
                        userInfo: [
                            DiscoverCoverNotificationKey.gameId: self.representativeGameId,
                            DiscoverCoverNotificationKey.image:  image
                        ]
                    )
                } else {
                    self.headerView.hideLoadingIndicator()
                    self.showToast(Bundle.localizedString(forKey: "cover_load_failed"))
                }
            }
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let container = UIView()
        container.backgroundColor    = UIColor.black.withAlphaComponent(0.72)
        container.layer.cornerRadius = 12
        container.clipsToBounds      = true

        let label = UILabel()
        label.text          = message
        label.font          = .systemFont(ofSize: 14)
        label.textColor     = .white
        label.numberOfLines = 0
        label.textAlignment = .center

        container.addSubview(label)
        view.addSubview(container)

        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
        }
        container.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-36)
            make.width.lessThanOrEqualToSuperview().offset(-48)
        }

        container.alpha = 0
        UIView.animate(withDuration: 0.25) {
            container.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.2, options: .curveEaseIn) {
                container.alpha = 0
            } completion: { _ in
                container.removeFromSuperview()
            }
        }
    }

    // MARK: - Build sections

    private func buildSections() {
        sections = []

        // ── 基本信息 ──────────────────────────────────────────────────────────
        var basic: [InfoRow] = []

        if let englishName = game.authoritativeEnglishNameForDisplay {
            basic.append(InfoRow(title: Bundle.localizedString(forKey: "detail_english_name"),
                                 value: englishName))
        }

        if let dev = game.developer, !dev.isEmpty {
            basic.append(InfoRow(title: Bundle.localizedString(forKey: "detail_developer"),
                                 value: dev))
        }
        if let pub = game.publisher, !pub.isEmpty {
            basic.append(InfoRow(title: Bundle.localizedString(forKey: "detail_publisher"),
                                 value: pub))
        }
        if game.releaseYear > 0 {
            let year = game.releaseMonth > 0
                ? String(format: "%04d / %02d", game.releaseYear, game.releaseMonth)
                : String(game.releaseYear)
            basic.append(InfoRow(title: Bundle.localizedString(forKey: "detail_release"),
                                 value: year))
        }
        if let genre = game.genre, !genre.isEmpty {
            basic.append(InfoRow(title: Bundle.localizedString(forKey: "detail_genre"),
                                 value: genre))
        }
        if let region = game.region, !region.isEmpty {
            basic.append(InfoRow(title: Bundle.localizedString(forKey: "detail_region"),
                                 value: region))
        }

        if !basic.isEmpty {
            sections.append(SectionData(
                header: Bundle.localizedString(forKey: "detail_section_basic"),
                rows: basic))
        }

        // ── 游戏简介 ──────────────────────────────────────────────────────────
        if let desc = game.gameDescription, !desc.isEmpty {
            // Description uses a dedicated cell type; store a single row whose
            // value carries the full text. The delegate distinguishes it by section index.
            sections.append(SectionData(
                header: Bundle.localizedString(forKey: "detail_section_description"),
                rows: [InfoRow(title: "", value: desc)]))
        }

        // ── 更多信息 ──────────────────────────────────────────────────────────
        var more: [InfoRow] = []

        if let franchise = game.franchise, !franchise.isEmpty {
            more.append(InfoRow(title: Bundle.localizedString(forKey: "detail_franchise"),
                                value: franchise))
        }
        if game.maxUsers > 1 {
            more.append(InfoRow(title: Bundle.localizedString(forKey: "detail_max_players"),
                                value: "\(game.maxUsers)"))
        }
        if let serial = game.serial, !serial.isEmpty {
            more.append(InfoRow(title: Bundle.localizedString(forKey: "detail_serial"),
                                value: serial))
        }

        if !more.isEmpty {
            sections.append(SectionData(
                header: Bundle.localizedString(forKey: "detail_section_more"),
                rows: more))
        }

        // ── ROM 信息 ──────────────────────────────────────────────────────────
        var rom: [InfoRow] = []

        if let romName = game.romName, !romName.isEmpty {
            rom.append(InfoRow(title: Bundle.localizedString(forKey: "detail_rom_name"),
                               value: romName))
        }
        if game.fileSize > 0 {
            rom.append(InfoRow(title: Bundle.localizedString(forKey: "detail_file_size"),
                               value: Self.formatFileSize(game.fileSize)))
        }
        if let crc = game.crc32, !crc.isEmpty {
            rom.append(InfoRow(title: "CRC32", value: crc.uppercased()))
        }
        if let md5 = game.md5, !md5.isEmpty {
            rom.append(InfoRow(title: "MD5", value: md5.uppercased()))
        }
        if let sha1 = game.sha1, !sha1.isEmpty {
            rom.append(InfoRow(title: "SHA1", value: sha1.uppercased()))
        }

        if !rom.isEmpty {
            sections.append(SectionData(
                header: Bundle.localizedString(forKey: "detail_section_rom"),
                rows: rom))
        }
    }

    // MARK: - Helpers

    private static func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1_024
        let mb = kb / 1_024
        if mb >= 1 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    // Whether a section index holds the description (single multi-line row).
    private func isDescriptionSection(_ section: Int) -> Bool {
        guard section < sections.count else { return false }
        let key = Bundle.localizedString(forKey: "detail_section_description")
        return sections[section].header == key
    }

    private func updateNavigationTitle() {
        navigationItem.title = game.localizedDisplayNameWithVariantSuffix
    }
}

// MARK: - UITableViewDataSource

extension DiscoverGameDetailViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView,
                   titleForHeaderInSection section: Int) -> String? {
        sections[section].header
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]

        if isDescriptionSection(indexPath.section) {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DiscoverDescriptionCell.reuseID,
                for: indexPath) as! DiscoverDescriptionCell
            cell.configure(text: row.value)
            return cell
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: DiscoverInfoCell.reuseID,
            for: indexPath) as! DiscoverInfoCell
        cell.configure(title: row.title, value: row.value)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DiscoverGameDetailViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
