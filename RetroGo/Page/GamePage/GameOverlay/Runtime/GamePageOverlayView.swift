//
//  GamePageOverlayView.swift
//  RetroGo
//
//  Created by haharsw on 2026/3/15.
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

import SpriteKit
import ObjcHelper
import RACoordinator

final class GamePageOverlayView: SKView {
    private(set) var coreInfoItem: EmuCoreInfoItem
    private(set) var overlayScene: GamePageOverlayScene?
    /// Shown instead of the game controls while a layout is being edited.
    private(set) var editorScene: GameOverlayLayoutEditorScene?
    /// The game whose layout choice applies; nil uses the platform choice.
    let game: RetroRomFileItem?
    private(set) var layoutSession: GameOverlayLayoutSession

    init(coreInfoItem: EmuCoreInfoItem, game: RetroRomFileItem?) {
        self.coreInfoItem = coreInfoItem
        self.game = game
        self.layoutSession = GameOverlayLayoutSession(core: coreInfoItem, game: game)
        super.init(frame: .zero)
        applyCoreMode(coreInfoItem)

        NotificationCenter.default.addObserver(self, selector: #selector(handleOverlayLayoutChanged(_:)), name: .overlayLayoutChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateCoreInfoItem(_ coreInfoItem: EmuCoreInfoItem) {
        guard self.coreInfoItem.coreId != coreInfoItem.coreId else {
            return
        }
        self.coreInfoItem = coreInfoItem
        self.layoutSession = GameOverlayLayoutSession(core: coreInfoItem, game: game)
        applyCoreMode(coreInfoItem)
    }

    /// Re-reads which custom layout applies and shows it in place.
    func reloadCustomLayout() {
        overlayScene?.applyLayoutData(layoutSession.resolvedLayout().item?.data)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let editorScene {
            if scene !== editorScene {
                presentScene(editorScene)
            }
            editorScene.updateLayout(for: size)
            return
        }
        if scene !== overlayScene {
            presentScene(overlayScene)
        }
        overlayScene?.updateLayout(for: size)
    }

    /// Replaces the game controls with an editor of `layoutData`; nil when this core has no overlay.
    @discardableResult
    func beginEditing(layoutData: GameOverlayLayoutData) -> GameOverlayLayoutEditorScene? {
        guard overlayScene != nil else { return nil }
        let config = GamePageOverlayConfig.loadOverlayConfig(coreInfoItem.overlayName)
        // The editor starts on the arcade 4/6-button layout the game shows.
        let editor = GameOverlayLayoutEditorScene(size: bounds.size, config: config,
                                                  supportsAnalog: overlaySupportsAnalog, layoutData: layoutData,
                                                  fourButtonLayout: overlayScene?.usesFourButtonLayout ?? false)
        editorScene = editor
        presentScene(editor)
        editor.updateLayout(for: bounds.size)
        return editor
    }

    /// Back to the game controls, showing `layoutData` (nil = the layout this game resolves to)
    /// in the arcade 4/6-button layout the editor ended on.
    func endEditing(showing layoutData: GameOverlayLayoutData?) {
        guard let editor = editorScene else { return }
        editorScene = nil
        if let overlayScene, overlayScene.usesFourButtonLayout != editor.usesFourButtonLayout {
            overlayScene.setFourButtonLayout(editor.usesFourButtonLayout)
            layoutSession.saveFourButtonLayout(editor.usesFourButtonLayout)
        }
        presentScene(overlayScene)
        overlayScene?.updateLayout(for: bounds.size)
        if let layoutData {
            overlayScene?.applyLayoutData(layoutData)
        } else {
            reloadCustomLayout()
        }
    }
}

extension GamePageOverlayView {
    /// Whether the on-screen stick sends analog values. A port set to a pad without
    /// sticks (the PS1 standard controller) ignores them, so the stick works as a D-pad.
    private var overlaySupportsAnalog: Bool {
        let portDevice = GamePageViewController.instance?.configSession.getPortDevice()
        return coreInfoItem.supportsAnalog && (portDevice?.analog ?? true)
    }

    @objc private func handleOverlayLayoutChanged(_ notification: Notification) {
        guard notification.object as? String == layoutSession.overlayName, editorScene == nil else { return }
        reloadCustomLayout()
    }

    private func applyCoreMode(_ coreInfoItem: EmuCoreInfoItem) {
        if coreInfoItem.coreId != "dosbox-pure" {
            allowsTransparency = true
            backgroundColor = .clear
            ignoresSiblingOrder = true
            isMultipleTouchEnabled = true
            isUserInteractionEnabled = true
            isHidden = false
            isPaused = false

            let overlayConfig = GamePageOverlayConfig.loadOverlayConfig(coreInfoItem.overlayName)
            let layoutData = layoutSession.resolvedLayout().item?.data
            let scene = GamePageOverlayScene(size: .zero, config: overlayConfig, supportsAnalog: overlaySupportsAnalog,
                                             layoutData: layoutData, fourButtonLayout: layoutSession.savedFourButtonLayout())
            scene.onFourButtonLayoutChanged = { [weak self] fourButtons in
                self?.layoutSession.saveFourButtonLayout(fourButtons)
            }
            overlayScene = scene
        } else {
            isHidden = true
            isUserInteractionEnabled = false
            isPaused = true
            overlayScene = nil
            if scene != nil {
                presentScene(nil)
            }
        }
    }
}
