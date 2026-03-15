//
//  RetroRomCoreInfoViewController.swift
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
import RACoordinator

final class RetroRomCoreInfoViewController: UIViewController {
    let coreInfoItem: EmuCoreInfoItem
    let showCloseButton: Bool
    let interactive: Bool

    private lazy var collectionView = self.configUI()
    private lazy var dataSource = self.configDS()

    private var basicItems: [Item] = []
    private var firmwareItems: [Item] = []
    private var descItems: [Item] = []

    init(coreInfoItem: EmuCoreInfoItem, showCloseButton: Bool = false, interactive: Bool) {
        self.coreInfoItem = coreInfoItem
        self.showCloseButton = showCloseButton
        self.interactive = interactive
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
        navigationItem.title = coreInfoItem.coreName

        if showCloseButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), style: .plain, target: self, action: #selector(closeAction))
        }

        _ = collectionView

        applySnapshot()
    }

    func updateFirmware(_ firmware: EmuCoreFirmware) {
        var snapshot = dataSource.snapshot()
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems([Item.firmware(data: firmware)])
        } else {
            snapshot.reloadItems([Item.firmware(data: firmware)])
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}

extension RetroRomCoreInfoViewController {
    private func configUI() -> UICollectionView {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        config.footerMode = .supplementary
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self = self, self.coreInfoItem.coreId == "mame", indexPath.section == 1 && indexPath.item > 0 else { return nil }
            guard let item = self.dataSource.itemIdentifier(for: indexPath) else { return nil }

            let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] (action, view, completion) in
                guard let self = self else { return }
                deleteFirmwareItem(item)
                completion(true)
            }
            deleteAction.image = UIImage(systemName: "trash")
            let config = UISwipeActionsConfiguration(actions: [deleteAction])
            return config
        }
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        let collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self
        collectionView.allowsSelection = false
        view.addSubview(collectionView)
        return collectionView
    }

    private func configDS() -> DataSource {
        let normalCellReg = NormalCellRegistration { cell, indexPath, item in
            cell.item = item
        }
        let firmwareCellReg = FirmwareCellRegistration { [weak self] cell, indexPath, firmware in
            cell.firmware = firmware
            cell.holder   = self
        }
        let mameFirmwareTipCellReg = MameFirmwareTipCellRegistration { cell, indexPath, item in
            if case .mameFirmwareTip(let core) = item {
                cell.core = core
            }
        }
        let ds = DataSource(collectionView: collectionView, cellProvider: { (collectionView, indexPath, item) -> UICollectionViewCell? in
            if case .firmware(let firmware) = item {
                return collectionView.dequeueConfiguredReusableCell(using: firmwareCellReg, for: indexPath, item: firmware)
            } else if case .mameFirmwareTip(_) = item {
                return collectionView.dequeueConfiguredReusableCell(using: mameFirmwareTipCellReg, for: indexPath, item: item)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: normalCellReg, for: indexPath, item: item)
            }
        })

        let headerReg = FirmwareHeaderRegistration(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] headerView, elementKind, indexPath in
            guard let self = self else { return }

            headerView.holder = self

            if firmwareItems.count > 0 && indexPath.section == 1 {
                headerView.coreInfoItem = coreInfoItem
            } else {
                headerView.coreInfoItem = nil
            }
        }

        let footerReg = FirmwareFooterRegistration(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] footerView, elementKind, indexPath in
            guard let self = self else { return }

            footerView.holder = self

            if coreInfoItem.coreId == "ppsspp" && firmwareItems.count > 0 && indexPath.section == 1 {
                footerView.coreInfoItem = coreInfoItem
                footerView.isHidden = false
            } else {
                footerView.coreInfoItem = nil
                footerView.isHidden = true
            }

        }

        ds.supplementaryViewProvider = { (collectionView, kind, indexPath) in
            // 判断 kind 类型
            if kind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(using: headerReg, for: indexPath)
            } else if kind == UICollectionView.elementKindSectionFooter {
                return collectionView.dequeueConfiguredReusableSupplementary(using: footerReg, for: indexPath)
            } else {
                return nil
            }
        }
        return ds
    }

    private func deleteFirmwareItem(_ item: Item) {
        guard coreInfoItem.coreId == "mame", case .firmware(let firmware) = item, let firstItem = firmwareItems.first else {
            return
        }

        firmwareItems.removeAll(where: { $0 == item })

        coreInfoItem.deleteFirmware(firmware)

        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([item])
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems([firstItem])
        } else {
            snapshot.reloadItems([firstItem])
        }

        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func applySnapshot() {
        var sections: [Section] = []
        basicItems.append(.normal(tip: Bundle.localizedString(forKey: "coreinfo_full_name"), value: coreInfoItem.displayName))

        if let manufacturer = coreInfoItem.manufacturer {
            basicItems.append(.normal(tip: Bundle.localizedString(forKey: "coreinfo_manufacturer"), value: manufacturer))
        }

        if let systemName = coreInfoItem.systemName {
            basicItems.append(.normal(tip: Bundle.localizedString(forKey: "coreinfo_system_name"), value: systemName))
        }

        if let exts = coreInfoItem.extensions {
            basicItems.append(.extensions(tip: Bundle.localizedString(forKey: "coreinfo_extensions"), list: exts))
        }

        if interactive, coreInfoItem.supportNoContent {
            let tip = Bundle.localizedString(forKey: "coreinfo_support_no_content")
            let value = Bundle.localizedString(forKey: "coreinfo_start_core")
            let item: Item = .runCore(tip: tip, value: value) { [weak self] in
                guard let self = self else { return }
                let coreInfoItem = coreInfoItem
                RetroArchX.playGame(romUrl: nil, core: coreInfoItem)
            }
            basicItems.append(item)
        }

        sections.append(.basic)

        if coreInfoItem.coreId == "mame" {
            firmwareItems.append(.mameFirmwareTip(core: coreInfoItem))
        }
        if let array = coreInfoItem.firmwares {
            firmwareItems.append(contentsOf: array.map({ Item.firmware(data: $0) }))
        }
        if firmwareItems.count > 0 {
            sections.append(.firmware)
        }

        if let developers = coreInfoItem.authors {
            let tip = Bundle.localizedString(forKey: "coreinfo_developers")
            let value = developers.joined(separator: ", ")
            descItems.append(.normal(tip: tip, value: value))
        }

        if let array = coreInfoItem.getLicenseDictionaryArray() {
            let tip = Bundle.localizedString(forKey: "coreinfo_licenses")
            let items = array.compactMap({ License(showName: $0["show_name"], fileName: $0["file_name"]) })
            descItems.append(.license(tip: tip, licenses: items))
        }

        if let url = coreInfoItem.getSourceURL() {
            let tip = Bundle.localizedString(forKey: "coreinfo_srcurl")
            descItems.append(.link(tip: tip, url: url))
        }

        if let desc = coreInfoItem.getLocalDesc(Bundle.currentSimpleLanguageKey()) {
            let tip = Bundle.localizedString(forKey: "coreinfo_descrption")
            descItems.append(.normal(tip: tip, value: desc))
        }

        if let systemId = coreInfoItem.systemID {
            let tip = Bundle.localizedString(forKey: "coreinfo_system_id")
            descItems.append(.normal(tip: tip, value: systemId))
        }

        if descItems.count > 0 {
            sections.append(.desc)
        }

        var snapshot = Snapshot()
        snapshot.appendSections(sections)
        snapshot.appendItems(basicItems, toSection: .basic)
        if firmwareItems.count > 0 {
            snapshot.appendItems(firmwareItems, toSection: .firmware)
        }
        if descItems.count > 0 {
            snapshot.appendItems(descItems, toSection: .desc)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    @objc
    private func closeAction() {
        dismiss(animated: true)
    }
}

extension RetroRomCoreInfoViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}

extension RetroRomCoreInfoViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        _ = url.startAccessingSecurityScopedResource()

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            url.stopAccessingSecurityScopedResource()

            if isDirectory.boolValue {
                openFrimwareFolder(url)
            } else {
                openFirmwareFile(url)
            }
        }
    }

    private func openFirmwareFile(_ url: URL) {
        guard coreInfoItem.coreId == "mame" else { return }

        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        let indicatorView = RetroRomActivityView(mainTitle: title)
        indicatorView.install()

        indicatorView.activeMessage(title, title: title)

        if let firmware = coreInfoItem.importFirmwareFile(url) {
            var snapshot = dataSource.snapshot()
            let fileName = url.lastPathComponent
            if let item = firmwareItems.first(where: { item in
                if case .firmware(let data) = item {
                    return data.name == fileName
                }
                return false
            }) {
                if #available(iOS 15.0, *) {
                    snapshot.reconfigureItems([item])
                } else {
                    snapshot.reloadItems([item])
                }
            } else {
                let new = Item.firmware(data: firmware)
                firmwareItems.append(new)
                snapshot.appendItems([new], toSection: .firmware)
            }
            dataSource.apply(snapshot, animatingDifferences: true)


            let message = String(format: Bundle.localizedString(forKey: "coreinfo_firmware_import_success"), 1)
            indicatorView.successMessage(message, title: title, canDismiss: true)
        } else {
            indicatorView.infoMessage(Bundle.localizedString(forKey: "coreinfo_firmware_import_zero"), title: title, canDismiss: true)
        }
    }

    private func openFrimwareFolder(_ url: URL) {
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        let indicatorView = RetroRomActivityView(mainTitle: title)
        indicatorView.install()

        indicatorView.activeMessage(title, title: title)

        let match = coreInfoItem.coreId != "mame"
        let messageFormat = Bundle.localizedString(forKey: "coreinfo_firmware_matching_file")
        coreInfoItem.scanFirmwareFolder(url, match: match, processing: { fileName in
            let message = String(format: messageFormat, fileName)
            indicatorView.activeMessage(message, title: title)
        }, errorHandler: { error in
            let message = String(format: Bundle.localizedString(forKey: "coreinfo_firmware_read_dir_failed"), error.localizedDescription)
            indicatorView.errorMessage(message, title: title, canDismiss: true)
        }) { updatedFirmwares in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if !updatedFirmwares.isEmpty {
                    if match {
                        var snapshot = dataSource.snapshot()

                        // 关键点：使用 reconfigureItems (iOS 15+) 或 reloadItems
                        // reconfigureItems 不会重新创建 Cell，只是重新触发 cellProvider 逻辑，性能更好
                        if #available(iOS 15.0, *) {
                            snapshot.reconfigureItems(firmwareItems)
                        } else {
                            snapshot.reloadItems(firmwareItems)
                        }

                        // 应用快照，系统会自动计算差异并执行动画
                        dataSource.apply(snapshot, animatingDifferences: true)
                    } else {
                        // 获取当前的全局快照
                        var snapshot = dataSource.snapshot()

                        // 1. 获取该 Section 目前已有的所有 Items（旧数据）
                        let oldFirmwareItems = snapshot.itemIdentifiers(inSection: .firmware)

                        // 2. 准备新的 Items
                        let newItems = updatedFirmwares.map({ Item.firmware(data: $0) })

                        // 3. 将新 Items 追加到 Section 中
                        snapshot.appendItems(newItems, toSection: .firmware)

                        // 4. 关键：刷新该 Section 下的所有 Items (包括旧的和刚加进去的)
                        // 注意：如果你只想刷新旧的，就传 oldFirmwareItems；如果要全刷，就传两者之和
                        let allFirmwareItems = oldFirmwareItems + newItems

                        if #available(iOS 15.0, *) {
                            snapshot.reconfigureItems(allFirmwareItems)
                        } else {
                            snapshot.reloadItems(allFirmwareItems)
                        }

                        // 5. 统一应用变更
                        dataSource.apply(snapshot, animatingDifferences: true)
                    }

                    let message = String(format: Bundle.localizedString(forKey: "coreinfo_firmware_import_success"), updatedFirmwares.count)
                    indicatorView.successMessage(message, title: title, canDismiss: true)
                } else {
                    indicatorView.infoMessage(Bundle.localizedString(forKey: "coreinfo_firmware_import_zero"), title: title, canDismiss: true)
                }
            }
        }
    }
}

extension RetroRomCoreInfoViewController {
    enum Section: Hashable {
        case basic, firmware, desc
    }

    struct License: Hashable, Equatable {
        let showName: String
        let fileName: String

        init?(showName: String?, fileName: String?) {
            if let showName = showName, let fileName = fileName {
                self.showName = showName
                self.fileName = fileName
            } else {
                return nil
            }
        }
    }

    enum Item: Hashable {
        case normal(tip: String, value: String)
        case extensions(tip: String, list: [String])
        case runCore(tip: String, value: String, action: (() -> Void)?)
        case firmware(data: EmuCoreFirmware)
        case mameFirmwareTip(core: EmuCoreInfoItem)
        case license(tip: String, licenses: [License])
        case link(tip: String, url: String)

        // MARK: - Hashable
        func hash(into hasher: inout Hasher) {
            switch self {
                case .normal(let tip, let value):
                    hasher.combine("normal")
                    hasher.combine(tip)
                    hasher.combine(value)
                case .extensions(let tip, let list):
                    hasher.combine("exts")
                    hasher.combine(tip)
                    hasher.combine(list)
                case .runCore(let tip, let value, _):
                    hasher.combine("run_core")
                    hasher.combine(tip)
                    hasher.combine(value)
                case .firmware(let data):
                    hasher.combine("firmware")
                    hasher.combine(data)
                case .mameFirmwareTip(let core):
                    hasher.combine("mame_firmware_tip")
                    hasher.combine(core)
                case .license(let tip, let license):
                    hasher.combine("license")
                    hasher.combine(tip)
                    hasher.combine(license)
                case .link(let tip, let url):
                    hasher.combine("link")
                    hasher.combine(tip)
                    hasher.combine(url)
            }
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            switch (lhs, rhs) {
                case (.normal(let lt, let lv), .normal(let rt, let rv)):
                    return lt == rt && lv == rv
                case (.extensions(let lt, let ll), .extensions(let rt, let rl)):
                    return lt == rt && ll == rl
                case (.runCore(let lt, let lv, _), .runCore(let rt, let rv, _)):
                    return lt == rt && lv == rv
                case (.firmware(let ld), .firmware(let rd)):
                    return ld == rd
                case (.mameFirmwareTip(let lc), .mameFirmwareTip(let rc)):
                    return lc == rc
                case (.license(let lt, let ll), license(let rt, licenses: let rl)):
                    return lt == rt && ll == rl
                case (.link(let lt, let lu), .link(let rt, let ru)):
                    return lt == rt && lu == ru
                default: return false
            }
        }
    }

    typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>
    typealias NormalCellRegistration = UICollectionView.CellRegistration<RetroRomCoreInfoViewCell, Item>
    typealias FirmwareCellRegistration = UICollectionView.CellRegistration<RetroRomCoreFrimwareViewCell, EmuCoreFirmware>
    typealias FirmwareHeaderRegistration = UICollectionView.SupplementaryRegistration<RetroRomCoreFirmwareHeaderView>
    typealias FirmwareFooterRegistration = UICollectionView.SupplementaryRegistration<RetroRomCoreFirmwareFooterView>
    typealias MameFirmwareTipCellRegistration = UICollectionView.CellRegistration<RetroRomMameFirmwareTipViewCell, Item>
}
