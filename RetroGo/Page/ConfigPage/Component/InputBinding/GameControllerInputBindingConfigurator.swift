//
//  GameControllerInputBindingConfigurator.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/29.
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
import SpriteKit
import ObjcHelper
import RACoordinator

final class GameControllerInputBindingConfigurator: UIViewController {
    private(set) lazy var skView = configSKView()
    private(set) lazy var overlayView = makeOverlayScene()
    private var resetBarButton: UIBarButtonItem?

    private var didPersistOnExit = false

    let session: GameConfigSession?
    let playerIndex: Int

    init(session: GameConfigSession?, playerIndex: Int) {
        self.session = session
        self.playerIndex = playerIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var isReadOnly: Bool {
        guard let coreId = session?.core?.coreId.lowercased() else { return false }
        return coreId == "mupen64plus-next"     // N64
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "configpage_button_mapping")

        _ = overlayView
        _ = skView

        let resetBarButton = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(resetButtonConfig(_:)))
        navigationItem.rightBarButtonItem = resetBarButton
        self.resetBarButton = resetBarButton
        overlayView.onDirtyChanged = { [weak self] _ in
            self?.updateResetButtonEnabled()
        }
        overlayView.shouldAllowBindingChange = { [weak self] in
            guard let self, self.isBindingInteractionActive else {
                return false
            }

            return AppStoreProFeatureGate.shared.requirePro(
                feature: .controllerMapping,
                presentation: .alert,
                from: self
            )
        }
        updateResetButtonEnabled()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        overlayView.updateLayout(for: skView.bounds.size)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // 只在真正离开本页面时保存一次
        guard (isMovingFromParent || isBeingDismissed), !didPersistOnExit else { return }
        didPersistOnExit = true
        persistBindingProfileIfNeeded()
    }
}

extension GameControllerInputBindingConfigurator {
    @objc
    private func resetButtonConfig(_ sender: UIBarButtonItem) {
        Vibration.selection.vibrate()
        guard !isReadOnly else { return }
        overlayView.resetToDefault()
        updateResetButtonEnabled()
    }

    private func updateResetButtonEnabled() {
        let hasNonDefault = RAInputActionManager.shared().hasNonDefaultBindings(forPort: Int32(playerIndex), useLock: true)
        resetBarButton?.isEnabled = !isReadOnly && hasNonDefault
    }

    private var isBindingInteractionActive: Bool {
        guard isViewLoaded, view.window != nil else { return false }
        guard presentedViewController == nil else { return false }

        if let navigationController {
            guard navigationController.visibleViewController === self else { return false }
            guard navigationController.presentedViewController == nil else { return false }
        }

        return UIViewController.currentActive() === self
    }

    private func persistBindingProfileIfNeeded() {
        guard let session else { return }
        guard !isReadOnly else { return }
        guard overlayView.isDirty else { return }

        let profile = overlayView.exportBindingProfileForPersistence()
    #if DEBUG
        if let profile {
            print(profile)
        } else {
            print("default binding, profile is nil")
        }
    #endif // DEBUG
        _ = session.saveInputBindingProfile(profile) // profile 为 nil 时会写 NULL
    }

    private func configSKView() -> SKView {
        let skView = SKView(frame: .zero)
        skView.backgroundColor = .clear
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.isMultipleTouchEnabled = true

        view.addSubview(skView)
        skView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            skView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            skView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            skView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            skView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        skView.presentScene(overlayView)
        return skView
    }

    private func makeOverlayScene() -> GameConfigBindingOverlayScene {
        let config = GamePageOverlayConfig.loadOverlayConfig(session?.core?.overlayName)
        let scene = GameConfigBindingOverlayScene(
            size: .zero,
            config: config,
            playerIndex: playerIndex,
            isReadOnly: isReadOnly
        )
        return scene
    }
}
