//
//  GameOverlayLayoutEditController.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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
import ObjcHelper
import os

/// Runs one editing session of a control layout on the game page: the game is
/// paused and its toolbar hidden, the overlay shows the editor scene, and a
/// floating panel holds the editing tools.
///
/// A new layout is named and saved through `GameOverlayLayoutSaveViewController`
/// when the user taps Done; an existing one is saved in place. Cancel discards
/// the edits.
@MainActor
final class GameOverlayLayoutEditController {
    enum Target {
        /// A new layout starting from `from` (the layout the game uses now).
        case create(from: GameOverlayLayoutData)
        case edit(GameOverlayLayoutItem)
    }

    private weak var gamePage: GamePageViewController?
    private let overlayView: GamePageOverlayView
    private var target: Target?
    private var editorScene: GameOverlayLayoutEditorScene?
    private var panel: GameOverlayLayoutEditPanel?
    private var pauseLease: GamePauseCoordinator.Lease?
    private var completion: ((GameOverlayLayoutItem?) -> Void)?

    var isEditing: Bool { editorScene != nil }

    private var session: GameOverlayLayoutSession { overlayView.layoutSession }

    init(gamePage: GamePageViewController, overlayView: GamePageOverlayView) {
        self.gamePage = gamePage
        self.overlayView = overlayView
    }

    /// Ends with the saved layout, or nil when cancelled. False when the core has no controls to edit.
    @discardableResult
    func begin(_ target: Target, completion: ((GameOverlayLayoutItem?) -> Void)? = nil) -> Bool {
        let data: GameOverlayLayoutData
        switch target {
        case .create(let base): data = base
        case .edit(let item): data = item.data
        }
        guard !isEditing, let gamePage, let editor = overlayView.beginEditing(layoutData: data) else { return false }
        self.target = target
        self.completion = completion
        editorScene = editor
        pauseLease = GamePauseCoordinator.shared.acquire(reason: "overlay-layout-edit")
        gamePage.toolbarView.isHidden = true
        // The screen stays in the orientation being edited until the panel switches it.
        gamePage.setLayoutEditingOrientation(editor.isPortrait ? .portrait : .landscape)

        let panel = GameOverlayLayoutEditPanel()
        bind(panel, to: editor)
        gamePage.view.addSubview(panel)
        self.panel = panel
        refreshPanel()
        sizePanel()
        // Start at the top, where the hidden toolbar was and no control sits.
        let area = gamePage.view.bounds.inset(by: gamePage.view.safeAreaInsets)
        panel.center = CGPoint(x: area.midX, y: area.minY + panel.bounds.height * 0.5 + 8)

        editor.onChange = { [weak self] in self?.refreshPanel() }
        RetroGoLogger.game.info("Started editing an overlay layout of \(self.session.overlayName, privacy: .public)")
        return true
    }

    /// Keeps the panel on screen after a rotation.
    func viewDidLayout() {
        guard let panel, let view = gamePage?.view else { return }
        sizePanel()
        panel.keepInside(view.bounds.inset(by: view.safeAreaInsets))
    }

    private func bind(_ panel: GameOverlayLayoutEditPanel, to editor: GameOverlayLayoutEditorScene) {
        panel.onModeChanged = { [weak editor] mode in editor?.setSelectionMode(mode) }
        panel.onArcadeLayoutChanged = { [weak editor] fourButtons in editor?.setFourButtonLayout(fourButtons) }
        panel.onOrientationChanged = { [weak self] portrait in
            self?.gamePage?.setLayoutEditingOrientation(portrait ? .portrait : .landscape)
        }
        panel.onUndo = { [weak editor] in editor?.undo() }
        panel.onReset = { [weak editor] in editor?.resetCurrentOrientation() }
        panel.onCancel = { [weak self] in self?.finish(saved: nil) }
        panel.onDone = { [weak self] in self?.done() }
        panel.onScaleEditing = { [weak editor] event in
            switch event {
            case .began: editor?.beginContinuousEdit()
            case .changed(let value): editor?.setSelectionScale(value)
            case .ended: editor?.endContinuousEdit()
            }
        }
        panel.onOpacityEditing = { [weak editor] event in
            switch event {
            case .began: editor?.beginContinuousEdit()
            case .changed(let value): editor?.setOpacity(value)
            case .ended: editor?.endContinuousEdit()
            }
        }
        panel.onToggleSelectionHidden = { [weak editor] in editor?.toggleSelectionHidden() }
        panel.onComboToggled = { [weak editor] id, shown in editor?.setHidden(!shown, element: id) }
        panel.onAddCombo = { [weak self] in self?.presentComboEditor(comboId: nil) }
        panel.onEditCombo = { [weak self] id in self?.presentComboEditor(comboId: id) }
        panel.onDeleteCombo = { [weak editor] id in editor?.removeCombo(id: id) }
        panel.onComboTurboChanged = { [weak editor] id, turbo in editor?.setComboTurbo(turbo, combo: id) }
        panel.onSizeChanged = { [weak self] in self?.viewDidLayout() }
    }

    private func refreshPanel() {
        guard let editor = editorScene, let panel else { return }
        panel.update(GameOverlayLayoutEditPanel.State(
            isPortrait: editor.isPortrait,
            fourButtonLayout: editor.hasArcadeLayoutSwitch ? editor.usesFourButtonLayout : nil,
            mode: editor.selectionMode,
            canUndo: editor.canUndo,
            canReset: editor.editedOrientation != nil,
            selectionTitle: editor.selectionTitle,
            selectionComboTitle: editor.selectionComboTitle,
            selectionScale: editor.selectionScale,
            opacity: editor.opacity,
            selectionHidden: editor.selectionHidden,
            combos: editor.comboElements.map {
                GameOverlayLayoutEditPanel.Combo(id: $0.id, title: $0.comboTitle ?? GameOverlayComboTitle(parts: [.text($0.buttonTitle)]),
                                                 shown: !editor.isHiddenInLayout($0),
                                                 isTurbo: $0.isTurbo, isUserCombo: editor.userCombo(id: $0.id) != nil)
            },
            selectedUserComboId: editor.selectedUserCombo?.id,
            note: sharedNote
        ))
    }

    /// Makes a combo (nil) or edits one of the user's in a sheet over the paused game.
    private func presentComboEditor(comboId: String?) {
        guard let gamePage, let editor = editorScene, gamePage.presentedViewController == nil else { return }
        let combo = comboId.flatMap(editor.userCombo(id:))
        if comboId != nil, combo == nil { return }
        let controller = GameOverlayComboEditViewController(keys: editor.comboKeys, combo: combo) { [weak editor] binds in
            guard let editor, let existing = editor.combo(binds: binds, excluding: combo?.id) else { return nil }
            return .init(title: existing.comboTitle?.plainText ?? existing.buttonTitle, isTurbo: existing.isTurbo,
                         isShown: editor.isShown(existing))
        }
        controller.onSave = { [weak editor] in editor?.saveCombo($0) }
        if let combo {
            controller.onDelete = { [weak editor] in editor?.removeCombo(id: combo.id) }
        }
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        gamePage.present(navigation, animated: true)
    }

    /// Editing a layout other games use changes it for them too.
    private var sharedNote: String? {
        guard case .edit(let item) = target else { return nil }
        let usage = session.usage(of: item.id)
        let ownGame = session.gameChoice() == .custom(item.id) ? 1 : 0
        guard usage.platform || usage.games - ownGame > 0 else { return nil }
        return Bundle.localizedString(forKey: "overlay_layout_editing_shared")
    }

    /// The panel is placed by frame so it can be dragged freely; its height follows its content.
    private func sizePanel() {
        guard let panel, let view = gamePage?.view else { return }
        let area = view.bounds.inset(by: view.safeAreaInsets)
        let width = min(Self.panelMaxWidth, area.width - 32)
        let height = panel.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let center = panel.center
        panel.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        panel.center = center
    }

    private static let panelMaxWidth: CGFloat = 380

    // MARK: Saving

    private func done() {
        guard let editor = editorScene, let target else { return }
        switch target {
        case .edit(let item):
            guard session.updateLayout(id: item.id, data: editor.layoutData) else {
                showSaveFailed()
                return
            }
            RetroGoLogger.game.info("Saved overlay layout \(item.id, privacy: .public) of \(self.session.overlayName, privacy: .public)")
            finish(saved: session.layout(id: item.id))
        case .create:
            presentSaveSheet(data: editor.layoutData)
        }
    }

    private func presentSaveSheet(data: GameOverlayLayoutData) {
        guard let gamePage else { return }
        let session = self.session
        var saved: GameOverlayLayoutItem?
        let controller = GameOverlayLayoutSaveViewController(session: session, showsGameOption: session.game != nil) { result in
            guard let item = session.createLayout(name: result.name, data: data) else { return false }
            if result.useForGame || result.applyToPlatform {
                session.choose(layoutId: item.id, applyToPlatform: result.applyToPlatform)
            }
            RetroGoLogger.game.info("Saved new overlay layout \(item.id, privacy: .public) of \(session.overlayName, privacy: .public)")
            saved = item
            return true
        }
        // Dismissed without saving keeps the editor open; once saved, the editor closes.
        controller.onDismiss = { [weak self] in
            guard let saved else { return }
            self?.finish(saved: saved)
        }
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        gamePage.present(navigation, animated: true)
    }

    private func showSaveFailed() {
        let alert = UIAlertController(title: nil, message: Bundle.localizedString(forKey: "overlay_layout_save_failed"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        gamePage?.present(alert, animated: true)
    }

    private func finish(saved: GameOverlayLayoutItem?) {
        guard editorScene != nil else { return }
        editorScene = nil
        target = nil

        panel?.removeFromSuperview()
        panel = nil
        // Show what the game resolves to now: the saved layout if it was chosen, else the one it had.
        overlayView.endEditing(showing: nil)
        gamePage?.toolbarView.isHidden = false
        gamePage?.setLayoutEditingOrientation(nil)
        pauseLease?.release()
        pauseLease = nil

        let completion = self.completion
        self.completion = nil
        completion?(saved)
    }
}
