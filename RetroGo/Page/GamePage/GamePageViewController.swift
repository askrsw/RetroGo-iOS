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
    private(set) lazy var myOverlayView = GamePageOverlayView(coreInfoItem: core, game: romItem)
    private(set) lazy var overlayLayoutEditController = GameOverlayLayoutEditController(gamePage: self, overlayView: myOverlayView)

    /// Runtime-only landscape lock — intentionally NOT persisted. Entering a
    /// game should match the device's current orientation (no jarring auto-
    /// rotate with no user action); the user taps once to lock landscape.
    /// Resets to free rotation every game session.
    private(set) var isLandscapeLocked = false
    /// The orientation the control layout editor shows; overrides the landscape lock while it runs.
    private(set) var layoutEditingOrientation: UIInterfaceOrientationMask?

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
    private var closeRequested = false
    private var closeFinished = false
    private var pauseSessionID: UUID?

    var isGameReady: Bool { loaded && !closeRequested }

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
        NotificationCenter.default.addObserver(self, selector: #selector(overlayHapticLevelChanged), name: .overlayHapticLevelChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(gameRumbleEnabledChanged), name: .gameRumbleEnabledChanged, object: nil)
    }

    init(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        let configSession = GameConfigSession(scope: .game, core: core, game: romItem)
        self.romItem   = romItem
        let entryPath = romItem.entryPath!
        if RetroRomMdsCueSheet.isNeeded(entryPath: entryPath, core: core),
           let cuePath = RetroRomMdsCueSheet.make(mdsPath: entryPath, key: romItem.key) {
            self.romUrl = URL(fileURLWithPath: cuePath)
        } else {
            self.romUrl = URL(fileURLWithPath: entryPath)
        }
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
        NotificationCenter.default.addObserver(self, selector: #selector(overlayHapticLevelChanged), name: .overlayHapticLevelChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(gameRumbleEnabledChanged), name: .gameRumbleEnabledChanged, object: nil)

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

        myOverlayView.isUserInteractionEnabled = false
        AppStoreProFeatureGate.resetFastForwardNotice()
        configSession.configRetroArch()
        GameHapticEngine.shared.start(level: configSession.getOverlayHapticLevel())

        // Keep the render owner alive until loading (and any cancelled-load
        // teardown) completes. A dismissed page must never leave an orphan core.
        RetroArchX.shared().start(romUrl?.path(percentEncoded: false), core: core) { [self] success in
            guard success, !closeRequested else {
                finishClosing()
                return
            }
            loaded = true
            // RetroArchX delivers completion on the main thread, but its ObjC
            // block type does not express MainActor isolation to Swift.
            pauseSessionID = MainActor.assumeIsolated {
                GamePauseCoordinator.shared.beginSession(
                    applicationIsActive: UIApplication.shared.applicationState == .active
                )
            }
            myOverlayView.isUserInteractionEnabled = true
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
            // A Pro that expired or was refunded keeps only the free number of
            // cheats; someone who never had Pro keeps every cheat switched on before.
            // This completion runs on the main thread, like the UI work above.
            let proLapsed = MainActor.assumeIsolated { AppStorePurchaseManager.shared.isProLapsed }
            cheatSession?.reloadTemplateItems { [weak self] in
                guard proLapsed else { return }
                self?.cheatSession?.limitEnabledCheatsToFreeNumber()
            }
            if proLapsed {
                mameCheatSession?.limitRestorableToFreeNumber()
            }
            mameCheatSession?.gameDidStart()

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
            if myLoadingView == nil, !closeFinished {
                myLoadingView = GamePageLoadingView(frame: .zero)
                if closeRequested {
                    myLoadingView?.messageLabel.text = Bundle.localizedString(forKey: "gamepage_game_closing")
                }
                myLoadingView?.install()
            }
        }

        // Apply persisted orientation lock on entry.
        applyOrientationLock()
    }

    /// Whether this core has on-screen controls whose layout can be edited.
    var canEditOverlayLayout: Bool {
        myOverlayView.overlayScene != nil
    }

    /// Shows this platform's control layouts; editing one returns to the list when done.
    func showOverlayLayoutList() {
        guard !RANetplayCoordinator.shared.isNetplayEnabled, !overlayLayoutEditController.isEditing else { return }
        let list = GameOverlayLayoutListViewController(session: myOverlayView.layoutSession)
        let card = GameOverlayLayoutListCardController(listController: list)
        list.editHandler = { [weak self, weak card] request in
            guard let card else { return }
            // Keeps the game paused from the list closing until the editor takes over.
            let bridge = GamePauseCoordinator.shared.acquire(reason: "overlay-layout-list-to-edit")
            let closing = card.close { [weak self] in
                self?.editOverlayLayout(request)
                bridge?.release()
            }
            if !closing { bridge?.release() }
        }
        present(card, animated: true)
    }

    private func editOverlayLayout(_ request: GameOverlayLayoutListViewController.EditRequest) {
        let target: GameOverlayLayoutEditController.Target
        switch request {
        case .create:
            target = .create
        case .edit(let item):
            target = .edit(item)
        }
        overlayLayoutEditController.begin(target) { [weak self] _ in
            self?.showOverlayLayoutList()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        overlayLayoutEditController.viewDidLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, overlayLayoutEditController.isEditing else { return }
            // The paused game still shows its frame at the old size; let it draw a few at the new one,
            // so the controls are edited against the real picture.
            GamePauseCoordinator.shared.runFramesWhilePaused(keepMuted: myToolbarView.isGameMuted)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if isBeingDismissed || isMovingFromParent {
            closeGame()
        }

        // Restore free rotation for all other pages.
        AppDelegate.setOrientationLock(.allButUpsideDown)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // The game is over once the page is gone, however it was closed.
        if isBeingDismissed || isMovingFromParent {
            GameHapticEngine.shared.stop()
        }
    }

    /// Applies the current (runtime) landscape-lock state to the app-wide mask
    /// and this VC's `supportedInterfaceOrientations`.
    func applyOrientationLock() {
        AppDelegate.setOrientationLock(supportedInterfaceOrientations)
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// Turns the screen for the control layout editor (portrait or landscape); nil gives
    /// rotation back to the device and the landscape lock.
    func setLayoutEditingOrientation(_ mask: UIInterfaceOrientationMask?) {
        guard layoutEditingOrientation != mask else { return }
        layoutEditingOrientation = mask
        applyOrientationLock()
    }

    /// Toggles the runtime landscape lock (called by the toolbar button).
    func toggleLandscapeLock() {
        isLandscapeLocked.toggle()
        applyOrientationLock()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        layoutEditingOrientation ?? (isLandscapeLocked ? .landscape : .allButUpsideDown)
    }

    override func showInGameMessage(_ message: EmuInGameMessage) {
        if Thread.isMainThread {
            inGameInfoView.showMessage(message)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.inGameInfoView.showMessage(message)
            }
        }
    }

    /// A core cannot abort arbitrary ROM loading safely. Keep the page/render
    /// owner until the cancelled load has returned and RetroArch has unloaded it.
    func closeGame() {
        guard !closeRequested else { return }
        let wasReady = loaded
        closeRequested = true
        endPauseSession()
        myToolbarView.closeButton.isEnabled = false
        myToolbarView.isUserInteractionEnabled = false
        myOverlayView.isUserInteractionEnabled = false
        NotificationCenter.default.post(name: .overlayMacroCancel, object: nil)

        if RetroArchX.shared().gameTransitionInProgress {
            myLoadingView?.messageLabel.text = Bundle.localizedString(forKey: "gamepage_game_closing")
            RetroArchX.shared().stop()
            return
        }

        if wasReady {
            // Do not touch cheats or save states during a background core load.
            RetroArchX.shared().clearCheats()
            mameCheatSession?.endSession()
            if AppSettings.shared.autoSaveLoadState {
                let name = RetroRomGameStateItem.getAutoSaveStateName(romItem: romItem)
                _ = RetroRomFileManager.shared.saveState(rawName: name, showName: nil, sha256: romItem?.sha256, romKey: romItem?.key, autoSave: true)
                romItem?.pulseImage = !(romItem?.pulseImage ?? false)
            }
            RetroArchX.shared().stop()
        }
        finishClosing()
    }

    private func finishClosing() {
        guard !closeFinished else { return }
        closeRequested = true
        closeFinished = true
        endPauseSession()
        myLoadingView?.uninstall()
        myLoadingView = nil
        GameHapticEngine.shared.stop()
        if isBeingPresented, let transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.dismiss(animated: true)
            }
            return
        }
        if presentingViewController != nil, !isBeingDismissed {
            dismiss(animated: true)
        }
    }

    private func endPauseSession() {
        guard let id = pauseSessionID else { return }
        pauseSessionID = nil
        GamePauseCoordinator.shared.endSession(id)
    }
}

extension GamePageViewController {
    @objc
    private func appWillResignActive() {
        if Self.instance == self, isGameReady {
            NotificationCenter.default.post(name: .overlayMacroCancel, object: nil)
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

            if let id = pauseSessionID {
                GamePauseCoordinator.shared.setApplicationActive(false, for: id)
            }
        }
    }

    @objc
    private func appWillBecomeActive() {
        if Self.instance == self, isGameReady {
            if self.startDate == nil {
                startDate = Date()
            }

            if let id = pauseSessionID {
                GamePauseCoordinator.shared.setApplicationActive(true, for: id)
            }
        }
    }

    @objc
    private func gameRumbleEnabledChanged() {
        guard Self.instance == self else { return }
        RetroArchX.shared().setPhoneRumbleEnabled(configSession.getGameRumbleEnabled())
    }

    @objc
    private func overlayHapticLevelChanged() {
        guard Self.instance == self else { return }
        let engine = GameHapticEngine.shared
        engine.setLevel(configSession.getOverlayHapticLevel())
        // Lets the player feel the new level from the settings sheet.
        engine.impact()
    }

    @objc
    private func showInGameMessageNotification(_ notif: NSNotification) {
        guard let message = notif.object as? EmuInGameMessage else {
            return
        }
        showInGameMessage(message)
    }
}

/// Serial queue for CRC32 + cheat-template binding work, shared by game launch
/// and the cheat page so two bindings for one game never run at once.
enum GameLaunchBackgroundPreparation {
    static let queue = DispatchQueue(label: "com.retrogo.game-launch.preparation", qos: .utility)
}

extension RetroArchX {
    static func playGame(romUrl: URL?, core: EmuCoreInfoItem) {
        guard !shared().gameTransitionInProgress, GamePageViewController.instance == nil else { return }
        guard MainActor.assumeIsolated({ GameFreePlayQuota.allowLaunch(core: core) }) else { return }
        CoreBiosLaunchCheck.run(core: core) {
            guard !shared().gameTransitionInProgress, GamePageViewController.instance == nil else { return }
            guard let currentViewController = UIViewController.currentActive() else {
                return
            }
            let controller = GamePageViewController(romUrl: romUrl, core: core)
            controller.modalPresentationStyle = .fullScreen
            currentViewController.present(controller, animated: true)
        }
    }

    static func playGame(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        guard !shared().gameTransitionInProgress, GamePageViewController.instance == nil else { return }
        guard MainActor.assumeIsolated({ GameFreePlayQuota.allowLaunch(core: core) }) else { return }
        // Cores that need a BIOS are checked for it, MAME sets for missing files.
        CoreBiosLaunchCheck.run(core: core) {
            MameLaunchCheck.run(game: romItem, core: core) {
                presentGame(romItem: romItem, core: core)
            }
        }
    }

    private static func presentGame(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        guard !shared().gameTransitionInProgress, GamePageViewController.instance == nil else { return }
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
