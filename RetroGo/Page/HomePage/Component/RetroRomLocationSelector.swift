//
//  RetroRomLocationSelector.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/24.
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

/// Modal "Choose Destination" picker for the long-press → "Move to…" flow
/// and the drag-and-drop fallback case where we want an explicit picker
/// (not currently wired, but the API is decoupled enough to allow it).
///
/// ## UI shape (post v2 redesign)
///
/// `.insetGrouped` list with two visual cards:
///
/// 1. **Source card** — single row showing the thumbnail, name, and a
///    "Moving game / Moving folder" subtitle for the item being moved.
///    Non-interactive (no highlight, no selection). Anchors the page so
///    users always see what they're moving without having to back out.
///
/// 2. **Destinations card** — outline tree of folders, rooted at the
///    "My Library" node ("root" in storage). Folders with subfolders get
///    a `.outlineDisclosure` accessory; root is intentionally rendered
///    without one (the whole library must stay open). Forbidden targets
///    (source folder itself + every descendant) render in
///    `.tertiaryLabel` and are non-tappable so the user can't pick an
///    illegal destination in the first place — the `doneAction` alert
///    paths stay as defense-in-depth but should never fire.
///
/// ## Selection model
///
/// Single-select: tapping a folder sets it as the pending destination
/// (checkmark accessory), tapping it again clears the selection.
/// Tapping a different folder moves the checkmark. The Done bar button
/// is disabled whenever `selectedFolderKey == nil` — Cancel is the only
/// way out of an unselected state.
///
/// ## Why outline-disclosure + section snapshot
///
/// The picker is the only place in RetroGo today that genuinely wants
/// a sidebar-style hierarchical list with expand/collapse. The
/// `UICollectionLayoutListConfiguration(appearance: .insetGrouped)` +
/// `NSDiffableDataSourceSectionSnapshot` + `.outlineDisclosure()`
/// combination is the modern Apple-recommended pattern for this (it's
/// what Files / Mail / Notes sidebars use). Indentation, the disclosure
/// chevron, expand/collapse animation, and inset cards all come for
/// free; we only have to feed the tree.
final class RetroRomLocationSelector: UIViewController {

    // MARK: - Section / Item

    private enum Section: Hashable {
        case source
        case destinations
    }

    /// Diffable identifier. We store folder **keys**, not the
    /// `RetroRomFolderItem` references, so identity is stable across
    /// any future reload — the manager resolves keys to items on demand
    /// and caches them.
    private enum Item: Hashable {
        case source
        case folder(String)
    }

    private typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    private typealias SectionSnapshot = NSDiffableDataSourceSectionSnapshot<Item>

    // MARK: - State

    private let srcItem: RetroRomBaseItem

    /// Fires on the main queue after the user taps Done and the picked
    /// destination passes inline validation (not the source itself, not a
    /// descendant). The selector is already dismissed by the time this
    /// fires — callers can present further UI or push immediately.
    private let onPicked: (RetroRomFolderItem) -> Void

    private var selectedFolderKey: String?

    /// Folder keys that the user **cannot** pick as destination — source
    /// itself + every descendant. Only populated when the source is a
    /// folder (file sources have no forbidden destinations). Computed
    /// once at init via a stack-based DFS through `subFolderKeys`.
    private lazy var forbiddenFolderKeys: Set<String> = computeForbiddenKeys()

    // MARK: - Views

    private lazy var collectionView: UICollectionView = {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = .systemGroupedBackground
        // No section headers — the source card itself communicates
        // "this is what you're moving", and "Choose Destination" is the
        // nav-bar title already. Extra header text would be redundant.
        config.headerMode = .none
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.delegate = self
        cv.backgroundColor = .systemGroupedBackground
        return cv
    }()

    private lazy var dataSource: DataSource = makeDataSource()

    private lazy var doneButton: UIBarButtonItem = {
        let button = UIBarButtonItem(barButtonSystemItem: .done,
                                     target: self,
                                     action: #selector(doneAction))
        // Stays disabled until the user actually picks a destination.
        // Mirrors iOS Files / Photos "Choose" behavior — accidentally
        // tapping Done without a selection shouldn't quietly dismiss.
        button.isEnabled = false
        return button
    }()

    // MARK: - Init

    init(srcItem: RetroRomBaseItem,
         onPicked: @escaping (RetroRomFolderItem) -> Void) {
        self.srcItem  = srcItem
        self.onPicked = onPicked
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.title = Bundle.localizedString(forKey: "homepage_choose_destination")
        navigationItem.leftBarButtonItem  = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                            target: self,
                                                            action: #selector(cancelAction))
        navigationItem.rightBarButtonItem = doneButton

        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        _ = dataSource
        applyData()
    }
}

// MARK: - Forbidden destinations

private extension RetroRomLocationSelector {

    /// Walk the folder tree from the source folder and collect every
    /// reachable folder key. These are the destinations that
    /// `RetroRomFileManager.moveItem` would reject ("can't move a
    /// folder into its own subfolder", "target is the same as the
    /// current location") — by computing them up-front and disabling
    /// the corresponding cells we prevent the illegal selection from
    /// happening at all, instead of fronting an error alert after Done.
    ///
    /// Source-as-file → empty set (files have no descendants to avoid).
    func computeForbiddenKeys() -> Set<String> {
        guard let srcFolder = srcItem as? RetroRomFolderItem else { return [] }

        var forbidden: Set<String> = [srcFolder.key]
        var stack: [RetroRomFolderItem] = [srcFolder]
        while let next = stack.popLast() {
            for childKey in next.subFolderKeys {
                guard let child = RetroRomFileManager.shared.folderItem(key: childKey) else { continue }
                if forbidden.insert(childKey).inserted {
                    stack.append(child)
                }
            }
        }
        return forbidden
    }

    func isForbidden(_ folderKey: String) -> Bool {
        forbiddenFolderKeys.contains(folderKey)
    }
}

// MARK: - Data source

private extension RetroRomLocationSelector {

    private func makeDataSource() -> DataSource {
        // Source cell registration. Renders a single non-interactive
        // row with thumbnail + name + "Moving …" subtitle.
        let sourceCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { [weak self] cell, _, _ in
            guard let self = self else { return }
            self.configureSourceCell(cell)
        }

        // Folder cell registration. Renders one row per folder in the
        // outline; root is special-cased (different title + no
        // disclosure chevron).
        let folderCellReg = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, key in
            guard let self = self else { return }
            self.configureFolderCell(cell, folderKey: key)
        }

        return DataSource(collectionView: collectionView) { cv, indexPath, item in
            switch item {
            case .source:
                return cv.dequeueConfiguredReusableCell(using: sourceCellReg,
                                                        for: indexPath,
                                                        item: ())
            case .folder(let key):
                return cv.dequeueConfiguredReusableCell(using: folderCellReg,
                                                        for: indexPath,
                                                        item: key)
            }
        }
    }

    func configureSourceCell(_ cell: UICollectionViewListCell) {
        var content = cell.defaultContentConfiguration()
        content.text = srcItem.itemName
        content.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
        content.textProperties.numberOfLines = 1
        content.textProperties.lineBreakMode = .byTruncatingMiddle

        let subtitleKey = srcItem.isFolder
            ? "homepage_location_selector_moving_folder"
            : "homepage_location_selector_moving_file"
        content.secondaryText = Bundle.localizedString(forKey: subtitleKey)
        content.secondaryTextProperties.color = .secondaryLabel

        // Prefer the real thumbnail; fall back to a system glyph if the
        // item has no cover art (most files, all folders).
        if let thumb = srcItem.thumbnail {
            content.image = thumb
        } else {
            content.image = UIImage(systemName: srcItem.isFolder
                                    ? "folder.fill"
                                    : "gamecontroller.fill")
            content.imageProperties.tintColor = .mainColor
        }
        content.imageProperties.maximumSize    = CGSize(width: 32, height: 32)
        content.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 32)
        content.imageProperties.cornerRadius   = 4
        content.imageToTextPadding             = 12

        cell.contentConfiguration = content
        cell.accessories = []  // non-interactive
    }

    func configureFolderCell(_ cell: UICollectionViewListCell, folderKey: String) {
        guard let folder = RetroRomFileManager.shared.folderItem(key: folderKey) else {
            // Defensive: a key we stored could in principle vanish due
            // to concurrent mutation. Blank cell beats a crash.
            cell.contentConfiguration = nil
            cell.accessories = []
            return
        }
        let isRoot      = folderKey == "root"
        let isForbidden = isForbidden(folderKey)

        var content = cell.defaultContentConfiguration()
        content.text = isRoot
            ? Bundle.localizedString(forKey: "homepage_root_folder_name")
            : folder.itemName

        // Trailing detail = total child count (folders + files). Helps
        // users distinguish empty folders from populated ones at a glance.
        let childCount = folder.subFolderKeys.count + folder.subFileKeys.count
        content.secondaryText = String(
            format: Bundle.localizedString(forKey: "homepage_location_selector_item_count"),
            childCount
        )
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.font  = .monospacedDigitSystemFont(
            ofSize: UIFont.smallSystemFontSize, weight: .regular)
        content.prefersSideBySideTextAndSecondaryText = true

        // Root gets the "tray" glyph — a deliberate visual cue that
        // "this is the top of the library, not a regular folder."
        content.image = UIImage(systemName: isRoot ? "tray.fill" : "folder.fill")
        content.imageProperties.tintColor = isForbidden ? .tertiaryLabel : .mainColor
        content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
        content.imageProperties.reservedLayoutSize = CGSize(width: 24, height: 24)

        // Forbidden = source folder itself + every descendant. We dim
        // them rather than hide them — context matters (the user can
        // see where the source currently lives), but the row is not
        // pickable (see `shouldHighlightItemAt` and `shouldSelectItemAt`).
        if isForbidden {
            content.textProperties.color = .tertiaryLabel
            content.secondaryTextProperties.color = .quaternaryLabel
        }

        cell.contentConfiguration = content

        // Accessories:
        // - Outline disclosure: only on non-root folders that actually
        //   have nested subfolders. Root never gets one (collapsing the
        //   whole library would hide everything). Leaves never get one
        //   (no children to expand into).
        // - Checkmark: only on the currently-selected folder.
        var accessories: [UICellAccessory] = []
        if !isRoot, !folder.subFolderKeys.isEmpty {
            accessories.append(.outlineDisclosure(
                options: .init(tintColor: .mainColor)
            ))
        }
        if selectedFolderKey == folderKey {
            accessories.append(.checkmark(options: .init(tintColor: .mainColor)))
        }
        cell.accessories = accessories
    }

    func applyData() {
        // Source section: single, fixed item.
        var sourceSnap = SectionSnapshot()
        sourceSnap.append([.source])
        dataSource.apply(sourceSnap, to: .source, animatingDifferences: false)

        // Destinations section: outline tree starting at "root".
        var destSnap = SectionSnapshot()
        appendFolderHierarchy(folderKey: "root", parent: nil, into: &destSnap)
        // Pre-expand the entire tree. Users picking a destination want
        // to scan all options without tapping disclosure chevrons
        // first. They can collapse manually if the tree is huge.
        destSnap.expand(destSnap.items)
        dataSource.apply(destSnap, to: .destinations, animatingDifferences: false)
    }

    private func appendFolderHierarchy(folderKey: String,
                               parent: Item?,
                               into snap: inout SectionSnapshot) {
        guard let folder = RetroRomFileManager.shared.folderItem(key: folderKey) else { return }
        let me: Item = .folder(folderKey)
        snap.append([me], to: parent)

        var children = RetroRomFileManager.shared.retroRomFolderItems(in: folder.subFolderKeys)
        children.sortByFileNameAsc()
        for child in children {
            appendFolderHierarchy(folderKey: child.key, parent: me, into: &snap)
        }
    }
}

// MARK: - Selection / interaction

extension RetroRomLocationSelector: UICollectionViewDelegate {

    /// Suppress touch-down highlight on non-selectable rows (source
    /// card, forbidden destinations). `shouldSelectItemAt` would block
    /// selection but not the visual press feedback — `shouldHighlight`
    /// covers both.
    func collectionView(_ collectionView: UICollectionView,
                        shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        case .source:
            return false
        case .folder(let key):
            return !isForbidden(key)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        case .source:
            return false
        case .folder(let key):
            return !isForbidden(key)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        Vibration.selection.vibrate()
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .folder(let folderKey) = item else { return }

        // Tapping the already-selected folder clears the selection
        // (single-select toggle, same as iOS Mail's flag picker).
        let previouslySelected = selectedFolderKey
        if previouslySelected == folderKey {
            selectedFolderKey = nil
        } else {
            selectedFolderKey = folderKey
        }

        // Drop the row's transient grey highlight — our "this is
        // selected" affordance is the checkmark accessory, not the
        // selection background.
        collectionView.deselectItem(at: indexPath, animated: true)

        // Reconfigure the two affected rows (new + old, if any) so
        // their checkmarks update. `reconfigureItems` keeps cell
        // identity and skips the full snapshot diff, so this is
        // animation-free and cheap.
        var snap = dataSource.snapshot()
        var toRefresh: [Item] = [item]
        if let prev = previouslySelected, prev != folderKey {
            toRefresh.append(.folder(prev))
        }
        snap.reconfigureItems(toRefresh)
        dataSource.apply(snap, animatingDifferences: false)

        doneButton.isEnabled = (selectedFolderKey != nil)
    }
}

// MARK: - Actions

private extension RetroRomLocationSelector {

    @objc
    func cancelAction() {
        Vibration.selection.vibrate()
        dismiss(animated: true)
    }

    @objc
    func doneAction() {
        Vibration.selection.vibrate()
        guard let folderKey = selectedFolderKey,
              let dstFolder = RetroRomFileManager.shared.folderItem(key: folderKey) else {
            // Should be unreachable while the Done button is gated on
            // `selectedFolderKey != nil`, but bail safely just in case.
            return dismiss(animated: true)
        }

        // `forbiddenFolderKeys` already covers "source itself" and
        // "descendant of source", and `shouldSelectItemAt` rejects taps
        // on those. These alerts stay as defense-in-depth — if logic
        // somewhere lets a forbidden key through, the user still gets
        // a clear explanation instead of a silent broken move.
        if srcItem.isFolder {
            if srcItem.key == dstFolder.key {
                return showAlert(message: Bundle.localizedString(forKey: "homepage_same_folder"))
            }
            if dstFolder.isDescendant(of: srcItem.key) {
                return showAlert(message: Bundle.localizedString(forKey: "homepage_descendant_folder"))
            }
        }

        let picked = onPicked
        dismiss(animated: true) {
            picked(dstFolder)
        }
    }

    func showAlert(message: String) {
        let title = Bundle.localizedString(forKey: "homepage_move_forbidden_title")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }
}
