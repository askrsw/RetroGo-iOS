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

final class GamePageViewController: RAGameViewController {
    static private(set) weak var instance: GamePageViewController?

    let inGameInfoView = GamePageInGameInfoView(frame: .zero)
    private(set) lazy var myToolbarView = GamePageToolbarView(holder: self)
    private(set) lazy var myOverlayView = GamePageOverlayView(coreInfoItem: core)

    /// Runtime-only landscape lock — intentionally NOT persisted. Entering a
    /// game should match the device's current orientation (no jarring auto-
    /// rotate with no user action); the user taps once to lock landscape.
    /// Resets to free rotation every game session.
    private(set) var isLandscapeLocked = false

    let romItem: RetroRomFileItem?
    let romUrl: URL?
    let startTime: Date
    let configSession: GameConfigSession
    /// The single cheat session for this game run (parallels `configSession`).
    /// nil when launched without a `RetroRomFileItem` (the document-browser path),
    /// since cheats are keyed by the rom item — cheats are unavailable then.
    let cheatSession: GameCheatSession?

    private(set) var startDate: Date?

    private var myLoadingView: GamePageLoadingView?
    private var loaded = false

    init(romUrl: URL?, core: EmuCoreInfoItem) {
        self.romItem   = nil
        self.romUrl    = romUrl
        self.startTime = Date()
        self.configSession = GameConfigSession(scope: .core, core: core, game: nil)
        self.cheatSession = nil
        super.init(core: core)
        Self.instance = self

        _ = self.romUrl?.startAccessingSecurityScopedResource()

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(showInGameMessageNotification(_:)), name: .showInGameMessage, object: nil)
    }

    init(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        let configSession = GameConfigSession(scope: .game, core: core, game: romItem)
        self.romItem   = romItem
        self.romUrl    = URL(fileURLWithPath: romItem.entryPath!)
        self.startTime = Date()
        self.configSession = configSession
        self.cheatSession = GameCheatSession(
            game: romItem,
            core: core,
            autoEnableCheatsOnLaunch: configSession.getAutoEnableCheats()
        )
        super.init(core: core)
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

    override var toolbarView: UIView {
        myToolbarView
    }

    override var overlayView: UIView {
        myOverlayView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configSession.configRetroArch()
        
        RetroArchX.shared().start(romUrl?.path(percentEncoded: false), core: core) { [unowned self] success in
            loaded = true
            myLoadingView?.uninstall()
            myLoadingView = nil

            myToolbarView.refreshActionAvailability()

            startDate = Date()

            if AppSettings.shared.autoSaveLoadState, let coreId = RetroArchX.shared().currentCoreItem?.coreId {
                let name = RetroRomGameStateItem.getAutoSaveStateName(romItem: romItem)
                let stateFolder = AppConfig.shared.statesFolder + coreId
                let autoPath = "\(stateFolder)/\(name).state"
                RetroArchX.shared().loadState(from: autoPath)
            }

            // Rebuild the engine cheat snapshot after the core starts. This must
            // load system-template states too; otherwise the toolbar badge and
            // enabled template cheats only become correct after opening the cheat page.
            cheatSession?.reloadTemplateItems {}

            if core.coreId == "dosbox-pure" {
                self.useRetroArchOverlay = true
                self.useSpriteKitOverlay = false
            } else {
                let useRetroArchOverlay = self.useRetroArchOverlay
                let useSpriteKitOverlay = self.useSpriteKitOverlay
                self.useRetroArchOverlay = useRetroArchOverlay
                self.useSpriteKitOverlay = useSpriteKitOverlay
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

        // Apply persisted orientation lock on entry.
        applyOrientationLock()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Restore free rotation for all other pages.
        AppDelegate.setOrientationLock(.allButUpsideDown)
    }

    /// Applies the current (runtime) landscape-lock state to the app-wide mask
    /// and this VC's `supportedInterfaceOrientations`.
    func applyOrientationLock() {
        let mask: UIInterfaceOrientationMask = isLandscapeLocked ? .landscape : .allButUpsideDown
        AppDelegate.setOrientationLock(mask)
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// Toggles the runtime landscape lock (called by the toolbar button).
    func toggleLandscapeLock() {
        isLandscapeLocked.toggle()
        applyOrientationLock()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        isLandscapeLocked ? .landscape : .allButUpsideDown
    }

    override func showInGameMessage(_ message: EmuInGameMessage) {
        if Thread.isMainThread {
            inGameInfoView.showMessage(message)
        } else {
            DispatchQueue.main.async { [unowned self] in
                inGameInfoView.showMessage(message)
            }
        }
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

private enum GameLaunchBackgroundPreparation {
    static let queue = DispatchQueue(label: "com.retrogo.game-launch.preparation", qos: .utility)
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

        // CRC32 + cheat-template binding are launch-adjacent conveniences, not
        // launch requirements. Keep them on a serial utility queue so playing a
        // game stays instant even for large legacy ROMs.
        GameLaunchBackgroundPreparation.queue.async {
            do {
                try romItem.ensureCRC32()
                try GameCheatTemplateAutoBinder.shared.prepareBindingIfNeeded(game: romItem, core: core)
            } catch {
                print("Failed to prepare launch metadata for ROM: \(romItem.itemName), error: \(error)")
            }
        }
    }
}
