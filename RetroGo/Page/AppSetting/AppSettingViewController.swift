//
//  AppSettingViewController.swift
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
import XMLTextRenderKit

final class AppSettingViewController: UIViewController {
    private lazy var tableView  = self.configUI()
    private lazy var dataSource = self.configDS()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "homepage_main_title")

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), landscapeImagePhone: UIImage(systemName: "xmark.circle"), style: .plain, target: self, action: #selector(closeAction(_:)))
        navigationItem.leftBarButtonItem?.tintColor = .mainColor

        _ = tableView
        _ = dataSource

        applySnapshot(animated: false)
    }
}

extension AppSettingViewController {
    typealias DataSource = UITableViewDiffableDataSource<Section, Item>
    typealias Snapshot   = NSDiffableDataSourceSnapshot<Section, Item>

    enum Section: Hashable {
        case main, game, about
    }

    enum Item: Hashable {

        // main section
        case systemHomepage // 系统首页开关
        case languageFollowSystem // 跟随系统语言开关
        case language(String, String) // 语言选项（key, displayName）
        case uiHaptic

        // game section
        case coreList
        case inGameHaptic

        // about
        case about
        case versionHeistory
    }

    private func configUI() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.estimatedRowHeight = 50
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
        let ds = DataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self = self else { return nil }

            let cellBuilder = {
                if let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell") {
                    return cell
                } else {
                    return UITableViewCell(style: .default, reuseIdentifier: "UITableViewCell")
                }
            }

            switch item {
            case .systemHomepage:
                let switchControl = UISwitch()
                switchControl.isOn = AppSettings.shared.systemHomePage
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(systemHomepageChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = UIImage(systemName: "house")
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_use_system_homepage")
                cell.accessoryView = switchControl
                return cell
            case .uiHaptic:
                let switchControl = UISwitch()
                switchControl.isOn = AppSettings.shared.isUIFeedbackEnabled
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(uiHapticChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = UIImage(systemName: "hand.tap")
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_ui_haptic_feedback")
                cell.accessoryView = switchControl
                return cell
            case .languageFollowSystem:
                let switchControl = UISwitch()
                switchControl.isOn = AppSettings.shared.languageFollowSystem
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(languageFollowSystemChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = UIImage(systemName: "globe")
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_language_follow_system")
                cell.accessoryView = switchControl
                return cell
            case .language(let key, let displayName):
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = IconRender.shared.dotImage(size: CGSize(width: 25, height: 25), color: .mainColor)
                cell.textLabel?.text = displayName
                cell.accessoryType = Bundle.currentLanguage() == key ? .checkmark : .none
                return cell

            case .coreList:
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = UIImage(systemName: "cpu")
                cell.textLabel?.text = Bundle.localizedString(forKey: "corelist_core_list")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .inGameHaptic:
                let switchControl = UISwitch()
                switchControl.isOn = true
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(inGameHapticChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = UIImage(systemName: "sensor.tag.radiowaves.forward")
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_ingame_haptic_feedback")
                cell.accessoryView = switchControl
                return cell

            case .versionHeistory:
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = UIImage(systemName: "clock.arrow.circlepath")
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_version_history")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .about:
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = UIImage(systemName: "info.circle")
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_about")
                cell.accessoryType = .disclosureIndicator
                return cell

            }
        }
        return ds
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = Snapshot()
        snapshot.appendSections([.main, .game, .about])

        var mainItems: [Item] = [.systemHomepage, .uiHaptic, .languageFollowSystem]
        if !AppSettings.shared.languageFollowSystem {
            let languageItems = Bundle.languages().map { Item.language($0[0], $0[1]) }
            mainItems.append(contentsOf: languageItems)
        }
        snapshot.appendItems(mainItems, toSection: .main)

        let gameItems: [Item] = [.coreList]
        snapshot.appendItems(gameItems, toSection: .game)

        let aboutItems: [Item] = [.versionHeistory, .about]
        snapshot.appendItems(aboutItems, toSection: .about)

        dataSource.apply(snapshot, animatingDifferences: animated)
    }
}

extension AppSettingViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        50
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        case .language: return true
        case .coreList: return true
        case .about, .versionHeistory: return true
        default: return false
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .language(let key, _): changeLanguage(key: key)
        case .coreList: showCoreList()
        case .about: showAbout()
        case .versionHeistory: showVersionHistory()
        default: break
        }
    }
}

extension AppSettingViewController {
    private func showVersionHistory() {
        Vibration.selection.vibrate()

        let languageKey = Bundle.currentSimpleLanguageKey()
        if let url = Bundle.main.url(forResource: "version", withExtension: "xml", subdirectory: "Data/xmls/\(languageKey)") {
            let title = Bundle.localizedString(forKey: "appsetting_version_history")
            let config = XMLRenderConfig()
            config.mainColor = .mainColor
            let controller = XMLTextRenderViewController(xmlUrl: url, mainTitle: title, config: config)
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    private func showCoreList() {
        Vibration.selection.vibrate()

        guard RetroArchX.shared().initialized else { return }

        let controller = EmuCoreListViewController()
        navigationController?.pushViewController(controller, animated: true)
    }

    private func showAbout() {
        Vibration.selection.vibrate()

        let languageKey = Bundle.currentSimpleLanguageKey()
        if let url = Bundle.main.url(forResource: "about", withExtension: "xml", subdirectory: "Data/xmls/\(languageKey)") {
            let title = Bundle.localizedString(forKey: "appsetting_about")
            let config = XMLRenderConfig()
            config.mainColor = .mainColor
            let controller = XMLTextRenderViewController(xmlUrl: url, mainTitle: title, config: config)
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    private func updateText() {
        navigationItem.title = Bundle.localizedString(forKey: "homepage_main_title")
    }

    private func changeLanguage(key: String) {
        Vibration.selection.vibrate()

        if key != Bundle.currentLanguage() {
            Bundle.setLanguage(key, storeKey: true)
            updateText()

            var snapshot = dataSource.snapshot()
            let allItems = snapshot.itemIdentifiers
            snapshot.reconfigureItems(allItems)
            dataSource.apply(snapshot, animatingDifferences: false)

            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    @objc
    private func systemHomepageChanged(_ sender: UISwitch) {
        guard let sceneDelegate = UIApplication.shared.sceneDelegate else {
            return
        }
        AppSettings.shared.systemHomePage = sender.isOn
        sceneDelegate.switchSystemHomepageController()
    }

    @objc
    private func uiHapticChanged(_ sender: UISwitch) {
        AppSettings.shared.isUIFeedbackEnabled = sender.isOn
    }

    @objc
    private func inGameHapticChanged(_ sender: UISwitch) {

    }

    @objc
    private func languageFollowSystemChanged(_ sender: UISwitch) {
        let updateLanguage = Bundle.systemLanguage() != Bundle.currentLanguage()
        AppSettings.shared.languageFollowSystem = sender.isOn
        if sender.isOn {
            Bundle.setLanguageFollowSystem()
        } else {
            Bundle.setLanguage(Bundle.systemLanguage(), storeKey: true)
        }

        applySnapshot(animated: true)

        if updateLanguage {
            updateText()
            var snapshot = dataSource.snapshot()
            let allItems = snapshot.itemIdentifiers
            snapshot.reconfigureItems(allItems)
            dataSource.apply(snapshot, animatingDifferences: false)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    @objc
    private func closeAction(_ sender: UIBarButtonItem) {
        Vibration.selection.vibrate()
        navigationController?.dismiss(animated: true)
    }
}
