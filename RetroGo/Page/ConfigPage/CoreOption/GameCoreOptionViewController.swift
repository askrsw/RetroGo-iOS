//
//  GameCoreOptionViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/19.
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
import ObjcHelper

final class GameCoreOptionViewController: UITableViewController {
    private enum Row: Hashable { case info(Int), group(String), option(String) }

    private let session: GameCoreOptionSession
    private let settings: GameConfigSession
    private let titleEntries: [GameConfigEntry]

    /// Groups start expanded; only the ones the user collapsed are tracked, so a
    /// group revealed later by `visibleWhen` also starts expanded.
    private var collapsed = Set<String>()
    private var dataSource: UITableViewDiffableDataSource<Int, Row>!
    private let pinnedGroup = UIButton(type: .system)
    private var pinnedGroupID: String?
    private var applyingSnapshot = false
    private lazy var optionsByKey = Dictionary(uniqueKeysWithValues: session.catalog.groups.flatMap(\.options).map { ($0.key, $0) })

    /// Groups with options hidden by `visibleWhen` removed, evaluated against current values.
    private var groups: [GameCoreOptionCatalog.Group] {
        session.catalog.groups.compactMap { group in
            let options = group.options.filter { isVisible($0) }
            guard !options.isEmpty else { return nil }
            return GameCoreOptionCatalog.Group(id: group.id, title: group.title, description: group.description, options: options)
        }
    }
    private var resetTitle: String {
        Bundle.localizedString(forKey: settings.scope == .game ? "coreoption_follow_core" : "coreoption_reset")
    }
    private var inheritedTitle: String {
        Bundle.localizedString(forKey: settings.scope == .game ? "coreoption_inherited_core" : "coreoption_default")
    }

    init(session: GameCoreOptionSession, settings: GameConfigSession) {
        self.session = session
        self.settings = settings
        titleEntries = settings.makeTitleConfigEntries()
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "coreoption_title")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: resetTitle, style: .plain, target: self, action: #selector(resetOptions))

        session.onSaveError = { [weak self] error in
            NSLog("[CoreOptions] Save failed: %@", String(describing: error))
            guard let self else { return }
            let alert = UIAlertController(title: Bundle.localizedString(forKey: "coreoption_title"), message: Bundle.localizedString(forKey: "coreoption_save_error"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "coreoption_ok"), style: .default))
            // Selection sheets finish dismissing before presenting the error.
            if let presented = presentedViewController {
                presented.dismiss(animated: true) { [weak self] in self?.present(alert, animated: true) }
            } else { present(alert, animated: true) }
        }

        tableView.tintColor = .mainColor
        tableView.estimatedRowHeight = 64
        tableView.rowHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 50
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "option")
        tableView.register(GameCoreOptionValueCell.self, forCellReuseIdentifier: "value")
        tableView.register(GameConfigTitleViewCell.self, forCellReuseIdentifier: "info")

        pinnedGroup.backgroundColor = .secondarySystemGroupedBackground
        pinnedGroup.layer.cornerRadius = 12
        pinnedGroup.contentHorizontalAlignment = .leading
        pinnedGroup.addTarget(self, action: #selector(collapsePinnedGroup), for: .touchUpInside)
        pinnedGroup.isHidden = true
        tableView.addSubview(pinnedGroup)

        configDataSource()
        reload()
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 0 else { return nil }
        let footer = RGSectionFooterView(reuseIdentifier: nil)
        footer.text = [GameConfigSection.title.getSectionFooterText(session: settings), Bundle.localizedString(forKey: "coreoption_runtime_warning")].compactMap { $0 }.joined(separator: "\n\n")
        return footer
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section == 0 ? UITableView.automaticDimension : 20
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !applyingSnapshot, let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .group(let id):
            if !collapsed.insert(id).inserted { collapsed.remove(id) }
            reload()
        case .option(let key):
            guard let option = option(key), !option.isSwitch else { return }
            // A pushed list keeps every value list identical, however long it is, and
            // avoids the popover anchoring oddly for rows near the top of the screen.
            let picker = GameCoreOptionValueListViewController(option: option, session: session, core: settings.core, resetTitle: resetTitle) { [weak self] in
                self?.reload()
            }
            navigationController?.pushViewController(picker, animated: true)
        case .info: break
        }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) { updatePinnedGroup() }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let row = dataSource.itemIdentifier(for: indexPath), case .option(let key) = row,
              let option = option(key) else { return nil }
        let action = UIContextualAction(style: .normal, title: resetTitle) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            completion(session.reset([option]))
            reload()
        }
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePinnedGroup()
    }
}

extension GameCoreOptionViewController {
    private func configDataSource() {
        dataSource = UITableViewDiffableDataSource<Int, Row>(tableView: tableView) { [weak self] table, index, row in
            guard let self else { return nil }
            if case .info(let item) = row {
                let cell = table.dequeueReusableCell(withIdentifier: "info", for: index) as! GameConfigTitleViewCell
                cell.entry = self.titleEntries[item]
                cell.selectionStyle = .none
                return cell
            }
            // Reconfiguration must dequeue the same cell with the same identifier.
            if case .option(let key) = row, let option = self.option(key) {
                let cell = table.dequeueReusableCell(withIdentifier: "value", for: index) as! GameCoreOptionValueCell
                cell.configure(option: option, valueTitle: self.selectedTitle(option), session: self.session, inheritedTitle: self.inheritedTitle) { [weak self] in
                    // Switches may change which dependent options are visible.
                    if self?.hasDependents(option) == true { self?.reload() }
                }
                return cell
            }
            let cell = table.dequeueReusableCell(withIdentifier: "option", for: index)
            cell.accessoryView = nil
            cell.accessoryType = .none
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button
            cell.accessibilityValue = nil
            var content = UIListContentConfiguration.subtitleCell()
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            switch row {
            case .group(let id):
                guard let group = self.groups.first(where: { $0.id == id }) else { return cell }
                content.text = GameCoreOptionCatalog.text(group.title, fallback: id)
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                content.secondaryText = GameCoreOptionCatalog.text(group.description)
                let image = UIImageView(image: UIImage(systemName: self.isExpanded(id) ? "chevron.down" : "chevron.right"))
                image.tintColor = .secondaryLabel
                cell.accessoryView = image
                cell.accessibilityValue = Bundle.localizedString(forKey: self.isExpanded(id) ? "coreoption_expanded" : "coreoption_collapsed")
            case .option, .info: break
            }
            cell.contentConfiguration = content
            return cell
        }
    }

    private func isExpanded(_ groupId: String) -> Bool {
        !collapsed.contains(groupId)
    }

    private func option(_ key: String) -> GameCoreOptionCatalog.Option? {
        optionsByKey[key]
    }

    private func isVisible(_ option: GameCoreOptionCatalog.Option) -> Bool {
        option.isVisible { [session, optionsByKey] key in optionsByKey[key].map(session.value(for:)) }
    }

    private func hasDependents(_ option: GameCoreOptionCatalog.Option) -> Bool {
        optionsByKey.values.contains { $0.visibleWhen.contains { $0[option.key] != nil } }
    }

    private func reload(completion: (() -> Void)? = nil) {
        guard !applyingSnapshot else { return }

        applyingSnapshot = true
        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
        snapshot.appendSections([0])
        snapshot.appendItems(titleEntries.indices.map { .info($0) }, toSection: 0)
        for (index, group) in groups.enumerated() {
            snapshot.appendSections([index + 1])
            snapshot.appendItems([.group(group.id)], toSection: index + 1)
            if isExpanded(group.id) {
                snapshot.appendItems(group.options.map { .option($0.key) }, toSection: index + 1)
            }
        }
        let oldItems = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { oldItems.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            applyingSnapshot = false
            tableView.layoutIfNeeded()
            completion?()
            updatePinnedGroup()
        }
    }

    private func selectedTitle(_ option: GameCoreOptionCatalog.Option) -> String {
        let value = session.value(for: option)
        return option.label(for: value)
    }

    private func updatePinnedGroup() {
        guard isViewLoaded, dataSource != nil, !applyingSnapshot else { return }

        let top = tableView.contentOffset.y + tableView.adjustedContentInset.top
        let height = max(50, UIFont.preferredFont(forTextStyle: .headline).lineHeight + 24)
        for (index, group) in groups.enumerated() where isExpanded(group.id) {
            let section = index + 1
            let first = tableView.rectForRow(at: IndexPath(row: 0, section: section))
            let bounds = tableView.rect(forSection: section)
            guard first.maxY <= top, bounds.maxY > top else { continue }
            if pinnedGroupID != group.id {
                var configuration = UIButton.Configuration.plain()
                configuration.title = GameCoreOptionCatalog.text(group.title, fallback: group.id)
                configuration.image = UIImage(systemName: "chevron.down")
                configuration.imagePlacement = .trailing
                configuration.imagePadding = 12
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
                pinnedGroup.configuration = configuration
            }
            let frame = CGRect(x: first.minX, y: min(top, bounds.maxY - height), width: first.width, height: height)
            if pinnedGroup.frame != frame { pinnedGroup.frame = frame }
            pinnedGroupID = group.id
            pinnedGroup.isHidden = false
            tableView.bringSubviewToFront(pinnedGroup)
            return
        }
        pinnedGroup.isHidden = true
        pinnedGroupID = nil
    }

    @objc
    private func collapsePinnedGroup() {
        guard !applyingSnapshot, let id = pinnedGroupID, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        collapsed.insert(id)
        reload { [weak self] in
            self?.tableView.scrollToRow(at: IndexPath(row: 0, section: index + 1), at: .top, animated: false)
        }
    }

    @objc
    private func resetOptions() {
        let message = Bundle.localizedString(forKey: settings.scope == .game ? "coreoption_follow_core_message" : "coreoption_reset_message")
        let alert = UIAlertController(title: resetTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "coreoption_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: resetTitle, style: .destructive) { [weak self] _ in
            guard let self else { return }
            session.resetAll()
            reload()
        })
        present(alert, animated: true)
    }
}

private final class GameCoreOptionValueCell: UITableViewCell {
    private let nameLabel = UILabel(frame: .zero)
    private let valueLabel = UILabel(frame: .zero)
    private let helpButton = UIButton(type: .system)
    private var explanation = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(option: GameCoreOptionCatalog.Option, valueTitle: String, session: GameCoreOptionSession, inheritedTitle: String, onChange: @escaping () -> Void) {

        nameLabel.text = GameCoreOptionCatalog.text(option.title, fallback: option.key)

        let source = session.isOverridden(option) ? Bundle.localizedString(forKey: "coreoption_overridden") : inheritedTitle
        valueLabel.text = option.isSwitch ? source : valueTitle + " · " + source
        valueLabel.isHidden = false

        var paragraphs = [GameCoreOptionCatalog.text(option.description)].filter { !$0.isEmpty }
        if option.restartRequired { paragraphs.append(Bundle.localizedString(forKey: "coreoption_restart")) }
        explanation = paragraphs.joined(separator: "\n\n")
        helpButton.isHidden = explanation.isEmpty
        helpButton.accessibilityLabel = nameLabel.text
        accessoryView = nil
        accessoryType = .none
        selectionStyle = option.isSwitch ? .none : .default

        if option.isSwitch {
            let control = UISwitch(frame: .zero)
            control.onTintColor = .mainColor
            control.isOn = session.value(for: option) == "enabled"
            control.accessibilityLabel = nameLabel.text
            control.addAction(UIAction { [weak self] action in
                guard let control = action.sender as? UISwitch else { return }
                if session.select(control.isOn ? "enabled" : "disabled", for: option) {
                    self?.valueLabel.text = Bundle.localizedString(forKey: "coreoption_overridden")
                    onChange()
                } else {
                    control.setOn(session.value(for: option) == "enabled", animated: true)
                }
            }, for: .valueChanged)
            accessoryView = control
        } else {
            accessoryType = .disclosureIndicator
        }
    }

    private func configUI() {
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.numberOfLines = 0
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .secondaryLabel
        valueLabel.numberOfLines = 0
        valueLabel.adjustsFontForContentSizeCategory = true

        helpButton.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
        helpButton.tintColor = .label
        helpButton.addTarget(self, action: #selector(showHelp), for: .touchUpInside)

        let titleRow = UIStackView(arrangedSubviews: [nameLabel, helpButton, UIView(frame: .zero)])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 6

        let stack = UIStackView(arrangedSubviews: [titleRow, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        // Let the table's temporary encapsulated height win during self-sizing
        // and reuse, while preserving the full content height when measured.
        let bottom = stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        bottom.priority = UILayoutPriority(999)

        // UIStackView imposes zero width when an arranged button is hidden.
        let helpWidth = helpButton.widthAnchor.constraint(equalToConstant: 32)
        helpWidth.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            helpWidth,
            helpButton.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            bottom
        ])
    }

    @objc
    private func showHelp() {
        Vibration.selection.vibrate()
        GameConfigDescView(desc: explanation).install(source: helpButton)
    }
}
