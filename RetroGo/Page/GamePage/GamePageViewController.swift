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
import os

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
    /// MAME runs its own cheat engine instead of RetroArch's; nil for other cores and
    /// launches without a rom item.
    let mameCheatSession: MameCheatSession?

    private(set) var startDate: Date?

    private var myLoadingView: GamePageLoadingView?
    private var loaded = false

    private var freePlayTimer: Timer?
    private weak var freePlayAlert: UIAlertController?
    private var freePlayWarned = false

    init(romUrl: URL?, core: EmuCoreInfoItem) {
        self.romItem   = nil
        self.romUrl    = romUrl
        self.startTime = Date()
        self.configSession = GameConfigSession(scope: .core, core: core, game: nil)
        self.cheatSession = nil
        self.mameCheatSession = nil
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
        if core.coreId == MameImportScreener.mameCoreId {
            self.cheatSession = nil
            self.mameCheatSession = MameCheatSession(game: romItem, core: core)
        } else {
            self.cheatSession = GameCheatSession(
                game: romItem,
                core: core,
                autoEnableCheatsOnLaunch: configSession.getAutoEnableCheats()
            )
            self.mameCheatSession = nil
        }
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
        freePlayTimer?.invalidate()
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
            mameCheatSession?.gameDidStart()

            if success {
                startFreePlayTimerIfNeeded()
            }

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

// MARK: - Free play allowance

extension GamePageViewController {
    private static let freePlayTick: TimeInterval = 1
    private static let freePlayWarning: TimeInterval = 60

    private func startFreePlayTimerIfNeeded() {
        guard GameFreePlayQuota.access(for: core) == .limited else { return }

        let minutes = Int((GameFreePlayQuota.remainingToday(for: core) / 60).rounded(.up))
        let formatter = Bundle.localizedString(forKey: "progate_free_time_left_format")
        AppToastManager.shared.toast(String(format: formatter, minutes), context: .game, level: .info)

        freePlayTimer?.invalidate()
        freePlayTimer = Timer.scheduledTimer(withTimeInterval: Self.freePlayTick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.freePlayTimerFired()
            }
        }
    }

    private func freePlayTimerFired() {
        guard Self.instance == self, view.window != nil else { return }

        if GameFreePlayQuota.access(for: core) == .unlimited {
            freePlayTimer?.invalidate()
            freePlayTimer = nil
            return
        }

        if GameFreePlayQuota.isExhausted(for: core) {
            // Re-shown whenever nothing else is on screen, e.g. after the purchase
            // page closes without a purchase.
            if presentedViewController == nil {
                presentFreePlayLimitReached()
            }
            return
        }

        // Only count time the game actually runs.
        guard UIApplication.shared.applicationState == .active,
              !GamePauseCoordinator.shared.isHoldingPause else { return }

        GameFreePlayQuota.consume(Self.freePlayTick, for: core)

        let remaining = GameFreePlayQuota.remainingToday(for: core)
        if remaining <= 0 {
            presentFreePlayLimitReached()
        } else if remaining <= Self.freePlayWarning, !freePlayWarned {
            freePlayWarned = true
            AppToastManager.shared.toast(Bundle.localizedString(forKey: "progate_free_time_ending"), context: .game, level: .info)
        }
    }

    private func presentFreePlayLimitReached() {
        guard freePlayAlert == nil, presentedViewController == nil else { return }

        let alert = UIAlertController.gamePausedAlert(
            title: Bundle.localizedString(forKey: "progate_alert_title"),
            message: GameFreePlayQuota.dailyLimitMessage(for: core)
        )
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_unlock_pro"), style: .default) { [weak self, weak alert] _ in
            // Hold the dismissed alert strongly: nothing else keeps it alive past the
            // yield, and its pause lease would leak with it, freezing the game.
            guard let alert else { return }
            Task { @MainActor [weak self] in
                await Task.yield()
                // The purchase page takes its own pause lease before this one goes.
                AppStoreProFeatureGate.shared.presentPurchasePage(from: self)
                alert.releaseGamePauseIfNeeded()
            }
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "progate_quit_game"), style: .cancel) { [weak self, weak alert] _ in
            alert?.releaseGamePauseIfNeeded()
            self?.freePlayTimer?.invalidate()
            self?.freePlayTimer = nil
            self?.myToolbarView.closeAction()
        })

        freePlayAlert = alert
        present(alert, animated: true)
    }
}

/// Serial queue for CRC32 + cheat-template binding work, shared by game launch
/// and the cheat page so two bindings for one game never run at once.
enum GameLaunchBackgroundPreparation {
    static let queue = DispatchQueue(label: "com.retrogo.game-launch.preparation", qos: .utility)
}

extension RetroArchX {
    static func playGame(romUrl: URL?, core: EmuCoreInfoItem) {
        guard MainActor.assumeIsolated({ GameFreePlayQuota.allowLaunch(core: core) }) else { return }
        guard let currentViewController = UIViewController.currentActive() else {
            return
        }
        let controller = GamePageViewController(romUrl: romUrl, core: core)
        controller.modalPresentationStyle = .fullScreen
        currentViewController.present(controller, animated: true)
    }

    static func playGame(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        guard MainActor.assumeIsolated({ GameFreePlayQuota.allowLaunch(core: core) }) else { return }
        // MAME sets are checked for missing files first; other cores launch directly.
        MameLaunchCheck.run(game: romItem, core: core) {
            presentGame(romItem: romItem, core: core)
        }
    }

    private static func presentGame(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
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
                RetroGoLogger.game.error("Failed to prepare launch metadata for \(romItem.itemName): \(String(describing: error))")
            }
        }
    }
}
