//
//  GameConfigViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/18.
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
import os

final class GameConfigViewController: UIViewController {
    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    let showCloseButton: Bool
    let applyInputBinding: Bool
    let session: GameConfigSession
    let configData: [(section: GameConfigSection, entries: [GameConfigEntry])]

    private var gamePauseLease: GamePauseCoordinator.Lease?
    private var startedDummyCoreForConfig = false
    private var installedTopologyHandler = false
    private var openedWhileGameRunning = false

    init(session: GameConfigSession, applyInputBinding: Bool, showCloseButton: Bool) {
        self.showCloseButton = showCloseButton
        self.session = session
        self.applyInputBinding = applyInputBinding
        self.configData = session.makeConfigData()
        super.init(nibName: nil, bundle: nil)

        // Pause only while a real game is running; never pause the dummy scene
        let ra = RetroArchX.shared()
        openedWhileGameRunning = (ra.currentCoreItem != nil) && !ra.dummyCoreRunning
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let ra = RetroArchX.shared()

        if installedTopologyHandler {
            RAInputActionManager.shared().topologyChangedHandler = nil
            installedTopologyHandler = false
        }

        if startedDummyCoreForConfig {
            _ = ra.stopDummyCoreIfNeeded()
            startedDummyCoreForConfig = false
        }

        gamePauseLease?.release()
        gamePauseLease = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if openedWhileGameRunning {
            gamePauseLease = acquireGamePause(reason: "game-config")
            attachGamePauseLeaseToPresentation(gamePauseLease)
        }

        view.backgroundColor = .systemBackground
        navigationItem.title = getMainTitle()
        navigationItem.titleView = makeTitleView()
        navigationItem.largeTitleDisplayMode = .never

        if showCloseButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeAction))
            navigationItem.leftBarButtonItem?.tintColor = .label
        }

    #if DEBUG
        installCoreOptionExportButtonIfNeeded()
    #endif

        prepareInputRuntimeIfNeeded()
        applyInputBindingIfNeeded()
        installTopologyChangedHandler()

        _ = tableView
        _ = dataSource
        applySnapshot(animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isClosingOrBeingDismissedFromGamePauseContext() {
            gamePauseLease?.release()
            gamePauseLease = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachGamePauseLeaseToPresentation(gamePauseLease)
    }
}

extension GameConfigViewController {
    @objc
    func closeAction() {
        Vibration.selection.vibrate()
        dismiss(animated: true)
    }

    func getMainTitle() -> String {
        switch session.scope {
            case .global: return Bundle.localizedString(forKey: "configpage_global_setting")
            case .core: return Bundle.localizedString(forKey: "configpage_core_setting")
            case .game: return Bundle.localizedString(forKey: "configpage_rom_setting")
        }
    }

    func makeTitleView() -> UIView? {
        let icon: UIImage?
        switch session.scope {
        case .global: icon = UIImage(systemName: "globe")
        // A filled "adjust settings" badge (like the cheat title icon), distinct
        // from the app-wide Settings gear so per-game settings read differently.
        case .game: icon = IconRender.shared.settingsIcon(symbol: "slider.horizontal.3", background: .mainColor, size: CGSize(width: 22, height: 22))
        case .core:
            if let key = session.core?.coreIcon {
                icon = IconRender.shared.platformIcon(key: key, size: CGSize(width: 20, height: 20))
            } else {
                icon = nil
            }
        }
        guard let icon = icon else { return nil }
        return Self.makeIconTitleView(getMainTitle(), icon: icon)
    }

    func prepareInputRuntimeIfNeeded() {
        let ra = RetroArchX.shared()

        // Outside a game: start the dummy; during a game: don't
        guard !openedWhileGameRunning else { return }
        guard ra.currentCoreItem == nil else { return }
        guard !ra.dummyCoreRunning else { return }

        ra.startDummyCoreIfNeeded { [weak self] success in
            guard let self else { return }
            if success {
                self.startedDummyCoreForConfig = true
                self.applySnapshot(animated: true)
            }
        }
    }

    func applyInputBindingIfNeeded() {
        guard applyInputBinding else { return }
        let cfg = session.config
        RAInputActionManager.shared().apply(cfg?.inputBindingProfile, coreCapabilities: cfg?.coreCaps, useLock: true)
    }

    func installTopologyChangedHandler() {
        guard !installedTopologyHandler else { return }
        installedTopologyHandler = true

        RAInputActionManager.shared().topologyChangedHandler = { [weak self] in
            guard let self else { return }
            if let section = configData.first(where: { $0.0 == .controller}) {
                section.entries.forEach({ $0.refresh.toggle() })
            }
        }
    }
}

extension GameConfigViewController {
    typealias DataSource = UITableViewDiffableDataSource<GameConfigSection, GameConfigEntry>
    typealias Snapshot   = NSDiffableDataSourceSnapshot<GameConfigSection, GameConfigEntry>

    private func applySnapshot(animated: Bool) {
        var snapshot = Snapshot()
        snapshot.appendSections(configData.map({ $0.section }))
        for item in configData {
            snapshot.appendItems(item.entries, toSection: item.section)
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.estimatedRowHeight = 50
        tableView.estimatedSectionHeaderHeight = 32
        tableView.estimatedSectionFooterHeight = 44
        tableView.sectionHeaderHeight = UITableView.automaticDimension
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

    private func configDS() -> DataSource {
        let ds = DataSource(tableView: tableView) { [weak self] tableView, indexPath, entry in
            guard let self = self else { return nil}
            switch entry.ui {
            case .label: return makeCell(GameConfigTitleViewCell.self, entry: entry)
            case .switch: return makeCell(GameConfigSwitchViewCell.self, entry: entry)
            case .segmentcontrol: return makeCell(GameConfigSegmentViewCell.self, entry: entry)
            case .list: return makeCell(GameConfigLabelViewCell.self, entry: entry)
            case .controller: return makeCell(GameConfigLabelViewCell.self, entry: entry)
            }
        }
        return ds
    }

    private func dequeueCell<T: GameConfigBaseViewCell>(_ cellType: T.Type) -> T {
        let cellId = String(describing: cellType)
        if let cell = tableView.dequeueReusableCell(withIdentifier: cellId) as? T {
            return cell
        } else {
            return T(style: .default, reuseIdentifier: cellId)
        }
    }

    private func makeCell<T: GameConfigBaseViewCell>(_ cellType: T.Type, entry: GameConfigEntry) -> UITableViewCell {
        let cell: T = dequeueCell(cellType)
        cell.entry = entry
        return cell
    }
}

extension GameConfigViewController: UITableViewDelegate {
    private func makeFooterView(_ text: String) -> RGSectionFooterView {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as? RGSectionFooterView
            ?? RGSectionFooterView(reuseIdentifier: RGSectionFooterView.className)
        view.text = text
        return view
    }

    private func makeHeaderView(_ text: String) -> RGSectionHeaderView {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as? RGSectionHeaderView
            ?? RGSectionHeaderView(reuseIdentifier: RGSectionHeaderView.className)
        view.text = text
        return view
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section < configData.count else { return nil }

        let text = configData[section].section.getSectionFooterText(session: session)
        guard let text, !text.isEmpty else { return nil }

        return makeFooterView(text)
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard section < configData.count else { return .leastNormalMagnitude }

        let text = configData[section].section.getSectionFooterText(session: session)
        if text?.isEmpty == false {
            return UITableView.automaticDimension
        }

        // Keep visual spacing between sections even when no footer text exists.
        return 28
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < configData.count else { return nil }

        let text = configData[section].section.getSectionHeaderText(session: session)
        guard let text, !text.isEmpty else { return nil }

        return makeHeaderView(text)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard section < configData.count else { return .leastNormalMagnitude }

        let text = configData[section].section.getSectionHeaderText(session: session)
        if text?.isEmpty == false {
            return UITableView.automaticDimension
        }

        return section == 0 ? .leastNormalMagnitude : 20
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let entry = dataSource.itemIdentifier(for: indexPath) else {
            return false
        }
        if entry.opensCoreOptions { return entry.enabled }
        switch entry.ui {
        case .list: return entry.enabled
        case .controller: return true
        default: return false
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        guard let entry = dataSource.itemIdentifier(for: indexPath) else { return }
        if entry.opensCoreOptions {
            guard let core = session.core else { return }
            do {
                let options = try session.makeCoreOptionSession()
                navigationController?.pushViewController(GameCoreOptionViewController(session: options, settings: session), animated: true)
            } catch {
                RetroGoLogger.coreOption.error("Failed to load catalog for \(core.coreId, privacy: .public): \(String(describing: error))")
                let alert = UIAlertController(title: Bundle.localizedString(forKey: "coreoption_title"), message: Bundle.localizedString(forKey: "coreoption_load_error"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "coreoption_ok"), style: .default))
                present(alert, animated: true)
            }
            return
        }
        switch entry.ui {
        case .list:
            let selector = GameConfigListItemSelector(entry: entry)
            navigationController?.pushViewController(selector, animated: true)
        case .controller:
            let selector = GameConfigControllerSelector(entry: entry, playerIndex: indexPath.row)
            navigationController?.pushViewController(selector, animated: true)
        default: break
        }
    }
}

#if DEBUG
// MARK: - DEBUG: export runtime core options as catalog JSON

extension GameConfigViewController {
    private static let debugCoreOptionExportDirectory = "CoreOptionExport"

    fileprivate func installCoreOptionExportButtonIfNeeded() {
        guard openedWhileGameRunning, debugExportCoreId() != nil else { return }
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(debugExportCoreOptions))
        navigationItem.rightBarButtonItem?.tintColor = .label
    }

    private func debugExportCoreId() -> String? {
        guard let coreId = session.core?.coreId,
              let running = RetroArchX.shared().currentCoreItem?.coreId,
              coreId.caseInsensitiveCompare(running) == .orderedSame else { return nil }
        return coreId
    }

    @objc fileprivate func debugExportCoreOptions() {
        let title: String
        let message: String
        do {
            let (path, languages, count) = try debugWriteCoreOptionCatalog()
            title = "导出成功"
            message = "\(count) 个选项，已包含语言：\(languages.joined(separator: ", "))\n\n\(path)\n\n在设置里切换 App 语言（English / 简体中文）后重新进入游戏再次导出，会与该文件合并。"
        } catch {
            title = "导出失败"
            message = error.localizedDescription
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func debugWriteCoreOptionCatalog() throws -> (String, [String], Int) {
        func fail(_ text: String) -> NSError {
            NSError(domain: "CoreOptionExport", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        guard let coreId = debugExportCoreId() else { throw fail("当前没有运行该核心") }
        guard let snapshot = RetroArchX.shared().debugCurrentCoreOptionsSnapshot(),
              let language = snapshot["language"] as? String,
              let categories = snapshot["categories"] as? [[String: Any]],
              let options = snapshot["options"] as? [[String: Any]], !options.isEmpty else {
            throw fail("核心没有注册 Core Option")
        }
        guard !language.isEmpty else { throw fail("RetroArch 当前语言不是 en / zh-Hans，请切换 App 语言后重新进入游戏") }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.debugCoreOptionExportDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(coreId + "_core_options.json")

        // Existing export (other language) to merge localized strings into.
        var oldGroups: [String: [String: Any]] = [:]
        var oldOptions: [String: [String: Any]] = [:]
        var languages = Set([language])
        if let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (root["coreId"] as? String) == coreId {
            for group in root["groups"] as? [[String: Any]] ?? [] {
                guard let id = group["id"] as? String else { continue }
                oldGroups[id] = group
                for option in group["options"] as? [[String: Any]] ?? [] {
                    if let key = option["key"] as? String { oldOptions[key] = option }
                }
            }
            let source = root["source"] as? [String: Any]
            languages.formUnion(source?["languages"] as? [String] ?? [])
        }

        func localized(_ old: Any?, _ text: String) -> [String: String] {
            var dict = old as? [String: String] ?? [:]
            dict[language] = text
            return dict
        }

        func str(_ dict: [String: Any], _ key: String) -> String { dict[key] as? String ?? "" }

        // Group order follows the core's category order; uncategorized options go first in "general".
        var groupOrder = categories.map { str($0, "key") }
        var groupMeta: [String: (String, String)] = [:]
        for cat in categories { groupMeta[str(cat, "key")] = (str(cat, "desc"), str(cat, "info")) }
        var groupOptions: [String: [[String: Any]]] = [:]

        for option in options {
            let key = str(option, "key")
            let categoryKey = str(option, "categoryKey")
            let groupId = categoryKey.isEmpty || groupMeta[categoryKey] == nil ? "general" : categoryKey
            if groupId == "general", !groupOrder.contains("general") { groupOrder.insert("general", at: 0) }

            let categorized = groupId != "general"
            let desc = categorized && !str(option, "descCategorized").isEmpty ? str(option, "descCategorized") : str(option, "desc")
            let info = categorized && !str(option, "infoCategorized").isEmpty ? str(option, "infoCategorized") : str(option, "info")
            // Some cores register the same value more than once; keep the first label.
            var seenValues = Set<String>()
            let pairs = zip(option["values"] as? [String] ?? [], option["labels"] as? [String] ?? [])
                .filter { seenValues.insert($0.0).inserted }
            let values = pairs.map(\.0)
            let labels = pairs.map(\.1)
            let old = oldOptions[key]

            var valueLabels = old?["valueLabels"] as? [String: [String: String]] ?? [:]
            for (value, label) in zip(values, labels) {
                valueLabels[value] = localized(valueLabels[value], label)
            }
            valueLabels = valueLabels.filter { values.contains($0.key) }

            var entry: [String: Any] = [
                "key": key,
                "title": localized(old?["title"], desc),
                "description": localized(old?["description"], info),
                "categoryId": groupId,
                "type": Set(values) == Set(["enabled", "disabled"]) ? "bool" : "select",
                "defaultValue": str(option, "defaultValue"),
                "restartRequired": old?["restartRequired"] as? Bool ?? true,
                "values": values,
                "valueLabels": valueLabels,
            ]
            if (option["visible"] as? Bool) == false { entry["initiallyHidden"] = true }
            groupOptions[groupId, default: []].append(entry)
        }

        let groups: [[String: Any]] = groupOrder.compactMap { id in
            guard let entries = groupOptions[id], !entries.isEmpty else { return nil }
            let old = oldGroups[id]
            let (desc, info) = groupMeta[id] ?? (language == "zh-Hans" ? "通用" : "General", "")
            return [
                "id": id,
                "title": localized(old?["title"], desc),
                "description": localized(old?["description"], info),
                "options": entries,
            ]
        }

        let core = RetroArchX.shared().currentCoreItem
        let root: [String: Any] = [
            "schemaVersion": 1,
            "version": 1,
            "coreId": coreId,
            "format": "libretro-core-options-v2",
            "source": [
                "generator": "RetroGo runtime export (core_option_manager)",
                "coreName": core?.coreName ?? "",
                "coreVersion": core?.version ?? "",
                "languages": languages.sorted(),
            ] as [String: Any],
            "groups": groups,
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)

        let catalog = try JSONDecoder().decode(GameCoreOptionCatalog.self, from: data)
        try catalog.validate(expectedCoreId: coreId)
        RetroGoLogger.coreOption.debug("Debug export: \(options.count) options (\(language, privacy: .public)) written to \(url.path)")
        return (url.path, languages.sorted(), options.count)
    }
}
#endif // DEBUG
