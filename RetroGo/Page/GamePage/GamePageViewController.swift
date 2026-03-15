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

    let inGameInfoView = InGameInfoView(frame: .zero)
    private(set) lazy var myHudView = GamePageHudView(holder: self)

    let romItem: RetroRomFileItem?
    let romUrl: URL?
    let core: EmuCoreInfoItem
    let startTime: Date

    private(set) var startDate: Date?

    private var myLoadingView: GamePageLoadingView?
    private var loaded = false

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

    override var hudView: UIView {
        myHudView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        RetroArchX.shared().start(romUrl?.path(percentEncoded: false), core: core) { [unowned self] success in
            loaded = true
            myLoadingView?.uninstall()
            myLoadingView = nil

            myHudView.configLoadSaveStateButons()

            startDate = Date()

            if AppSettings.shared.autoSaveLoadState, let coreId = RetroArchX.shared().currentCoreItem?.coreId {
                let name = RetroRomGameStateItem.getAutoSaveStateName(romItem: romItem)
                let stateFolder = AppConfig.shared.statesFolder + coreId
                let autoPath = "\(stateFolder)/\(name).state"
                RetroArchX.shared().loadState(from: autoPath)
            }
        }

        view.addSubview(inGameInfoView)
        inGameInfoView.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading).offset(20)
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing).offset(-20)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-10)
            make.height.greaterThanOrEqualTo(25)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !loaded {
            myLoadingView = GamePageLoadingView(frame: .zero)
            myLoadingView?.install()
        }
    }

    override func showInGameMessage(_ message: EmuInGameMessage) {
        inGameInfoView.showMessage(message)
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
                let name = RetroRomGameStateItem.getAutoSaveStateName(romItem: romItem)
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
}

extension RetroArchX {
    static func playGame(romUrl: URL?, core: EmuCoreInfoItem) {
        guard let currentViewController = UIViewController.currentActive() else {
            return
        }
        let controller = GamePageViewController(romUrl: romUrl, core: core)
        controller.modalPresentationStyle = .fullScreen
        currentViewController.present(controller, animated: true)
    }

    static func playGame(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        guard let currentViewController = UIViewController.currentActive() else {
            return
        }
        let controller = GamePageViewController(romItem: romItem, core: core)
        controller.modalPresentationStyle = .fullScreen
        currentViewController.present(controller, animated: true)
    }
}
