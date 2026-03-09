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

fileprivate final class FolderCollectionViewCell: UICollectionViewListCell {
    static let rowHeight: CGFloat = 44.0

    let thumbnailView = UIImageView(frame: .zero)
    let titleLabel    = UILabel(frame: .zero)
    let chevronImageView = UIImageView(image: UIImage(named: "Icon_chevron")?.withRenderingMode(.alwaysTemplate))
    let checkmarkImageView = UIImageView(image: UIImage(systemName: "checkmark"))

    var folder: RetroRomFolderItem? {
        didSet {
            titleLabel.text = folder?.itemName
        }
    }

    weak var holder: RetroRomLocationSelector?

    override init(frame: CGRect) {
        super.init(frame: frame)

        configUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configUI() {
        chevronImageView.tintColor = .mainColor
        chevronImageView.contentMode = .scaleAspectFit
        contentView.addSubview(chevronImageView)
        chevronImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 24, height: 24))
        }

        thumbnailView.image = UIImage(systemName: "folder.fill")
        thumbnailView.tintColor = .mainColor
        contentView.addSubview(thumbnailView)
        thumbnailView.snp.makeConstraints { make in
            make.leading.equalTo(chevronImageView.snp.trailing)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 24, height: 24))
        }

        checkmarkImageView.tintColor = .mainColor
        checkmarkImageView.isHidden = true
        contentView.addSubview(checkmarkImageView)
        checkmarkImageView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 18, height: 18))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(thumbnailView.snp.trailing).offset(10)
            make.trailing.equalTo(checkmarkImageView.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
        }
    }

    func setSelected(_ selected: Bool) {
        checkmarkImageView.isHidden = !selected
    }

    func setExpaneded(_ v: Bool) {
        self.chevronImageView.transform = v ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
    }
}

final class RetroRomLocationSelector: UIViewController {
    private lazy var collectionView = self.configUI()
    private lazy var dataSource = self.configDS()

    private var expanededStatus: [String: Bool] = [:]
    private var selectedFolder: RetroRomFolderItem?

    private let srcItem: RetroRomBaseItem
    private unowned let browser: RetroRomFileBrowser

    init(srcItem: RetroRomBaseItem, browser: RetroRomFileBrowser) {
        self.srcItem = srcItem
        self.browser = browser
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "homepage_move_to")

        navigationItem.leftBarButtonItem  = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAtion))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneAction))

        _ = collectionView
        _ = dataSource
        applyData()
    }
}

extension RetroRomLocationSelector {
    enum Section { case main }

    private typealias DataSource = UICollectionViewDiffableDataSource<Section, RetroRomFolderItem>
    private typealias Snapshot = NSDiffableDataSourceSectionSnapshot<RetroRomFolderItem>
    private typealias CellRegistration = UICollectionView.CellRegistration<FolderCollectionViewCell, RetroRomFolderItem>

    private func configUI() -> UICollectionView {
        let itemHeight: CGFloat = FolderCollectionViewCell.rowHeight
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(itemHeight))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(itemHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        let layout = UICollectionViewCompositionalLayout(section: section)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = false
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        return collectionView
    }

    private func configDS() -> DataSource {
        let cellReg = CellRegistration { [weak self] (cell, indexPath, folder) in
            guard let self = self else { return }
            cell.folder = folder
            cell.holder = self
            cell.setExpaneded(expanededStatus[folder.key] ?? false)
            cell.setSelected(folder == selectedFolder)
        }

        let ds = DataSource(collectionView: collectionView) { collectionView, indexPath, folder in
            collectionView.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: folder)
        }
        return ds
    }

    private func applyData() {
        var snapshot = Snapshot()
        func addFolders(folderKey: String, to paremtItem: RetroRomFolderItem?) {
            guard let item = RetroRomFileManager.shared.folderItem(key: folderKey) else { return }
            var subFolders = RetroRomFileManager.shared.retroRomFolderItems(in: item.subFolderKeys)
            subFolders.sortByFileNameAsc()
            snapshot.append(subFolders, to: paremtItem)
            for folder in subFolders {
                addFolders(folderKey: folder.key, to: folder)
            }
            expanededStatus[item.key] = !subFolders.isEmpty
            snapshot.expand([item])
        }
        addFolders(folderKey: "root", to: nil)

        dataSource.apply(snapshot, to: .main, animatingDifferences: false)
    }
}

extension RetroRomLocationSelector: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Vibration.selection.vibrate()

        guard let folder = dataSource.itemIdentifier(for: indexPath), folder != selectedFolder else { return }

        if let old = selectedFolder, let indexPath = dataSource.indexPath(for: old), let cell = collectionView.cellForItem(at: indexPath) as? FolderCollectionViewCell {
            cell.setSelected(false)
        }

        selectedFolder = folder
        if let cell = collectionView.cellForItem(at: indexPath) as? FolderCollectionViewCell {
            cell.setSelected(true)
        }
    }
}

extension RetroRomLocationSelector {
    @objc
    private func cancelAtion() {
        dismiss(animated: true)
    }

    @objc
    private func doneAction() {
        guard let dstFolder = selectedFolder else {
            return dismiss(animated: true)
        }

        if srcItem.isFolder {
            if srcItem.key == dstFolder.key {
                return showAlert(message: Bundle.localizedString(forKey: "homepage_same_folder"))
            }

            if dstFolder.isDescendant(of: srcItem.key) {
                return showAlert(message: Bundle.localizedString(forKey: "homepage_descendant_folder"))
            }
        }

        let srcItem = self.srcItem
        let browser = self.browser
        dismiss(animated: true) {
            browser.moveItem(srcItem: srcItem, dstFolderItem: dstFolder) {
                HomePageViewController.instance?.enterFolder(dstFolder, forward: true)
            }
        }
    }

    private func showAlert(message: String) {
        let title = Bundle.localizedString(forKey: "homepage_move_forbidden_title")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }
}
