//
//  GamePageViewController.swift
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
import StoreKit
import ObjcHelper
import RACoordinator

final class GamePageViewController: RetroArchViewController {
    static private(set) weak var instance: GamePageViewController?

    private let inGameInfoView = InGameInfoView(frame: .zero)

    private let romItem: RetroRomFileItem?
    private let romUrl: URL?
    private let core: EmuCoreInfoItem
    private let startTime: Date

    private var startDate: Date?

    init(romUrl: URL?, core: EmuCoreInfoItem) {
        self.romItem  = nil
        self.romUrl   = romUrl
        self.core = core
        self.startTime = Date()
        super.init()
        Self.instance = self

        _ = self.romUrl?.startAccessingSecurityScopedResource()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(showInGameMessageNotification(_:)), name: .showInGameMessage, object: nil)
    }

    init(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        self.romItem   = romItem
        self.romUrl    = URL(fileURLWithPath: romItem.fullPath!)
        self.core      = core
        self.startTime = Date()
        super.init()
        Self.instance = self

        _ = self.romUrl?.startAccessingSecurityScopedResource()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(showInGameMessageNotification(_:)), name: .showInGameMessage, object: nil)

        romItem.updateLastPlayAt()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        self.romUrl?.stopAccessingSecurityScopedResource()

        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        if Self.instance == self {
            Self.instance = nil
        }

        if let start = startDate {
            let diff = Date().timeIntervalSince(start)
            let seconds = Int(diff.rounded(.toNearestOrAwayFromZero))
            romItem?.updatePlayTime(seconds: seconds)
        }

        let startTime = self.startTime
        DispatchQueue.main.async {
            let now = Date()
            let dd = startTime.distance(to: now)
            if dd > 60 * 2 {
                if AppSettings.shared.checkAndMarkRatingRequest() {
                    if let scene = UIWindow.currentKey()?.windowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        RetroArchX.shared().start(romUrl?.path(percentEncoded: false), core: core)

        if AppSettings.shared.autoSaveLoadState, let coreId = RetroArchX.shared().currentCoreItem?.coreId {
            let name = getAutoSaveStateName()
            let stateFolder = AppConfig.shared.statesFolder + coreId
            let autoPath = "\(stateFolder)/\(name).state"
            RetroArchX.shared().loadState(from: autoPath)
        }

        configHud()

        view.addSubview(inGameInfoView)
        inGameInfoView.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading).offset(20)
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing).offset(-20)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-10)
            make.height.greaterThanOrEqualTo(25)
        }

        startDate = Date()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

//        let width  = view.width
//        let height = view.height
//        let safeAreaInsets = view.safeAreaInsets
//        let x = safeAreaInsets.left + 20
//        let h = 25.0
//        let y = height - safeAreaInsets.bottom - h
//        let w = width - x - 20 - safeAreaInsets.right
//        inGameInfoView.frame = CGRect(x: x, y: y, width: w, height: h)
    }

    override func showInGameMessage(_ message: EmuInGameMessage) {
        inGameInfoView.showMessage(message)
    }
}

extension GamePageViewController {
    private func configHud() {
        let closeImage  = UIImage(systemName: "xmark.circle")
        let closeButton = UIButton(type: .system)
        closeButton.tintColor = UIColor.label
        closeButton.setImage(closeImage, for: .normal)
        closeButton.addTarget(self, action: #selector(closeAction), for: .touchUpInside)
        closeButton.sizeToFit()
        hudView.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.leading.equalTo(hudView.safeAreaLayoutGuide.snp.leading).offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(closeButton.size)
        }

        var lastTrailing: ConstraintItem = hudView.safeAreaLayoutGuide.snp.trailing

        let coreInfoImage  = UIImage(systemName: "cpu")
        let coreInfoButton = UIButton(type: .system)
        coreInfoButton.tintColor = .label
        coreInfoButton.setImage(coreInfoImage, for: .normal)
        coreInfoButton.addTarget(self, action: #selector(coreInfoAction), for: .touchUpInside)
        coreInfoButton.sizeToFit()
        hudView.addSubview(coreInfoButton)
        coreInfoButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(coreInfoButton.size)
        }
        lastTrailing = coreInfoButton.snp.leading

        let restartImage  = UIImage(systemName: "arrow.clockwise.circle")
        let restartButton = UIButton(type: .system)
        restartButton.tintColor = .label
        restartButton.setImage(restartImage, for: .normal)
        restartButton.addTarget(self, action: #selector(restartAction), for: .touchUpInside)
        restartButton.sizeToFit()
        hudView.addSubview(restartButton)
        restartButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(restartButton.size)
        }
        lastTrailing = restartButton.snp.leading

        let snapImage  = UIImage(systemName: "photo.circle")
        let snapButton = UIButton(type: .system)
        snapButton.tintColor = .label
        snapButton.setImage(snapImage, for: .normal)
        snapButton.addTarget(self, action: #selector(snapAction), for: .touchUpInside)
        snapButton.sizeToFit()
        hudView.addSubview(snapButton)
        snapButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(snapButton.size)
        }
        lastTrailing = snapButton.snp.leading

        if(RetroArchX.shared().isCurrentCoreSupportsSavestate()) {
            let loadImage  = UIImage(systemName: "arrowshape.up.circle")
            let loadButton = UIButton(type: .system)
            loadButton.tintColor = .label
            loadButton.setImage(loadImage, for: .normal)
            loadButton.addTarget(self, action: #selector(loadStateAction), for: .touchUpInside)
            loadButton.sizeToFit()
            hudView.addSubview(loadButton)
            loadButton.snp.makeConstraints { make in
                make.trailing.equalTo(lastTrailing).offset(-20)
                make.centerY.equalToSuperview()
                make.size.equalTo(loadButton.size)
            }
            lastTrailing = loadButton.snp.leading

            let saveImage  = UIImage(systemName: "arrowshape.down.circle")
            let saveButton = UIButton(type: .system)
            saveButton.tintColor = .label
            saveButton.setImage(saveImage, for: .normal)
            saveButton.addTarget(self, action: #selector(saveStateAction), for: .touchUpInside)
            saveButton.sizeToFit()
            hudView.addSubview(saveButton)
            saveButton.snp.makeConstraints { make in
                make.trailing.equalTo(lastTrailing).offset(-20)
                make.centerY.equalToSuperview()
                make.size.equalTo(saveButton.size)
            }
            lastTrailing = saveButton.snp.leading
        }
    }

    private func getAutoSaveStateName() -> String {
        let name: String
        if let sha256 = romItem?.sha256 {
            name = "auto_\(sha256)"
        } else if let coreInfoItem = RetroArchX.shared().currentCoreItem {
            name = "auto_\(coreInfoItem.coreId)"
        } else {
            name = RetroRomGameStateItem.stateAutoSaveName
        }
        return name
    }
}

extension GamePageViewController {

    @objc
    private func appWillResignActive() {
        if Self.instance == self {
            if let startDate = startDate {
                let diff = Date().timeIntervalSince(startDate)
                let seconds = Int(diff.rounded(.toNearestOrAwayFromZero))
                romItem?.updatePlayTime(seconds: seconds)
                self.startDate = nil
            }

            if AppSettings.shared.autoSaveLoadState {
                let name = getAutoSaveStateName()
                _ = RetroRomFileManager.shared.saveState(rawName: name, showName: nil, sha256: romItem?.sha256, romKey: romItem?.key, autoSave: true)
                romItem?.pulseImage = !(romItem?.pulseImage ?? false)
            }

            RetroArchX.shared().pause()
        }
    }

    @objc
    private func appWillBecomeActive() {
        if Self.instance == self {
            if self.startDate == nil {
                startDate = Date()
            }

            RetroArchX.shared().resume()
        }
    }

    @objc
    private func showInGameMessageNotification(_ notif: NSNotification) {
        guard let message = notif.object as? EmuInGameMessage else {
            return
        }
        showInGameMessage(message)
    }

    @objc
    private func snapAction() {
        let nowString = DateFormatter.yyyyMMddHHmmss().string(from: Date())
        let pngName  = "snap-\(nowString).png"
        let snapPath = AppConfig.shared.snapshotFolder + pngName
        RetroArchX.shared().saveScreenshot(to: snapPath)
    }

    @objc
    private func saveStateAction() {
        guard RetroArchX.shared().isCurrentCoreSupportsSavestate() else {
            return
        }

        let title = Bundle.localizedString(forKey: "gamepage_save_state")
        let message = Bundle.localizedString(forKey: "gamepage_input_state_name")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            let nowString = DateFormatter.yyyyMMddHHmmss().string(from: Date())
            textField.placeholder = Bundle.localizedString(forKey: "gamepage_name_state")
            textField.text = nowString
        }
        let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { _ in
            RetroArchX.shared().resume()
        }
        alert.addAction(cancelAction)
        let okAction = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default) { [weak self] _ in
            let now = Date()
            let rawName = DateFormatter.yyyyMMddHHmmss().string(from: now)
            let showName = alert.textFields?.first?.text ?? ""
            let ret = RetroRomFileManager.shared.saveState(rawName: rawName, showName: showName, sha256: self?.romItem?.sha256, romKey: self?.romItem?.key, autoSave: false)
            if ret {
                let str = String(format: Bundle.localizedString(forKey: "gamepage_state_saved"), showName)
                let msg = EmuInGameMessage(message: str, title: nil, type: .info, duration: 3.5, priority: 0)
                self?.inGameInfoView.showMessage(msg)
            } else {
                let str = String(format: Bundle.localizedString(forKey: "gamepage_state_save_failed"), showName)
                let msg = EmuInGameMessage(message: str, title: nil, type: .error, duration: 3.5, priority: 0)
                self?.inGameInfoView.showMessage(msg)
            }
            RetroArchX.shared().resume()
        }
        alert.addAction(okAction)

        RetroArchX.shared().pause()
        alert.view.tintColor = .label
        present(alert, animated: true)
    }

    @objc
    private func loadStateAction() {
        guard RetroArchX.shared().isCurrentCoreSupportsSavestate() else {
            return
        }

        guard
            let currentCoreItem = RetroArchX.shared().currentCoreItem,
            let romPath = RetroArchX.shared().getCurrentRomPath(),
            let sha256 = FileManager.default.sha256ForFile(atPath: romPath) else {
            return
        }

        let items = RetroRomFileManager.shared.getGameStateItems(coreId: currentCoreItem.coreId, sha256: sha256) ?? []
        let controller = GameStateListViewController(gameStateItems: items, showClose: true)
        let naviController = UINavigationController(rootViewController: controller)
        present(naviController, animated: true)
    }

    @objc
    private func restartAction() {
        RetroArchX.shared().restart()
    }

    @objc
    private func coreInfoAction() {
        let coreInfoViewController = RetroRomCoreInfoViewController(coreInfoItem: core, showCloseButton: true, interactive: false)
        let navController = UINavigationController(rootViewController: coreInfoViewController)
        present(navController, animated: true)
    }

    @objc
    private func closeAction() {
        Self.instance = nil

        if AppSettings.shared.autoSaveLoadState {
            let name = getAutoSaveStateName()
            _ = RetroRomFileManager.shared.saveState(rawName: name, showName: nil, sha256: romItem?.sha256, romKey: romItem?.key, autoSave: true)
            romItem?.pulseImage = !(romItem?.pulseImage ?? false)
        }

        RetroArchX.shared().close()
        romUrl?.stopAccessingSecurityScopedResource()
        dismiss(animated: true)
    }
}
