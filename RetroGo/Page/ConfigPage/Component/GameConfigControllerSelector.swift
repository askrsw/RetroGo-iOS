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
import GameController

final class GameConfigControllerSelector: UIViewController {
    private lazy var tableView = configUI()
    private lazy var dataSource = configDS()
    private lazy var layouts = GameOverlayLayoutSession(
        templateId: GamePageOverlayConfig.resolvedOverlayName(entry.session?.core?.overlayName),
        game: entry.session?.game, coreId: entry.session?.core?.coreId
    )
    private var selectedControllerValue: AnyHashable?
    private var selectedLayoutId: String?
    private lazy var emptyTipView = makeEmptyTipView()
    private var hasConnectedControllers: Bool {
        !GCController.controllers().isEmpty && entry.getListArray?().list.isEmpty == false
    }

    let entry: GameConfigEntry
    let playerIndex: Int

    init(entry: GameConfigEntry, playerIndex: Int) {
        self.entry = entry
        self.playerIndex = playerIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.title = entry.title
        _ = tableView
        _ = dataSource
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(inputDevicesChanged), name: name, object: nil)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySnapshot()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func inputDevicesChanged() {
        // Let the MFi driver finish updating device slots before reading the list.
        DispatchQueue.main.async { [weak self] in self?.applySnapshot() }
        // Autoconfiguration publishes device names through the task queue.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.applySnapshot() }
    }
}

private extension GameConfigControllerSelector {
    enum Item: Hashable {
        case controller(title: String, value: AnyHashable)
        case layout(id: String?, name: String)
    }
    typealias DataSource = UITableViewDiffableDataSource<String, Item>
    typealias Snapshot = NSDiffableDataSourceSnapshot<String, Item>

    func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.estimatedRowHeight = 50
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 60
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.tintColor = .mainColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "controller")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        return tableView
    }

    func configDS() -> DataSource {
        DataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return nil }
            let cell = tableView.dequeueReusableCell(withIdentifier: "controller", for: indexPath)
            cell.accessoryView = nil
            cell.accessoryType = .none
            cell.accessibilityTraits.remove(.selected)
            var content = cell.defaultContentConfiguration()
            content.textProperties.color = .label
            switch item {
            case .controller(let title, let value):
                content.text = title
                cell.accessoryType = value == selectedControllerValue ? .checkmark : .none
            case .layout(let id, let name):
                let selected = id == selectedLayoutId
                content.text = name
                content.image = UIImage(systemName: "checkmark")
                content.imageProperties.tintColor = selected ? .mainColor : .clear
                if selected { cell.accessibilityTraits.insert(.selected) }
                let editTitle = Bundle.localizedString(forKey: "configpage_binding_edit")
                let button = UIButton(type: .system)
                var configuration = UIButton.Configuration.plain()
                configuration.title = editTitle
                button.configuration = configuration
                button.accessibilityLabel = "\(editTitle), \(name)"
                button.addAction(UIAction { [weak self] _ in
                    self?.editMapping(layoutId: id)
                }, for: .touchUpInside)
                button.sizeToFit()
                cell.accessoryView = button
            }
            cell.contentConfiguration = content
            return cell
        }
    }

    func applySnapshot() {
        let result = entry.getListArray?()
        guard !GCController.controllers().isEmpty, let result, !result.list.isEmpty else {
            selectedControllerValue = nil
            selectedLayoutId = nil
            tableView.backgroundView = emptyTipView
            tableView.separatorStyle = .none
            dataSource.apply(Snapshot(), animatingDifferences: false)
            return
        }
        tableView.backgroundView = nil
        tableView.separatorStyle = .singleLine
        selectedControllerValue = result.selected.flatMap { index in
            guard result.list.indices.contains(index) else { return nil }
            return result.list[index].value
        }
        do {
            selectedLayoutId = try entry.session?.inputBindingLayoutId(for: playerIndex)
        } catch {
            selectedLayoutId = nil
        }
        var snapshot = Snapshot()
        snapshot.appendSections(["controllers", "layouts"])
        snapshot.appendItems(result.list.map { .controller(title: $0.title, value: $0.value) }, toSection: "controllers")
        snapshot.appendItems([.layout(id: nil, name: Bundle.localizedString(forKey: "overlay_layout_builtin"))]
            + layouts.layouts().map { .layout(id: $0.id, name: $0.name) }, toSection: "layouts")
        // Reconfigure reused rows as the selected identities are separate from item identity.
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { existing.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func editMapping(layoutId: String?) {
        guard hasConnectedControllers else { applySnapshot(); return }
        let editingLayout: GameOverlayLayoutGameChoice = layoutId.map { .custom($0) } ?? .builtIn
        let configurator = GameControllerInputBindingConfigurator(
            session: entry.session, playerIndex: playerIndex, editingLayout: editingLayout)
        navigationController?.pushViewController(configurator, animated: true)
    }

    func chooseLayout(_ id: String?) {
        guard hasConnectedControllers else { applySnapshot(); return }
        guard id != selectedLayoutId else { return }
        guard layouts.canChooseLayout(id: id)
            || AppStoreProFeatureGate.shared.requirePro(feature: .overlayLayoutSelection, from: self) else { return }
        do {
            guard let session = entry.session else { return }
            try session.chooseInputBindingLayout(id, for: playerIndex)
        } catch {
            let alert = UIAlertController(title: Bundle.localizedString(forKey: "overlay_layout_save_failed"),
                                          message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
            present(alert, animated: true)
            return
        }
        entry.session?.refreshInputBindingProfile()
        (GamePageViewController.instance?.configSession ?? entry.session)?.refreshInputBindingProfile(apply: true)
        entry.refresh.toggle()
        applySnapshot()
    }

    func makeEmptyTipView() -> UIView {
        let view = UIView()
        let icon = UIImageView(image: UIImage(systemName: "gamecontroller"))
        icon.tintColor = .mainColor
        icon.contentMode = .scaleAspectFit
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 6
        label.attributedText = NSAttributedString(
            string: Bundle.localizedString(forKey: "configpage_no_controllers_connected_tip"),
            attributes: [.paragraphStyle: paragraph])
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        view.addSubview(stack)
        icon.snp.makeConstraints { $0.size.equalTo(120) }
        label.snp.makeConstraints { $0.width.lessThanOrEqualTo(320) }
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(60)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(36)
            make.trailing.lessThanOrEqualToSuperview().offset(-36)
        }
        return view
    }
}

extension GameConfigControllerSelector: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard hasConnectedControllers else { applySnapshot(); return }
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        Vibration.selection.vibrate()
        switch item {
        case .controller(_, let value):
            entry.setListSelectedValue?(value)
            entry.refresh.toggle()
            applySnapshot()
        case .layout(let id, _):
            chooseLayout(id)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard tableView.backgroundView == nil else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as? RGSectionHeaderView
            ?? RGSectionHeaderView(reuseIdentifier: RGSectionHeaderView.className)
        header.text = Bundle.localizedString(forKey: section == 0 ? "configpage_connected_controllers" : "configpage_button_mapping")
        header.topInset = section == 1 ? 48 : 12
        return header
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 1, tableView.backgroundView == nil else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as? RGSectionFooterView
            ?? RGSectionFooterView(reuseIdentifier: RGSectionFooterView.className)
        footer.text = Bundle.localizedString(forKey: "configpage_binding_layout_link_footer")
        return footer
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section == 1 ? UITableView.automaticDimension : .leastNormalMagnitude
    }
}
