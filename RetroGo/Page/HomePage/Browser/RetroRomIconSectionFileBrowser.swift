//
//  RetroRomIconSectionFileBrowser.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

final class RetroRomIconSectionFileBrowser: UIView, RetroRomSectionFileBrowser {
    let organizeType: RetroRomFileOrganizeType

    var items: [String: [RetroRomFileItemWrapper]] = [:]
    var keys: [String] = []
    var observers: [NSObjectProtocol] = []

    private(set) lazy var collectionView = self.configUI()
    private(set) lazy var dataSource     = self.configDS()

    init(organizeType: RetroRomFileOrganizeType) {
        self.organizeType   = organizeType
        super.init(frame: .zero)

        _ = collectionView

        initialize()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        deinitialize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let layout = rekonCollectionViewLayout(width)
        collectionView.collectionViewLayout = layout
    }

    var meta: RetroRomFileBrowserMeta {
        .iconView(organize: organizeType, folderKey: nil)
    }

    func editRomFileName(indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? RetroRomBaseIconViewCell {
            cell.editFileName()
        }
    }

    func resignKeyboardFocus() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? RetroRomBaseIconViewCell {
                cell.titleEditor?.resignFirstResponder()
            }
        }
    }
}

extension RetroRomIconSectionFileBrowser {
    private func configUI() -> UICollectionView {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        collectionView.delegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return collectionView
    }

    private func configDS() -> DataSource {
        let cellReg = IconCellRegistration { [weak self] (cell, indexPath, item) in
            guard let self = self else { return }
            cell.wrappedItem = item
            cell.addInteraction(UIContextMenuInteraction(delegate: self))
        }

        let ds = DataSource(collectionView: collectionView) { (collectionView, indexPath, item) in
            collectionView.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: item)
        }

        let headerReg = HeaderRegistration(elementKind: RetroRomSectionHeaderView.sectionHeaderElementKind) { [weak self, weak ds] (headerView, elementKind, indexPath) in
            guard let self = self, let dataSource = ds else { return }
            guard indexPath.section < dataSource.snapshot().numberOfSections else { return }
            let key = dataSource.snapshot().sectionIdentifiers[indexPath.section]
            if organizeType == .byTag {
                if let id = Int(key) {
                    if let tag = RetroRomFileManager.shared.fileTag(id: id) {
                        headerView.type = .tag(tag: tag)
                    } else {
                        headerView.type = nil
                    }
                } else {
                    headerView.type = nil
                }
            } else if organizeType == .byCore {
                if let core = RetroRomCoreManager.shared.core(key) {
                    headerView.type = .core(core: core)
                } else {
                    headerView.type = nil
                }
            }
            headerView.holder = self
        }

        ds.supplementaryViewProvider = { (view, kind, indexPath) in
            view.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
        }

        return ds
    }

    private func rekonCollectionViewLayout(_ width: CGFloat) -> UICollectionViewLayout {
        let cellWidth: CGFloat
        let rowCount: Int
        if width > 500 {
            cellWidth = 150
            rowCount  = Int((width - 20) / (cellWidth + 20))
        } else if width > 400 {
            cellWidth = (width - 20 - 20 * 3 - 20) / 4
            rowCount  = 4
        } else {
            cellWidth = (width - 20 - 20 * 2 - 20) / 3
            rowCount  = 3
        }
        let cellHeight = cellWidth / 256.0 * 240 + RetroRomBaseIconViewCell.titleHeight
        let cellItemSize = NSCollectionLayoutSize(widthDimension: .absolute(cellWidth), heightDimension: .fractionalHeight(1.0))
        let cellItem = NSCollectionLayoutItem(layoutSize: cellItemSize)
        let cellGroupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(cellHeight))
        let cellGroup = NSCollectionLayoutGroup.horizontal(layoutSize: cellGroupSize, repeatingSubitem: cellItem, count: rowCount)
        cellGroup.interItemSpacing = .fixed(20)
        let section = NSCollectionLayoutSection(group: cellGroup)
        section.interGroupSpacing = 10
        section.contentInsets = .init(top: 0, leading: 20, bottom: 10, trailing: 20)
        let sectionHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(54))
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: sectionHeaderSize, elementKind: RetroRomSectionHeaderView.sectionHeaderElementKind, alignment: .top)
        sectionHeader.zIndex = 2
        sectionHeader.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [sectionHeader]
        return StickyHeaderLayout(section: section)
    }
}

extension RetroRomIconSectionFileBrowser: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        Vibration.selection.vibrate()
        startGame(item.item, core: item.core)
    }
}

extension RetroRomIconSectionFileBrowser: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return getSectionFileItemMenuConfiguration(interaction: interaction, at: location)
    }
}
