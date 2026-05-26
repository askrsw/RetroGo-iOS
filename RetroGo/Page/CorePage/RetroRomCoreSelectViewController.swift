//
//  RetroRomCoreSelectViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/12.
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
import YYText
import SnapKit
import ObjcHelper
import RACoordinator

fileprivate final class HeaderView: UITableViewHeaderFooterView {
    let label = {
        let label = UILabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .label
        label.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        return label
    }()

    class var className: String {
        String(describing: Self.self)
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        contentView.backgroundColor = .systemGroupedBackground
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.preferredMaxLayoutWidth = contentView.bounds.width
    }
}

fileprivate final class FooterView: UITableViewHeaderFooterView {
    let label = {
        let label = UILabel()
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
        return label
    }()

    var text: String? {
        didSet {
            guard let text = text else {
                return label.attributedText = nil
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 5
            let attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paragraphStyle,
                .font: label.font!,
                .foregroundColor: label.textColor!
            ]
            label.attributedText = NSAttributedString(string: text, attributes: attributes)
        }
    }

    class var className: String {
        String(describing: Self.self)
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        contentView.backgroundColor = .systemGroupedBackground
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -26),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class RetroRomCoreSelectViewController: UIViewController {
    enum Action {
        case assignCoreForFile(item: RetroRomFileItem)
        case assignCoreForFolder(folder: RetroRomFolderItem)
        case runRomWithItem(item: RetroRomFileItem)
        case runRomWithUrl(url: URL)
    }

    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    let action: Action

    private(set) lazy var dataSource = { [unowned self] in
        let ds = DataSource(tableView: tableView) { [weak self] tableView, indexPath, core in
            guard let self = self else { return nil }
            let cell = tableView.dequeueReusableCell(withIdentifier: RetroRomCoreItemTableViewCell.className) as! RetroRomCoreItemTableViewCell
            cell.coreInfoItem = core
            let preferCore: String?
            switch action {
                case .assignCoreForFile(let item):
                    preferCore = item.preferCore
                case .assignCoreForFolder(let folder):
                    preferCore = folder.preferCore
                case .runRomWithItem(let item):
                    preferCore = item.preferCore
                case .runRomWithUrl(let url):
                    preferCore = nil
            }
            cell.check = core.coreId == preferCore
            return cell
        }

        return ds
    }()

    init(action: Action) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "homepage_select_core")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeAction))

        configureTableView()
        configureSnapshot()
    }
}

extension RetroRomCoreSelectViewController {
    enum Section: Hashable {
        case matched, other
    }

    typealias DataSource = UITableViewDiffableDataSource<Section, EmuCoreInfoItem>
    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, EmuCoreInfoItem>
}

extension RetroRomCoreSelectViewController {

    @objc
    private func closeAction() {
        dismiss(animated: true)
    }

    private func configureSnapshot() {
        var snapshot = Snapshot()
        if case .assignCoreForFolder(_) = action {
            let array = RetroRomCoreManager.shared.allCores
            snapshot.appendSections([.other])
            snapshot.appendItems(array, toSection: .other)
        } else {
            let filePath: String?
            switch action {
                case .assignCoreForFile(let item):
                    filePath = item.entryPath
                case .runRomWithItem(let item):
                    filePath = item.entryPath
                case .runRomWithUrl(let url):
                    filePath = url.path(percentEncoded: false)
                default:
                    fatalError()
            }
            guard let filePath = filePath else { return }

            let matched: [EmuCoreInfoItem]
            let others: [EmuCoreInfoItem]
            let cores = RetroArchX.shared().supportedCores(forRom: filePath)
            if cores.count > 0 {
                matched = cores
                others = RetroArchX.shared().allCores.filter({ !matched.contains($0) })
            } else {
                matched = []
                others = RetroArchX.shared().allCores
            }

            if matched.count > 0 {
                snapshot.appendSections([.matched])
                snapshot.appendItems(matched, toSection: .matched)
            }

            if others.count > 0 {
                snapshot.appendSections([.other])
                snapshot.appendItems(others, toSection: .other)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.rowHeight = 60
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 44
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 44
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.register(RetroRomCoreItemTableViewCell.self, forCellReuseIdentifier: RetroRomCoreItemTableViewCell.className)
        tableView.register(HeaderView.self, forHeaderFooterViewReuseIdentifier: HeaderView.className)
        tableView.register(FooterView.self, forHeaderFooterViewReuseIdentifier: FooterView.className)
    }
}

extension RetroRomCoreSelectViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        guard let core = dataSource.itemIdentifier(for: indexPath) else {
            return
        }

        let checkCellCheckMark: Bool
        switch action {
            case .runRomWithUrl(let url):
                dismiss(animated: true) {
                    RetroArchX.playGame(romUrl: url, core: core)
                }
                checkCellCheckMark = false
            case .runRomWithItem(let item):
                dismiss(animated: true) {
                    RetroArchX.playGame(romItem: item, core: core)
                }
                checkCellCheckMark = true
            case .assignCoreForFile(let item):
                dismiss(animated: true) {
                    if item.assignCore(core) {
                        let message = Bundle.localizedString(forKey: "homepage_assign_core_success")
                        AppToastManager.shared.toast(message, context: .ui, level: .success)
                    } else {
                        let message = Bundle.localizedString(forKey: "homepage_assign_core_failed")
                        AppToastManager.shared.toast(message, context: .ui, level: .error)
                    }
                }
                checkCellCheckMark = true
            case .assignCoreForFolder(let item):
                dismiss(animated: true) {
                    if item.assignCore(core) {
                        let message = Bundle.localizedString(forKey: "homepage_assign_core_success")
                        AppToastManager.shared.toast(message, context: .ui, level: .success)
                    } else {
                        let message = Bundle.localizedString(forKey: "homepage_assign_core_failed")
                        AppToastManager.shared.toast(message, context: .ui, level: .error)
                    }
                }
                checkCellCheckMark = true
        }

        if checkCellCheckMark {
            for cell in tableView.visibleCells {
                guard let cell = cell as? RetroRomCoreItemTableViewCell else {
                    continue
                }

                if cell.check {
                    if tableView.indexPath(for: cell) != indexPath {
                        cell.check = false
                    }
                    break
                }
            }

            let cell = tableView.cellForRow(at: indexPath) as? RetroRomCoreItemTableViewCell
            cell?.check = true
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if case .assignCoreForFolder(_) = action {
            return nil
        } else {
            guard let section = dataSource.sectionIdentifier(for: section) else {
                return nil
            }

            guard let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: HeaderView.className) as? HeaderView else {
                return nil
            }

            switch section {
                case .matched:
                    view.label.text = Bundle.localizedString(forKey: "homepage_matched_core")
                case .other:
                    view.label.text = Bundle.localizedString(forKey: "homepage_other_core")
            }
            return view
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: FooterView.className) as? FooterView else {
            return nil
        }

        if case .assignCoreForFolder(_) = action {
            view.text = Bundle.localizedString(forKey: "homepage_folder_core_tip")
            return view
        } else {
            guard let section = dataSource.sectionIdentifier(for: section) else {
                return nil
            }

            switch section {
                case .matched:
                    view.text = Bundle.localizedString(forKey: "homepage_matched_core_tip")
                case .other:
                    view.text = Bundle.localizedString(forKey: "homepage_other_core_tip")
            }

            return view
        }
    }
}
