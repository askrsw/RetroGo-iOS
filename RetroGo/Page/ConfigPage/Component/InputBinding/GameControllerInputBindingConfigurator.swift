//
//  GameControllerInputBindingConfigurator.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/8.
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
import RACoordinator
import ObjcHelper
import os

final class GameControllerInputBindingConfigurator: UITableViewController {
    private let skView = SKView()
    private var overlayView: GameConfigBindingOverlayScene?
    private var resetBarButton: UIBarButtonItem?
    private var selectedLayoutId: String?
    private var didRestoreOnExit = false
    private var canvasHeight: CGFloat = 440
    private var canvasReferenceSize: CGSize = .zero
    private var canvasFittingWidth: CGFloat = 0
    private let manager = RAInputActionManager.shared()

    let session: GameConfigSession?
    let playerIndex: Int
    private let editingLayout: GameOverlayLayoutGameChoice
    private lazy var layouts = GameOverlayLayoutSession(
        templateId: GamePageOverlayConfig.resolvedOverlayName(session?.core?.overlayName),
        game: session?.game, coreId: session?.core?.coreId
    )

    init(session: GameConfigSession?, playerIndex: Int, editingLayout: GameOverlayLayoutGameChoice = .followPlatform) {
        self.session = session
        self.playerIndex = playerIndex
        self.editingLayout = editingLayout
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isReadOnly: Bool { session?.core?.coreId.lowercased() == "mupen64plus-next" }
    private var selectedLayout: GameOverlayLayoutItem? { selectedLayoutId.flatMap { layouts.layout(id: $0) } }
    private var bindings: GameLayoutInputBindingStore {
        .init(templateId: layouts.templateId, idiom: layouts.idiom, layoutId: selectedLayoutId)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.title = Bundle.localizedString(forKey: "configpage_button_mapping")
        let reset = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain,
                                   target: self, action: #selector(resetBindings))
        navigationItem.rightBarButtonItem = reset
        resetBarButton = reset

        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.alwaysBounceVertical = true
        tableView.estimatedRowHeight = 500
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.estimatedSectionFooterHeight = 80
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        skView.backgroundColor = .clear
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.isMultipleTouchEnabled = true
        switch editingLayout {
        case .followPlatform: selectedLayoutId = try? session?.inputBindingLayoutId(for: playerIndex)
        case .builtIn: selectedLayoutId = nil
        case .custom(let id): selectedLayoutId = id
        }
        showSelectedLayout()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section != 0 else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as! RGSectionHeaderView
        header.text = Bundle.localizedString(forKey: "configpage_button_mapping")
        header.topInset = section == 1 ? 22 : 12
        return header
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as! RGSectionFooterView
        footer.text = Bundle.localizedString(forKey: section == 0 ? "configpage_binding_layout_instructions" : "configpage_binding_layout_upgrade")
        return footer
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == 0 ? UITableView.automaticDimension : canvasHeight + 16
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.section == 0 {
            configureLayoutCell(cell)
            return cell
        }
        cell.selectionStyle = .none
        let content = skView
        cell.contentView.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let inset: CGFloat = 8
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -inset)
        ])
        return cell
    }

    private func configureLayoutCell(_ cell: UITableViewCell) {
        var content = cell.defaultContentConfiguration()
        content.text = String(format: Bundle.localizedString(forKey: "configpage_binding_current_layout"),
                              selectedLayout?.name ?? Bundle.localizedString(forKey: "overlay_layout_builtin"))
        content.textProperties.color = .label
        cell.contentConfiguration = content
        cell.accessoryType = .none
        cell.selectionStyle = .none
    }


    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard skView.bounds.width > 0, let overlayView else { return }
        let referenceSize = mappingReferenceSize()
        guard canvasReferenceSize != referenceSize || canvasFittingWidth != skView.bounds.width else { return }
        canvasReferenceSize = referenceSize
        canvasFittingWidth = skView.bounds.width
        let height = overlayView.fitLayout(for: referenceSize, canvasWidth: canvasFittingWidth)
        guard abs(canvasHeight - height) > 0.5 else { return }
        canvasHeight = height
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UIView.performWithoutAnimation {
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
            }
        }
    }

    private func mappingReferenceSize() -> CGSize {
        if let window = view.window, let overlay = GamePageViewController.instance?.myOverlayView,
           overlay.window === window, overlay.bounds.width > 0, overlay.bounds.height > 0 {
            return overlay.bounds.size
        }
        let bounds = view.window?.bounds ?? view.bounds
        let safeArea = view.window?.safeAreaInsets ?? view.safeAreaInsets
        // Match RAGameViewController: safe horizontal edges, below its 44pt toolbar,
        // extending to the bottom of the window (including the home indicator area).
        return CGSize(width: max(1, bounds.width - safeArea.left - safeArea.right),
                      height: max(1, bounds.height - safeArea.top - 44))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if didRestoreOnExit { showSelectedLayout() }
        didRestoreOnExit = false
        overlayView?.resumeBindingCapture()
        if overlayView == nil { showSaveError() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        manager.physicalSourcePressHandler = nil
        let leaving = isMovingFromParent || isBeingDismissed || (navigationController?.isBeingDismissed ?? false)
        if leaving && !didRestoreOnExit {
            didRestoreOnExit = true
            // Editing a different layout is a preview; restore the game's actual chosen scheme.
            (GamePageViewController.instance?.configSession ?? session)?.refreshInputBindingProfile(apply: true)
        }
    }

    private func updateLayoutCell() {
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) {
            configureLayoutCell(cell)
        }
    }


    private func showSelectedLayout() {
        let data = selectedLayout?.data
        if selectedLayoutId != nil && data == nil { selectedLayoutId = nil }
        manager.physicalSourcePressHandler = nil
        overlayView?.onDirtyChanged = nil
        skView.presentScene(nil)
        overlayView = nil
        resetBarButton?.isEnabled = false
        do {
            session?.refreshInputBindingProfile()
            let preview = GameLayoutInputBindingStore.replacingPlayer(in: session?.config.inputBindingProfile,
                with: try bindings.runtimeProfile(data: data), port: playerIndex)
            manager.apply(preview, coreCapabilities: session?.config.coreCaps, useLock: true)
        } catch {
            // Never overwrite an unreadable profile with a blank mapping.
            showSaveError()
            updateLayoutCell()
            return
        }
        let scene = GameConfigBindingOverlayScene(size: skView.bounds.size,
            config: .loadOverlayConfig(layouts.templateId), playerIndex: playerIndex,
            layoutData: data, isReadOnly: isReadOnly)
        overlayView = scene
        canvasReferenceSize = .zero
        scene.shouldAllowBindingChange = { [weak self] in
            guard let self, self.viewIfLoaded?.window != nil, self.presentedViewController == nil,
                  self.navigationController?.visibleViewController === self else { return false }
            return AppStoreProFeatureGate.shared.requirePro(feature: .controllerMapping, presentation: .alert, from: self)
        }
        scene.onDirtyChanged = { [weak self] dirty in
            if dirty { self?.persistChanges() }
        }
        skView.presentScene(scene)
        view.setNeedsLayout()
        updateLayoutCell()
        updateResetButton()
    }

    private func persistChanges() {
        do {
            try bindings.savePlayer(manager.exportInputBindingProfileUseLock(true), port: playerIndex, data: selectedLayout?.data)
            manager.acceptCurrentBindingsUseLock(true)
            updateResetButton()
        } catch {
            RetroGoLogger.game.error("Failed to save layout controller mapping: \(String(describing: error))")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.viewIfLoaded?.window != nil,
                      self.navigationController?.visibleViewController === self else { return }
                self.showSelectedLayout()
                self.showSaveError()
            }
        }
    }

    private func showSaveError() {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "configpage_binding_save_failed"),
                                      message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
        present(alert, animated: true)
    }

    @objc private func resetBindings() {
        guard !isReadOnly else { return }
        Vibration.selection.vibrate()
        overlayView?.resetToDefault()
        updateResetButton()
    }

    private func updateResetButton() {
        resetBarButton?.isEnabled = !isReadOnly && manager.hasNonDefaultBindings(forPort: Int32(playerIndex), useLock: true)
    }
}
