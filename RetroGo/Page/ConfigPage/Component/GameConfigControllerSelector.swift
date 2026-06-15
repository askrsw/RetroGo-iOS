//
//  GameConfigControllerSelector.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/1.
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

final class GameConfigControllerSelector: UIViewController {
    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    private var oldSelectedIndex: IndexPath?

    let entry: GameConfigEntry
    let playerIndex: Int

    init(entry: GameConfigEntry, playerIndex: Int) {
        self.entry = entry
        self.playerIndex = playerIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = entry.title

        _ = tableView
        _ = dataSource
        applySnapshot(animated: false)
    }
}

private extension GameConfigControllerSelector {
    typealias DataSource = UITableViewDiffableDataSource<String, Item>
    typealias Snapshot   = NSDiffableDataSourceSnapshot<String, Item>

    struct Item: Hashable {
        let title: String
        let value: AnyHashable
    }

    func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.estimatedRowHeight = 50
        tableView.estimatedSectionFooterHeight = 44
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.tintColor = .mainColor
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        return tableView
    }

    func configDS() -> DataSource {
        let ds = DataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self = self else { return nil }
            let cell = {
                if let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell") {
                    return cell
                } else {
                    return UITableViewCell(style: .default, reuseIdentifier: "UITableViewCell")
                }
            }()

            cell.textLabel?.text = item.title
            if indexPath.section == 0 {
                cell.accessoryType = indexPath == oldSelectedIndex ? .checkmark : .none
            } else {
                cell.accessoryType = .disclosureIndicator
            }
            return cell
        }
        return ds
    }

    func applySnapshot(animated: Bool) {
        guard let result = entry.getListArray?() else {
            return
        }

        if result.list.isEmpty {
            updateEmptyTip(isEmpty: true)
            return
        }

        oldSelectedIndex = nil
        if let selected = result.selected {
            oldSelectedIndex = IndexPath(item: selected, section: 0)
        }

        var snapshot = Snapshot()
        snapshot.appendSections(["main", "config"])
        snapshot.appendItems(result.list.map({ Item(title: $0.title, value: $0.value) }), toSection: "main")

        if oldSelectedIndex != nil {
            snapshot.appendItems([makeConfigItem()], toSection: "config")
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    func insertConfigItemIfNeeded(animated: Bool) {
        var snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains("config"),
              snapshot.itemIdentifiers(inSection: "config").isEmpty else {
            return
        }

        snapshot.appendItems([makeConfigItem()], toSection: "config")
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    func makeConfigItem() -> Item {
        Item(title: Bundle.localizedString(forKey: "configpage_button_mapping"), value: "")
    }

    func hasConfigItem() -> Bool {
        let snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains("config") else {
            return false
        }

        return !snapshot.itemIdentifiers(inSection: "config").isEmpty
    }

    func updateEmptyTip(isEmpty: Bool) {
        guard isEmpty else {
            tableView.backgroundView = nil
            tableView.separatorStyle = .singleLine
            return
        }

        let tipText = Bundle.localizedString(forKey: "configpage_no_controllers_connected_tip")
        let tipImage = UIImage(systemName: "gamecontroller")

        tableView.backgroundView = makeEmptyTipView(text: tipText, image: tipImage)
        tableView.separatorStyle = .none
    }

    func makeEmptyTipView(text: String, image: UIImage?) -> UIView {
        GameConfigListEmptyTipView(text: text, image: image)
    }
}

extension GameConfigControllerSelector: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        if indexPath.section == 0 {
            let needsInsertConfigItem = oldSelectedIndex == nil

            if let oldSelectedIndex {
                if let cell = tableView.cellForRow(at: oldSelectedIndex) {
                    cell.accessoryType = .none
                }
            }

            if let cell = tableView.cellForRow(at: indexPath) {
                cell.accessoryType = .checkmark
            }
            oldSelectedIndex = indexPath

            if let item = dataSource.itemIdentifier(for: indexPath) {
                entry.setListSelectedValue?(item.value)
                entry.refresh.toggle()

                if needsInsertConfigItem {
                    insertConfigItemIfNeeded(animated: true)
                }
            }
        } else if indexPath.section == 1 {
            let configurator = GameControllerInputBindingConfigurator(session: entry.session, playerIndex: playerIndex)
            navigationController?.pushViewController(configurator, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == 0 {
            return makeHeaderView(Bundle.localizedString(forKey: "configpage_connected_controllers"))
        } else if section == 1, hasConfigItem() {
            return makeHeaderView(Bundle.localizedString(forKey: "setting"))
        } else {
            return UIView(frame: .zero)
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 || (section == 1 && hasConfigItem()) {
            return UITableView.automaticDimension
        } else {
            return .leastNormalMagnitude
        }
    }

    private func makeHeaderView(_ text: String) -> UITableViewHeaderFooterView {
        if tableView.backgroundView != nil {
            return UITableViewHeaderFooterView(frame: .zero)
        }
        let header = {
            let viewId = "GameConfigHeaderView"
            if let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: viewId) as? GameConfigHeaderView {
                return view
            } else {
                return GameConfigHeaderView(reuseIdentifier: viewId)
            }
        }()
        header.text = text
        return header
    }
}

private final class GameConfigListEmptyTipView: UIView {
    private let maxContentWidth: CGFloat = 320
    private let horizontalPadding: CGFloat = 36
    private var contentWidthConstraint: Constraint?

    init(text: String, image: UIImage?) {
        super.init(frame: .zero)
        configUI(text: text, image: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableWidth = max(0, bounds.width - horizontalPadding * 2)
        contentWidthConstraint?.update(offset: min(maxContentWidth, availableWidth))
    }

    private func configUI(text: String, image: UIImage?) {
        let iconView = UIImageView(image: image)
        iconView.tintColor = .mainColor
        iconView.contentMode = .scaleAspectFit

        let label = UILabel(frame: .zero)
        label.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.attributedText = makeAttributedText(text)

        let stackView = UIStackView(arrangedSubviews: [iconView, label])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16

        addSubview(stackView)
        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(120)
        }

        label.snp.makeConstraints { make in
            contentWidthConstraint = make.width.lessThanOrEqualTo(maxContentWidth).constraint
        }

        stackView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(60)
            make.centerX.equalToSuperview()
        }
    }

    private func makeAttributedText(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 6

        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: UIFont.labelFontSize),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
