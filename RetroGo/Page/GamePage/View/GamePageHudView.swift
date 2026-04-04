//
//  GamePageHudView.swift
//  RetroGo
//
//  Created by haharsw on 2026/3/14.
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

final class GamePageHudView: UIView {
    private weak var holder: GamePageViewController?

    let closeButton = UIButton(type: .system)
    let settingButton = UIButton(type: .system)
    let infoButton = UIButton(type: .system)
    let restartButton = UIButton(type: .system)
    let snapButton = UIButton(type: .system)
    private(set) lazy var loadStateButton = UIButton(type: .system)
    private(set) lazy var saveStateButton = UIButton(type: .system)

    let pauseResumeButton = UIButton(type: .system)
    let muteButton = UIButton(type: .system)

    private var isGamePaused = false
    private var isGameMuted = false
    private lazy var lastTrailing: ConstraintItem = safeAreaLayoutGuide.snp.trailing

    init(holder: GamePageViewController) {
        self.holder = holder
        super.init(frame: .zero)

        configUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configLoadSaveStateButons() {
        if(RetroArchX.shared().isCurrentCoreSupportsSavestate()) {
            let loadImage  = UIImage(systemName: "arrowshape.up.circle")
            loadStateButton.tintColor = .label
            loadStateButton.setImage(loadImage, for: .normal)
            loadStateButton.addTarget(self, action: #selector(loadStateAction), for: .touchUpInside)
            loadStateButton.sizeToFit()
            addSubview(loadStateButton)
            loadStateButton.snp.makeConstraints { make in
                make.trailing.equalTo(lastTrailing).offset(-20)
                make.centerY.equalToSuperview()
                make.size.equalTo(loadStateButton.size)
            }
            lastTrailing = loadStateButton.snp.leading

            let saveImage  = UIImage(systemName: "arrowshape.down.circle")
            saveStateButton.tintColor = .label
            saveStateButton.setImage(saveImage, for: .normal)
            saveStateButton.addTarget(self, action: #selector(saveStateAction), for: .touchUpInside)
            saveStateButton.sizeToFit()
            addSubview(saveStateButton)
            saveStateButton.snp.makeConstraints { make in
                make.trailing.equalTo(lastTrailing).offset(-20)
                make.centerY.equalToSuperview()
                make.size.equalTo(saveStateButton.size)
            }
            lastTrailing = saveStateButton.snp.leading
        }
    }
}

extension GamePageHudView {
    private func configUI() {
        let closeImage  = UIImage(systemName: "xmark.circle")
        closeButton.tintColor = UIColor.label
        closeButton.setImage(closeImage, for: .normal)
        closeButton.addTarget(self, action: #selector(closeAction), for: .touchUpInside)
        closeButton.sizeToFit()
        addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(closeButton.size)
        }

        let settingImage = UIImage(systemName: "gear.circle")
        settingButton.setImage(settingImage, for: .normal)
        settingButton.tintColor = .label
        settingButton.addTarget(self, action: #selector(settingAction), for: .touchUpInside)
        settingButton.sizeToFit()
        addSubview(settingButton)
        settingButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(settingButton.size)
        }
        lastTrailing = settingButton.snp.leading

        let infoImage  = UIImage(systemName: "cpu")
        infoButton.tintColor = .label
        infoButton.setImage(infoImage, for: .normal)
        infoButton.addTarget(self, action: #selector(coreInfoAction), for: .touchUpInside)
        infoButton.sizeToFit()
        addSubview(infoButton)
        infoButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(infoButton.size)
        }
        lastTrailing = infoButton.snp.leading

        let restartImage  = UIImage(systemName: "arrow.clockwise.circle")
        restartButton.tintColor = .label
        restartButton.setImage(restartImage, for: .normal)
        restartButton.addTarget(self, action: #selector(restartAction), for: .touchUpInside)
        restartButton.sizeToFit()
        addSubview(restartButton)
        restartButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(restartButton.size)
        }
        lastTrailing = restartButton.snp.leading

        let snapImage  = UIImage(systemName: "photo.circle")
        snapButton.tintColor = .label
        snapButton.setImage(snapImage, for: .normal)
        snapButton.addTarget(self, action: #selector(snapAction), for: .touchUpInside)
        snapButton.sizeToFit()
        addSubview(snapButton)
        snapButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(snapButton.size)
        }
        lastTrailing = snapButton.snp.leading

        pauseResumeButton.tintColor = .label
        pauseResumeButton.addTarget(self, action: #selector(pauseResumeAction), for: .touchUpInside)
        updatePauseResumeButtonAppearance()
        pauseResumeButton.sizeToFit()
        addSubview(pauseResumeButton)
        pauseResumeButton.snp.makeConstraints { make in
            make.trailing.equalTo(lastTrailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(pauseResumeButton.size)
        }
        lastTrailing = pauseResumeButton.snp.leading

//        muteButton.tintColor = .label
//        muteButton.addTarget(self, action: #selector(muteAction), for: .touchUpInside)
//        updateMuteButtonAppearance()
//        muteButton.sizeToFit()
//        addSubview(muteButton)
//        muteButton.snp.makeConstraints { make in
//            make.trailing.equalTo(lastTrailing).offset(-20)
//            make.centerY.equalToSuperview()
//            make.size.equalTo(muteButton.size)
//        }
//        lastTrailing = muteButton.snp.leading
    }

    private func updatePauseResumeButtonAppearance() {
        let imageName = isGamePaused ? "play.circle" : "pause.circle"
        pauseResumeButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    private func updateMuteButtonAppearance() {
        let imageName = isGameMuted ? "speaker.slash.circle" : "speaker.wave.2.circle"
        muteButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
}

extension GamePageHudView {
    @objc
    private func saveStateAction() {
        Vibration.selection.vibrate()
        
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
        let cancelAction = UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel) { [weak self] _ in
            RetroArchX.shared().resume()
            self?.isGamePaused = false
            self?.updatePauseResumeButtonAppearance()
        }
        alert.addAction(cancelAction)
        let okAction = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            let rawName = DateFormatter.yyyyMMddHHmmss().string(from: now)
            let showName = alert.textFields?.first?.text ?? ""
            let ret = RetroRomFileManager.shared.saveState(rawName: rawName, showName: showName, sha256: holder?.romItem?.sha256, romKey: holder?.romItem?.key, autoSave: false)
            if ret {
                let str = String(format: Bundle.localizedString(forKey: "gamepage_state_saved"), showName)
                let msg = EmuInGameMessage(message: str, title: nil, type: .info, duration: 3.5, priority: 0)
                holder?.inGameInfoView.showMessage(msg)
            } else {
                let str = String(format: Bundle.localizedString(forKey: "gamepage_state_save_failed"), showName)
                let msg = EmuInGameMessage(message: str, title: nil, type: .error, duration: 3.5, priority: 0)
                holder?.inGameInfoView.showMessage(msg)
            }
            RetroArchX.shared().resume()
            self.isGamePaused = false
            self.updatePauseResumeButtonAppearance()
        }
        alert.addAction(okAction)

        RetroArchX.shared().pause()
        isGamePaused = true
        updatePauseResumeButtonAppearance()
        alert.view.tintColor = .label
        holder?.present(alert, animated: true)
    }

    @objc
    private func loadStateAction() {
        Vibration.selection.vibrate()

        guard RetroArchX.shared().isCurrentCoreSupportsSavestate() else {
            return
        }

        guard
            let currentCoreItem = RetroArchX.shared().currentCoreItem,
            let romPath = RetroArchX.shared().getCurrentRomPath(),
            let sha256 = FileManager.default.sha256ForFile(atPath: romPath) else {
            return
        }

        let items = Retro​Rom​Persistence.shared.getGameStateItems(coreId: currentCoreItem.coreId, sha256: sha256) ?? []
        let controller = GameStateListViewController(gameStateItems: items, showClose: true)
        let naviController = UINavigationController(rootViewController: controller)
        holder?.present(naviController, animated: true)
    }

    @objc
    private func snapAction() {
        Vibration.selection.vibrate()

        let nowString = DateFormatter.yyyyMMddHHmmss().string(from: Date())
        let pngName  = "snap-\(nowString).png"
        let snapPath = AppConfig.shared.snapshotFolder + pngName
        RetroArchX.shared().saveScreenshot(to: snapPath)
    }

    @objc
    private func pauseResumeAction() {
        Vibration.selection.vibrate()

        let success: Bool
        if isGamePaused {
            success = RetroArchX.shared().resume()
            if success {
                isGamePaused = false
            }
        } else {
            success = RetroArchX.shared().pause()
            if success {
                isGamePaused = true
            }
        }

        if success {
            updatePauseResumeButtonAppearance()
        }
    }

    @objc
    private func muteAction() {
        Vibration.selection.vibrate()

        let nextMuted = !isGameMuted
        if RetroArchX.shared().mute(nextMuted) {
            isGameMuted = nextMuted
            updateMuteButtonAppearance()
        }
    }

    @objc
    private func restartAction() {
        Vibration.selection.vibrate()

        RetroArchX.shared().restart()
    }

    @objc
    private func coreInfoAction() {
        Vibration.selection.vibrate()

        if let coreInfoItem = RetroArchX.shared().currentCoreItem {
            let controller = RetroRomCoreInfoViewController(coreInfoItem: coreInfoItem, showCloseButton: true, interactive: false)
            let navController = UINavigationController(rootViewController: controller)
            holder?.present(navController, animated: true)
        }
    }

    @objc
    private func settingAction() {
        Vibration.selection.vibrate()

        let controller = GameSettingViewController()
        let naviController = UINavigationController(rootViewController: controller)
        holder?.present(naviController, animated: true)
    }

    @objc
    private func closeAction() {
        Vibration.selection.vibrate()

        if AppSettings.shared.autoSaveLoadState {
            let name = RetroRomGameStateItem.getAutoSaveStateName(romItem: holder?.romItem)
            _ = RetroRomFileManager.shared.saveState(rawName: name, showName: nil, sha256: holder?.romItem?.sha256, romKey: holder?.romItem?.key, autoSave: true)
            holder?.romItem?.pulseImage = !(holder?.romItem?.pulseImage ?? false)
        }

        RetroArchX.shared().close()
        holder?.romUrl?.stopAccessingSecurityScopedResource()
        holder?.dismiss(animated: true)
    }
}
