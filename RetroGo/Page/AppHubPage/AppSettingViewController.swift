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
    private lazy var proButton = AppSettingProButton(target: self, action: #selector(purchaseAction(_:)))
    private var entitlementRefreshTask: Task<Void, Never>?

    deinit {
        entitlementRefreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "settings_main_title")
        navigationItem.largeTitleDisplayMode = .automatic

        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: proButton)

        _ = tableView
        _ = dataSource

        applySnapshot(animated: false)

        proButton.reloadPurchaseState()
        NotificationCenter.default.addObserver(self, selector: #selector(purchaseStateDidChange(_:)), name: .appStorePurchaseStateDidChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        proButton.reloadPurchaseState()
        refreshPurchaseState()
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
        case coreSettingList

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
        // Extend edge-to-edge so the scroll view passes UNDER the nav bar.
        // UIKit needs an under-bar scroll view to drive the large-title
        // collapse animation; clipping to `safeAreaLayoutGuide` would leave
        // the bar with nothing to track and the small-title fallback would
        // never appear. Content inset is adjusted automatically via the
        // default `contentInsetAdjustmentBehavior = .automatic`.
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
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

            // Shared geometry for every leading icon on this page. Using
            // the same size for the squircle icons and the language-row
            // dot keeps the text leading edge aligned across all rows.
            // Color semantics follow `12_ui_design_system.md`
            // (AppSetting color convention).
            let iconSize = CGSize(width: 28, height: 28)

            switch item {
            case .systemHomepage:
                let switchControl = UISwitch()
                switchControl.isOn = AppSettings.shared.systemHomePage
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(systemHomepageChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "house.fill",
                    background: .systemBlue,
                    size: iconSize
                )
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_use_system_homepage")
                cell.accessoryView = switchControl
                return cell
            case .uiHaptic:
                let switchControl = UISwitch()
                switchControl.isOn = AppSettings.shared.isUIFeedbackEnabled
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(uiHapticChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "hand.tap.fill",
                    background: .systemPink,
                    size: iconSize
                )
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_ui_haptic_feedback")
                cell.accessoryView = switchControl
                return cell
            case .languageFollowSystem:
                let switchControl = UISwitch()
                switchControl.isOn = AppSettings.shared.languageFollowSystem
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(languageFollowSystemChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "globe",
                    background: .systemIndigo,
                    size: iconSize
                )
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_language_follow_system")
                cell.accessoryView = switchControl
                return cell
            case .language(let key, let displayName):
                // Sub-row radio selection — intentionally keeps the small
                // dot pattern (not a colored squircle) per design doc.
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = IconRender.shared.dotImage(size: iconSize, color: .mainColor)
                cell.textLabel?.text = displayName
                cell.accessoryType = Bundle.currentLanguage() == key ? .checkmark : .none
                return cell

            case .coreList:
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "cpu.fill",
                    background: .systemOrange,
                    size: iconSize
                )
                cell.textLabel?.text = Bundle.localizedString(forKey: "corelist_core_list")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .coreSettingList:
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "slider.horizontal.3",
                    background: .systemGray,
                    size: iconSize
                )
                cell.textLabel?.text = Bundle.localizedString(forKey: "corelist_core_settings")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .inGameHaptic:
                let switchControl = UISwitch()
                switchControl.isOn = true
                switchControl.onTintColor = .mainColor
                switchControl.addTarget(self, action: #selector(inGameHapticChanged(_:)), for: .valueChanged)
                let cell = cellBuilder()
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "sensor.tag.radiowaves.forward.fill",
                    background: .systemPink,
                    size: iconSize
                )
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_ingame_haptic_feedback")
                cell.accessoryView = switchControl
                return cell

            case .versionHeistory:
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "clock.fill",
                    background: .systemIndigo,
                    size: iconSize
                )
                cell.textLabel?.text = Bundle.localizedString(forKey: "appsetting_version_history")
                cell.accessoryType = .disclosureIndicator
                return cell
            case .about:
                let cell = cellBuilder()
                cell.accessoryView = nil
                cell.imageView?.image = IconRender.shared.settingsIcon(
                    symbol: "info.circle.fill",
                    background: .systemBlue,
                    size: iconSize
                )
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

        let gameItems: [Item] = [.coreList, .coreSettingList]
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
        case .coreList, .coreSettingList: return true
        case .about, .versionHeistory: return true
        default: return false
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .language(let key, _): changeLanguage(key: key)
        case .coreList: showCoreList(action: .showCoreInfo)
        case .coreSettingList: showCoreList(action: .configureCore)
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

    private func showCoreList(action: EmuCoreListViewController.Action) {
        Vibration.selection.vibrate()

        guard RetroArchX.shared().initialized else { return }

        let controller = EmuCoreListViewController(action: action)
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
        navigationItem.title = Bundle.localizedString(forKey: "settings_main_title")
        proButton.reloadPurchaseState()
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
    private func purchaseAction(_ sender: Any) {
        Vibration.selection.vibrate()
        let controller = AppStorePurchaseViewController()
        let naviController = UINavigationController(rootViewController: controller)
        present(naviController, animated: true)
    }

    @objc
    private func purchaseStateDidChange(_ notification: Notification) {
        proButton.reloadPurchaseState()
    }

    private func refreshPurchaseState() {
        entitlementRefreshTask?.cancel()
        entitlementRefreshTask = Task { @MainActor [weak self] in
            try? await AppStorePurchaseManager.shared.loadProducts()
            await AppStorePurchaseManager.shared.refreshEntitlements(allowClearingActiveEntitlement: true)
            guard !Task.isCancelled else { return }
            self?.proButton.reloadPurchaseState()
        }
    }
}

private final class AppSettingProButton: UIControl {
    private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let iconView = UIImageView(image: UIImage(systemName: "crown.fill"))
    private let statusBadgeView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let titleLabel = UILabel()
    private var currentTitle = "Pro"

    init(target: Any?, action: Selector) {
        super.init(frame: .zero)
        configUI()
        reloadPurchaseState()
        frame.size = intrinsicContentSize
        addTarget(target, action: action, for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
                self.alpha = self.isHighlighted ? 0.82 : 1.0
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        let iconWidth: CGFloat = 20
        let spacing: CGFloat = 6
        let horizontalPadding: CGFloat = 20
        let titleWidth = ceil((currentTitle as NSString).size(withAttributes: [.font: titleLabel.font as Any]).width)
        return CGSize(width: iconWidth + spacing + titleWidth + horizontalPadding, height: 38)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let radius = bounds.height / 2
        layer.cornerRadius = radius
        effectView.layer.cornerRadius = radius
    }

    func reloadPurchaseState() {
        apply(entitlement: AppStorePurchaseManager.shared.activeProEntitlement)
    }

    private func configUI() {
        accessibilityLabel = "RetroGo Pro"
        accessibilityTraits = .button

        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        clipsToBounds = true

        effectView.isUserInteractionEnabled = false
        effectView.clipsToBounds = true
        addSubview(effectView)
        effectView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.tintColor = UIColor(hex: 0xFFD700, alpha: 1.0)
        iconView.contentMode = .scaleAspectFit

        titleLabel.font = .systemFont(ofSize: UIFont.labelFontSize, weight: .semibold)
        titleLabel.text = currentTitle

        statusBadgeView.tintColor = .systemGreen
        statusBadgeView.contentMode = .scaleAspectFit
        statusBadgeView.isHidden = true

        let iconContainer = UIView()
        iconContainer.isUserInteractionEnabled = false
        iconContainer.addSubview(iconView)
        iconContainer.addSubview(statusBadgeView)

        let stackView = UIStackView(arrangedSubviews: [iconContainer, titleLabel])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.isUserInteractionEnabled = false
        addSubview(stackView)

        iconContainer.snp.makeConstraints { make in
            make.size.equalTo(22)
        }

        iconView.snp.makeConstraints { make in
            make.size.equalTo(20)
            make.center.equalToSuperview()
        }

        statusBadgeView.snp.makeConstraints { make in
            make.size.equalTo(11)
            make.top.equalToSuperview().offset(-1)
            make.trailing.equalToSuperview().offset(1)
        }

        stackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.equalToSuperview().offset(10)
            make.trailing.equalToSuperview().offset(-10)
        }
    }

    private func apply(entitlement: AppStoreProEntitlementInfo?) {
        if let entitlement {
            if entitlement.isInFreeTrial {
                currentTitle = Bundle.localizedString(forKey: "iap_trial_status")
                titleLabel.text = currentTitle
                titleLabel.textColor = UIColor(hex: 0xFFD700, alpha: 1.0)
                statusBadgeView.isHidden = true
                effectView.contentView.backgroundColor = UIColor(hex: 0xFFD700, alpha: 0.08)
                layer.borderColor = UIColor(hex: 0xFFD700, alpha: 0.32).cgColor
                accessibilityLabel = "RetroGo Pro Trial"
            } else {
                currentTitle = "Pro"
                titleLabel.text = currentTitle
                titleLabel.textColor = UIColor(hex: 0xFFD700, alpha: 1.0)
                statusBadgeView.isHidden = false
                effectView.contentView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.08)
                layer.borderColor = UIColor(hex: 0xFFD700, alpha: 0.36).cgColor
                accessibilityLabel = "RetroGo Pro Active"
            }
        } else {
            currentTitle = "Pro"
            titleLabel.text = currentTitle
            titleLabel.textColor = .mainColor
            statusBadgeView.isHidden = true
            effectView.contentView.backgroundColor = UIColor.clear
            layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
            accessibilityLabel = "RetroGo Pro"
        }

        invalidateIntrinsicContentSize()
        frame.size = intrinsicContentSize
        setNeedsLayout()
        layoutIfNeeded()
    }
}
