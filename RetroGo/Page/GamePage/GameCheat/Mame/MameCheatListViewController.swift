//
//  MameCheatListViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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
import XMLTextRenderKit

/// In-game list of a MAME game's cheats (Pugsy's collection, run by MAME's engine).
/// Text entries of the XML become section titles and notes; the rest are switches,
/// value pickers and "Run" buttons. Pauses the game while open.
final class MameCheatListViewController: UIViewController {
    fileprivate struct Section {
        var title: String?
        var notes: [String] = []
        var rows: [Int] = []   // cheat indices
    }

    private let session: MameCheatSession
    private var sections: [Section] = []
    private var gamePauseLease: GamePauseCoordinator.Lease?
    private lazy var tableView = configUI()
    private let emptyView = UIView(frame: .zero)
    /// The import guide, shown in place of the list until a cheat collection is imported.
    private var guideView: XMLTextRenderView?

    init(session: MameCheatSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        gamePauseLease = acquireGamePause(reason: "mame-cheat-list")
        attachGamePauseLeaseToPresentation(gamePauseLease)

        view.backgroundColor = .systemBackground
        let title = Bundle.localizedString(forKey: "cheat_title")
        navigationItem.title = title
        navigationItem.titleView = Self.makeIconTitleView(title, icon: IconRender.shared.settingsIcon(
            symbol: "star.circle", background: .cheatIconColor, size: CGSize(width: 22, height: 22)))
        let close = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeAction))
        close.tintColor = .label
        navigationItem.leftBarButtonItem = close
        let library = UIBarButtonItem(image: UIImage(systemName: "books.vertical"), style: .plain, target: self, action: #selector(libraryAction))
        library.tintColor = .label
        navigationItem.rightBarButtonItem = library

        _ = tableView
        NotificationCenter.default.addObserver(self, selector: #selector(stateDidChange), name: .gameCheatStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryDidChange), name: .mameCheatLibraryDidChange, object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachGamePauseLeaseToPresentation(gamePauseLease)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isClosingOrBeingDismissedFromGamePauseContext() {
            gamePauseLease?.release()
            gamePauseLease = nil
        }
    }

    private func configUI() -> UITableView {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.tintColor = .mainColor
        table.estimatedRowHeight = 52
        table.rowHeight = UITableView.automaticDimension
        table.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        table.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        view.addSubview(table)
        table.snp.makeConstraints { $0.edges.equalToSuperview() }
        return table
    }

    @objc private func stateDidChange() {
        // The session rebuilds its entries when the library is imported mid-game.
        reload()
    }

    private func reload() {
        sections = Self.makeSections(session.entries)
        tableView.reloadData()
        updateEmptyState()
        updateRestoreHeader()
    }

    /// "Restore last cheats": cheats come back only once the player knows the game is past
    /// its boot sequence (see MameCheatSession).
    private func updateRestoreHeader() {
        let count = session.restorableCount
        guard count > 0 else {
            tableView.tableHeaderView = nil
            return
        }
        var config = UIButton.Configuration.tinted()
        config.title = String(format: Bundle.localizedString(forKey: "mame_cheat_restore_last"), count)
        config.image = UIImage(systemName: "arrow.counterclockwise")
        config.imagePadding = 6
        config.cornerStyle = .large
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.restoreAction() })
        let note = UILabel()
        note.text = Bundle.localizedString(forKey: "mame_cheat_restore_note")
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [button, note])
        stack.axis = .vertical
        stack.spacing = 8
        let header = UIView()
        header.addSubview(stack)
        // Bottom/trailing give way while the header has no size yet (sized in sizeRestoreHeader).
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.bottom.equalToSuperview().offset(-4).priority(.high)
            make.leading.equalTo(header.layoutMarginsGuide)
            make.trailing.equalTo(header.layoutMarginsGuide).priority(.high)
        }
        header.preservesSuperviewLayoutMargins = true
        tableView.tableHeaderView = header
        sizeRestoreHeader()
    }

    /// Table headers are laid out by frame: fit the height to the current table width.
    private func sizeRestoreHeader() {
        guard let header = tableView.tableHeaderView, tableView.bounds.width > 0 else { return }
        let width = tableView.bounds.width
        let height = header.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                    withHorizontalFittingPriority: .required,
                                                    verticalFittingPriority: .fittingSizeLevel).height
        guard header.frame.width != width || header.frame.height != height else { return }
        header.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeRestoreHeader()
    }

    private func restoreAction() {
        guard allowEnabling() else { return }
        Vibration.selection.vibrate()
        session.restoreLastCheats()
    }

    /// A run of text entries starts a new section: a single line is its title, several lines
    /// are one sentence split over entries, shown as a note (joined with spaces, the key its
    /// translation is stored under). Blank entries only start a new section. Trailing text
    /// (e.g. "no cheats because the game did not work") becomes a note of the last section.
    private static func makeSections(_ entries: [MameCheatSession.Entry]) -> [Section] {
        var sections: [Section] = []
        var current = Section()
        var pendingText: [String] = []

        func flush() {
            if !current.rows.isEmpty || !current.notes.isEmpty { sections.append(current) }
            current = Section()
        }
        for entry in entries {
            if entry.kind == .text {
                if entry.definition.hasText {
                    pendingText.append(entry.definition.desc)
                } else if pendingText.isEmpty {
                    flush()
                }
                continue
            }
            if !pendingText.isEmpty {
                flush()
                if pendingText.count == 1 {
                    current.title = pendingText[0]
                } else {
                    current.notes = [pendingText.joined(separator: " ")]
                }
                pendingText = []
            }
            current.rows.append(entry.index)
        }
        if !pendingText.isEmpty {
            if !current.rows.isEmpty || !current.notes.isEmpty {
                flush()
            }
            current.notes = [pendingText.joined(separator: " ")]
        }
        flush()
        return sections
    }

    private func updateEmptyState() {
        emptyView.subviews.forEach { $0.removeFromSuperview() }
        let imported = MameCheatLibrary.shared.isImported
        updateGuide(visible: !imported)
        guard imported else {
            tableView.backgroundView = nil
            return
        }
        let text: String
        if !session.hasCheatFile {
            text = Bundle.localizedString(forKey: "mame_cheat_none_for_game")
        } else if session.entries.isEmpty {
            text = Bundle.localizedString(forKey: "mame_cheat_none_for_game")
        } else {
            tableView.backgroundView = nil
            return
        }

        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        // The table sizes its background view later; start at its size and keep the margins
        // breakable so a zero-size first pass does not conflict.
        emptyView.frame = tableView.bounds
        emptyView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(32).priority(.high)
            make.trailing.lessThanOrEqualToSuperview().offset(-32).priority(.high)
        }
        tableView.backgroundView = emptyView
    }

    /// The step-by-step import guide fills the page until a collection is imported; its
    /// "import" command opens the file picker right here.
    private func updateGuide(visible: Bool) {
        guard visible else {
            guideView?.removeFromSuperview()
            guideView = nil
            tableView.isHidden = false
            return
        }
        tableView.isHidden = true
        guard guideView == nil, let url = MameCheatLibraryViewController.guideURL,
              let xml = try? String(contentsOf: url, encoding: .utf8) else { return }
        let guide = XMLTextRenderView(frame: .zero)
        view.addSubview(guide)
        guide.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        let config = XMLRenderConfig()
        config.mainColor = .mainColor
        guide.render(xmlContent: xml, config: config, commandHandlers: [
            MameCheatLibraryViewController.importCommand: { [weak self] in
                guard let self else { return }
                Vibration.selection.vibrate()
                MameCheatImporter.pickAndImport(from: self)
            }
        ], imageInteractionHandler: { [weak self] tap in
            self?.present(MameGuideImageViewController(image: tap.image), animated: true)
        }, usesDynamicType: true)
        guideView = guide
    }

    /// A collection was imported (or deleted): load it into the running game right away.
    @objc private func libraryDidChange() {
        session.reloadFromLibrary()
    }

    // MARK: - Actions

    @objc private func closeAction() {
        Vibration.selection.vibrate()
        navigationController?.dismiss(animated: true)
    }

    @objc private func libraryAction() {
        Vibration.selection.vibrate()
        // Imports reach this list through .mameCheatLibraryDidChange.
        MameCheatLibraryViewController.show(from: self)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "cheat_title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        (presentedViewController ?? self).present(alert, animated: true)
    }

    /// Netplay check before anything is switched on or run.
    fileprivate func allowEnabling() -> Bool {
        if RANetplayCoordinator.shared.isNetplayEnabled {
            showMessage(Bundle.localizedString(forKey: "netplay_cheat_blocked"))
            return false
        }
        return true
    }

    fileprivate func entry(at indexPath: IndexPath) -> MameCheatSession.Entry? {
        let index = sections[indexPath.section].rows[indexPath.row]
        return session.entries.first { $0.index == index }
    }

    private func toggle(_ entry: MameCheatSession.Entry, on: Bool) {
        if on && !allowEnabling() {
            tableView.reloadData()
            return
        }
        session.setEnabled(on, index: entry.index)
    }

    private func run(_ entry: MameCheatSession.Entry) {
        guard allowEnabling() else { return }
        Vibration.selection.vibrate()
        if session.activate(index: entry.index) {
            AppToastManager.shared.toast(String(format: Bundle.localizedString(forKey: "mame_cheat_activated"),
                                                MameCheatTexts.shared.localized(entry.definition.desc)),
                                         context: .game, level: .info)
        }
    }

    private func pickParameter(_ entry: MameCheatSession.Entry) {
        guard let parameter = entry.definition.parameter else { return }
        let picker = MameCheatParameterViewController(entry: entry, parameter: parameter) { [weak self] position in
            guard let self else { return false }
            if let position {
                guard self.allowEnabling() else { return false }
                if entry.kind == .oneShotParameter {
                    return self.session.activate(index: entry.index, position: position)
                }
                return self.session.setPosition(position, index: entry.index)
            }
            return self.session.setEnabled(false, index: entry.index)
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

extension MameCheatListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard let entry = entry(at: indexPath) else { return cell }
        var content = UIListContentConfiguration.subtitleCell()
        content.text = MameCheatTexts.shared.localized(entry.definition.desc)
        content.secondaryText = entry.definition.comment.map { MameCheatTexts.shared.localized($0) }
        content.secondaryTextProperties.color = .secondaryLabel
        // Room between the name and its hint, and around both, so long hints do not crowd the row.
        content.textToSecondaryTextVerticalPadding = 6
        content.directionalLayoutMargins.top = 12
        content.directionalLayoutMargins.bottom = 12
        content.textProperties.color = entry.available ? .label : .tertiaryLabel
        cell.selectionStyle = .none

        switch entry.kind {
        case .onOff:
            let toggle = UISwitch()
            toggle.isOn = entry.enabled
            toggle.isEnabled = entry.available
            toggle.onTintColor = .mainColor
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }
                self.toggle(entry, on: toggle.isOn)
            }, for: .valueChanged)
            cell.accessoryView = toggle
        case .oneShot:
            var config = UIButton.Configuration.tinted()
            config.title = Bundle.localizedString(forKey: "mame_cheat_run")
            config.cornerStyle = .capsule
            config.buttonSize = .small
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.run(entry) })
            button.isEnabled = entry.available
            button.sizeToFit()
            cell.accessoryView = button
        case .parameter, .oneShotParameter:
            var value = UIListContentConfiguration.valueCell()
            value.text = MameCheatTexts.shared.localized(entry.definition.desc)
            value.textProperties.color = content.textProperties.color
            if entry.kind == .parameter {
                value.secondaryText = entry.enabled && entry.position >= 0
                    ? entry.definition.parameter.map { MameCheatTexts.shared.localized($0.title(at: entry.position)) }
                    : Bundle.localizedString(forKey: "mame_cheat_off")
            } else {
                value.secondaryText = Bundle.localizedString(forKey: "mame_cheat_choose_run")
            }
            content = value
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = entry.available ? .default : .none
        default:
            break
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = sections[section].title else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as? RGSectionHeaderView
        header?.text = MameCheatTexts.shared.localized(title)
        return header
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        var lines = sections[section].notes.map { MameCheatTexts.shared.localized($0) }
        if section == sections.count - 1 {
            lines.append(String(format: Bundle.localizedString(forKey: "mame_cheat_credit"), MameCheatLibrary.sourceName,
                                MameCheatLibrary.sourceURL.host ?? ""))
        }
        guard !lines.isEmpty else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as? RGSectionFooterView
        footer?.text = lines.joined(separator: "\n")
        return footer
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let entry = entry(at: indexPath), entry.available,
              entry.kind == .parameter || entry.kind == .oneShotParameter else { return }
        Vibration.selection.vibrate()
        pickParameter(entry)
    }
}

/// Values of a parameter cheat. "Off" is offered for regular parameters; picking a value
/// of a one-shot parameter runs it once.
private final class MameCheatParameterViewController: UITableViewController {
    private let entry: MameCheatSession.Entry
    private let parameter: MameCheatDefinition.Parameter
    /// nil = off. Returns whether the change was applied.
    private let onSelect: (Int?) -> Bool
    private var selected: Int?

    init(entry: MameCheatSession.Entry, parameter: MameCheatDefinition.Parameter, onSelect: @escaping (Int?) -> Bool) {
        self.entry = entry
        self.parameter = parameter
        self.onSelect = onSelect
        // Parameters start off every launch; the remembered value is shown as the choice.
        selected = entry.position >= 0 ? entry.position : nil
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var offersOff: Bool { entry.kind == .parameter }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = MameCheatTexts.shared.localized(entry.definition.desc)
        tableView.tintColor = .mainColor
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let selected {
            tableView.scrollToRow(at: IndexPath(row: selected + (offersOff ? 1 : 0), section: 0), at: .middle, animated: false)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        parameter.count + (offersOff ? 1 : 0)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "value") ?? UITableViewCell(style: .default, reuseIdentifier: "value")
        var content = UIListContentConfiguration.cell()
        let position = offersOff ? indexPath.row - 1 : indexPath.row
        content.text = position < 0
            ? Bundle.localizedString(forKey: "mame_cheat_off")
            : MameCheatTexts.shared.localized(parameter.title(at: position))
        cell.contentConfiguration = content
        let isOff = entry.kind == .parameter && !entry.enabled
        cell.accessoryType = (position < 0 ? isOff : (!isOff && selected == position)) ? .checkmark : .none
        if isOff, position >= 0, position == selected {
            content.secondaryText = Bundle.localizedString(forKey: "mame_cheat_last_used")
            cell.contentConfiguration = content
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        entry.kind == .oneShotParameter ? Bundle.localizedString(forKey: "mame_cheat_one_shot_footer") : nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let position = offersOff ? indexPath.row - 1 : indexPath.row
        let value: Int? = position < 0 ? nil : position
        Vibration.selection.vibrate()
        guard onSelect(value) else { return }
        selected = value
        tableView.reloadData()
        navigationController?.popViewController(animated: true)
    }
}
