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
import RACoordinator
import SpriteKit

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
        /// A new layout starting from the bundled default controls.
        case create
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
        case .create:
            guard session.canCreateAnotherLayout || AppStoreProFeatureGate.shared.requirePro(feature: .overlayLayout, from: gamePage) else { return false }
            data = GameOverlayLayoutData()
        case .edit(let item):
            guard session.canEditLayout(id: item.id) || AppStoreProFeatureGate.shared.requirePro(feature: .overlayLayoutEditing, from: gamePage) else { return false }
            data = item.data
        }
        guard !isEditing, let gamePage, gamePage.isGameReady,
              let lease = GamePauseCoordinator.shared.acquire(reason: "overlay-layout-edit") else { return false }
        guard let editor = overlayView.beginEditing(layoutData: data) else {
            lease.release()
            return false
        }
        self.target = target
        self.completion = completion
        editorScene = editor
        pauseLease = lease
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
        RetroGoLogger.game.info("Started editing an overlay layout of \(self.session.templateId, privacy: .public)")
        return true
    }

    /// Keeps the panel on screen after a rotation.
    func viewDidLayout() {
        guard let panel, let view = gamePage?.view else { return }
        sizePanel()
        panel.keepInside(view.bounds.inset(by: view.safeAreaInsets))
    }

    private func bind(_ panel: GameOverlayLayoutEditPanel, to editor: GameOverlayLayoutEditorScene) {
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
        panel.onToggleSelectionHidden = { [weak editor] in editor?.toggleSelectionHidden() }
        panel.onSelectMember = { [weak self] in self?.presentSlotPicker($0) }
        panel.onEditFan = { [weak self] in self?.presentFanEditor() }
        panel.onAddCombo = { [weak self] button in self?.presentNewExtensionMenu(from: button) }
        panel.onEditCombo = { [weak self] id in
            if self?.editorScene?.userMacro(id: id) != nil { self?.presentMacroEditor(buttonId: id) }
            else { self?.presentComboEditor(comboId: id) }
        }
        panel.onSizeChanged = { [weak self] in self?.viewDidLayout() }
        editor.onEditSlot = { [weak self] in self?.presentSlotPicker($0) }
    }

    private func refreshPanel() {
        guard let editor = editorScene, let panel else { return }
        panel.update(GameOverlayLayoutEditPanel.State(
            isPortrait: editor.isPortrait,
            canUndo: editor.canUndo,
            canReset: editor.editedOrientation != nil,
            selectionTitle: editor.selectionTitle,
            selectionComboTitle: editor.selectionComboTitle,
            selectionScale: editor.selectionScale,
            selectionHidden: editor.selectionHidden,
            combos: editor.comboElements.map {
                GameOverlayLayoutEditPanel.Combo(id: $0.id, title: $0.type == .macro
                    ? ($0.comboTitle ?? GameOverlayComboTitle(parts: [.symbol(GameOverlayMacro.defaultSymbol, text: "")]))
                    : ($0.comboTitle ?? GameOverlayComboTitle(parts: [.text($0.buttonTitle)])),
                                                 shown: !editor.isHiddenInLayout($0),
                                                 isTurbo: $0.isTurbo, isUserCombo: editor.userCombo(id: $0.id) != nil || editor.userMacro(id: $0.id) != nil,
                                                 isMacro: $0.type == .macro)
            },
            selectedUserComboId: editor.selectedUserCombo?.id ?? editor.selectedMacroButtonId,
            note: sharedNote,
            groupMembers: editor.fanSlots.map { slot in
                guard let element = slot.element else { return .init(id: slot.id, title: .init(parts: [.text("+")]), hidden: false) }
                let parts = (element.comboTitle ?? GameOverlayComboTitle(parts: [.text(element.buttonTitle)])).parts
                    + (element.isTurbo ? [.symbol("bolt.fill", text: "⚡")] : [])
                return .init(id: slot.id, title: .init(parts: parts), hidden: editor.isHiddenInLayout(element))
            },
            selectedSlotId: editor.selectedSlotId,
            selectedSlotOccupied: editor.fanSlots.first { $0.id == editor.selectedSlotId }?.element != nil,
            memberHidden: editor.fanSlots.first { $0.id == editor.selectedSlotId }?.element.map(editor.isHiddenInLayout),
            canEditFan: editor.canEditFan
        ))
    }

    private func presentSlotPicker(_ id: String) {
        guard let gamePage, let editor = editorScene, gamePage.presentedViewController == nil else { return }
        editor.selectFanSlot(id)
        let slot = editor.fanSlots.first { $0.id == id }
        let picker = GameOverlayFanSlotPickerViewController(currentId: slot?.element?.id,
            isHidden: slot?.element.map(editor.isHiddenInLayout) ?? false,
            candidates: editor.slotCandidates(id),
            onPick: { [weak editor] in editor?.assignSlot(id, elementId: $0) },
            onToggleHidden: { [weak editor] in editor?.toggleGroupMemberHidden() })
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        gamePage.present(navigation, animated: true)
    }

    private func presentFanEditor() {
        guard let gamePage, let editor = editorScene, editor.canEditFan, gamePage.presentedViewController == nil else { return }
        editor.beginContinuousEdit()
        let controller = GameOverlayFanEditViewController(fan: editor.selectedFan, hasOuterRing: editor.fanHasOuterRing,
            preview: { [weak editor] in editor?.fanPreview() ?? [] },
            candidates: { [weak editor] in editor?.slotCandidates($0) ?? [] },
            onPick: { [weak editor] in editor?.assignSlot($0, elementId: $1) },
            onToggleHidden: { [weak editor] id in
                editor?.selectFanSlot(id)
                editor?.toggleGroupMemberHidden()
            },
            onChange: { [weak editor] in editor?.setFan($0) },
            onFinish: { [weak editor] in editor?.endContinuousEdit() })
        let navigation = UINavigationController(rootViewController: controller)
        navigation.sheetPresentationController?.detents = [.large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        navigation.presentationController?.delegate = controller
        gamePage.present(navigation, animated: true)
    }

    private func presentNewExtensionMenu(from button: UIButton) {
        guard let gamePage, gamePage.presentedViewController == nil else { return }
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "overlay_extension_new"), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "overlay_extension_combo"), style: .default) { [weak self, weak alert] _ in
            alert?.dismiss(animated: true) { self?.presentComboEditor(comboId: nil) }
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "overlay_macro_title"), style: .default) { [weak self, weak alert] _ in
            alert?.dismiss(animated: true) { self?.presentMacroEditor(buttonId: nil) }
        })
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = button
        alert.popoverPresentationController?.sourceRect = button.bounds
        gamePage.present(alert, animated: true)
    }

    private func presentMacroEditor(buttonId: String?) {
        guard let gamePage, let editor = editorScene, gamePage.presentedViewController == nil else { return }
        let macro = buttonId.flatMap(editor.userMacro(id:))
        let directions = [("UP", "↑", "arrow.up"), ("DOWN", "↓", "arrow.down"), ("LEFT", "←", "arrow.left"), ("RIGHT", "→", "arrow.right")].map {
            GameOverlayComboKey(bind: GamePageOverlayAction($0.0), title: $0.1, symbol: $0.2)
        }
        let controller = GameOverlayMacroEditViewController(macro: macro, keys: directions + editor.comboKeys,
            shown: buttonId.flatMap(editor.element(id:)).map(editor.isShown) ?? true,
            usedSymbols: Set(editor.macrosToSave.map(\.resolvedSymbol)))
        controller.onSave = { [weak editor] macro, shown in editor?.saveMacro(macro, shown: shown) }
        if let buttonId { controller.onDelete = { [weak editor] in editor?.removeMacro(id: buttonId) } }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.sheetPresentationController?.detents = [.large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        navigation.presentationController?.delegate = controller
        gamePage.present(navigation, animated: true)
    }

    /// Makes a combo (nil) or edits one of the user's in a sheet over the paused game.
    private func presentComboEditor(comboId: String?) {
        guard let gamePage, let editor = editorScene, gamePage.presentedViewController == nil else { return }
        let combo = comboId.flatMap(editor.userCombo(id:))
        if comboId != nil, combo == nil { return }
        let controller = GameOverlayComboEditViewController(keys: editor.comboKeys, combo: combo,
            suggestedBinds: comboId == nil ? editor.suggestedComboBinds : [],
            suggestedTurbo: editor.suggestedComboTurbo,
            shown: comboId.flatMap(editor.element(id:)).map(editor.isShown) ?? true,
            reservedIds: Set(editor.comboElements.map(\.id))) { [weak editor] binds in
            guard let editor, let existing = editor.combo(binds: binds, excluding: combo?.id) else { return nil }
            return .init(title: existing.comboTitle?.plainText ?? existing.buttonTitle, isTurbo: existing.isTurbo,
                         isShown: editor.isShown(existing))
        }
        controller.onSave = { [weak editor] combo, shown in editor?.saveCombo(combo, shown: shown) }
        if let combo {
            controller.onDelete = { [weak editor] in editor?.removeCombo(id: combo.id) }
        }
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
        navigation.presentationController?.delegate = controller
        gamePage.present(navigation, animated: true)
    }

    /// Editing a layout other games use changes it for them too.
    private var sharedNote: String? {
        guard case .edit(let item) = target else { return nil }
        let usage = session.usage(of: item.id)
        let ownGame = session.gameChoice() == .custom(item.id) ? 1 : 0
        guard usage.platform || usage.drivers > 0 || usage.games - ownGame > 0 else { return nil }
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
            guard session.canEditLayout(id: item.id) || AppStoreProFeatureGate.shared.requirePro(feature: .overlayLayoutEditing, from: gamePage) else { return }
            guard session.updateLayout(id: item.id, data: editor.layoutData) else {
                showSaveFailed()
                return
            }
            RetroGoLogger.game.info("Saved overlay layout \(item.id, privacy: .public) of \(self.session.templateId, privacy: .public)")
            finish(saved: session.layout(id: item.id))
        case .create:
            // Checked again here: the list may have been opened before a purchase was refunded.
            guard session.canCreateAnotherLayout ||
                  AppStoreProFeatureGate.shared.requirePro(feature: .overlayLayout, from: gamePage) else { return }
            presentSaveSheet(data: editor.layoutData)
        }
    }

    private func presentSaveSheet(data: GameOverlayLayoutData) {
        guard let gamePage else { return }
        let session = self.session
        var saved: GameOverlayLayoutItem?
        let controller = GameOverlayLayoutSaveViewController(session: session, showsGameOption: session.game != nil) { result in
            guard let item = session.createLayout(name: result.name, data: data) else { return false }
            let applied: Bool
            if result.applyToDriver {
                applied = session.chooseForDriver(layoutId: item.id)
            } else if result.useForGame || result.applyToPlatform {
                applied = session.choose(layoutId: item.id, applyToPlatform: result.applyToPlatform)
            } else {
                applied = true
            }
            guard applied else {
                session.deleteLayout(id: item.id)
                return false
            }
            RetroGoLogger.game.info("Saved new overlay layout \(item.id, privacy: .public) of \(session.templateId, privacy: .public)")
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

/// A compact picker shared by the floating panel and fan preview.
private final class GameOverlayFanSlotPickerViewController: UITableViewController {
    private let currentId: String?
    private var isHidden: Bool
    private let candidates: [GamePageOverlayElement]
    private let onPick: (String?) -> Void
    private let onToggleHidden: () -> Void
    private var sections: [[GamePageOverlayElement]] {
        [candidates.filter { $0.type == .button }, candidates.filter { $0.type == .combo }, candidates.filter { $0.type == .macro }]
    }
    init(currentId: String?, isHidden: Bool, candidates: [GamePageOverlayElement],
         onPick: @escaping (String?) -> Void, onToggleHidden: @escaping () -> Void) {
        self.currentId = currentId; self.isHidden = isHidden; self.candidates = candidates
        self.onPick = onPick; self.onToggleHidden = onToggleHidden
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = Bundle.localizedString(forKey: currentId == nil ? "overlay_slot_add" : "overlay_slot_replace")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        if currentId != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: isHidden ? "eye.slash" : "eye"),
                style: .plain, target: self, action: #selector(toggleHidden))
            navigationItem.rightBarButtonItem?.accessibilityLabel = Bundle.localizedString(forKey: isHidden ? "overlay_layout_show_control" : "overlay_layout_hide_control")
        }
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
    }
    override func numberOfSections(in tableView: UITableView) -> Int { currentId == nil ? 3 : 4 }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section < 3 && !sections[section].isEmpty ? UITableView.automaticDimension : .leastNormalMagnitude
    }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section < 3 && sections[section].isEmpty ? .leastNormalMagnitude : 12
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 3 ? 1 : (sections[section].count + 2) / 3
    }
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < 3, !sections[section].isEmpty else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as! RGSectionHeaderView
        header.text = Bundle.localizedString(forKey: ["overlay_slot_native", "overlay_extension_combo", "overlay_macro_title"][section])
        return header
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        if indexPath.section == 3 {
            var content = cell.defaultContentConfiguration()
            content.text = Bundle.localizedString(forKey: "overlay_layout_detach")
            content.textProperties.color = .systemRed
            cell.contentConfiguration = content
            return cell
        }
        cell.selectionStyle = .none
        let stack = UIStackView()
        stack.axis = .horizontal; stack.spacing = 8; stack.distribution = .fillEqually
        for column in 0..<3 {
            let index = indexPath.row * 3 + column
            guard index < sections[indexPath.section].count else { stack.addArrangedSubview(UIView()); continue }
            let element = sections[indexPath.section][index]
            var config = UIButton.Configuration.tinted()
            config.baseForegroundColor = .label
            config.baseBackgroundColor = element.id == currentId ? .mainColor : .tertiarySystemFill
            var parts = (element.comboTitle ?? .init(parts: [.text(element.buttonTitle)])).parts
            if element.isTurbo { parts.append(.symbol("bolt.fill", text: "⚡")) }
            let text = NSMutableAttributedString(attributedString: GameOverlayComboTitle(parts: parts).attributedString(font: .systemFont(ofSize: 17), joined: false))
            text.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.length))
            config.attributedTitle = AttributedString(text)
            if element.type == .macro { config.subtitle = element.buttonTitle }
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.choose(element.id) })
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.accessibilityLabel = element.type == .macro ? element.buttonTitle : GameOverlayComboTitle(parts: parts).plainText
            stack.addArrangedSubview(button)
        }
        cell.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8)])
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 3 { choose(nil) }
    }
    private func choose(_ id: String?) { onPick(id); dismiss(animated: true) }

    @objc private func toggleHidden() {
        isHidden.toggle()
        onToggleHidden()
        navigationItem.rightBarButtonItem?.image = UIImage(systemName: isHidden ? "eye.slash" : "eye")
        navigationItem.rightBarButtonItem?.accessibilityLabel = Bundle.localizedString(forKey: isHidden ? "overlay_layout_show_control" : "overlay_layout_hide_control")
    }
}

private final class GameOverlayFanEditViewController: UITableViewController, UIAdaptivePresentationControllerDelegate {
    private var fan: GameOverlayLayoutData.Fan
    private let hasOuterRing: Bool
    private let preview: () -> [GameOverlayLayoutEditorScene.FanSlot]
    private let candidates: (String) -> [GamePageOverlayElement]
    private let onPick: (String, String?) -> Void
    private let onToggleHidden: (String) -> Void
    private var previewHits: [(String, CGRect)] = []
    private let onChange: (GameOverlayLayoutData.Fan) -> Void
    private let onFinish: () -> Void
    private var finished = false
    private let previewView = SKView()
    private var previewSize: CGSize = .zero

    init(fan: GameOverlayLayoutData.Fan, hasOuterRing: Bool,
         preview: @escaping () -> [GameOverlayLayoutEditorScene.FanSlot],
         candidates: @escaping (String) -> [GamePageOverlayElement],
         onPick: @escaping (String, String?) -> Void,
         onToggleHidden: @escaping (String) -> Void,
         onChange: @escaping (GameOverlayLayoutData.Fan) -> Void, onFinish: @escaping () -> Void) {
        self.fan = fan; self.hasOuterRing = hasOuterRing
        self.preview = preview; self.onChange = onChange; self.onFinish = onFinish
        self.candidates = candidates; self.onPick = onPick; self.onToggleHidden = onToggleHidden
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = Bundle.localizedString(forKey: "overlay_layout_edit_fan")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: Bundle.localizedString(forKey: "overlay_layout_reset"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.fan = .init()
            self.onChange(self.fan)
            self.tableView.reloadData()
            self.updatePreview()
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.finish()
            self?.dismiss(animated: true)
        })
        tableView.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 70
        previewView.isUserInteractionEnabled = true
        previewView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapSlot(_:))))
        previewView.backgroundColor = .clear
        previewView.allowsTransparency = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard previewSize != previewView.bounds.size else { return }
        previewSize = previewView.bounds.size
        updatePreview()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : (hasOuterRing ? 4 : 3) }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as! RGSectionFooterView
        footer.text = Bundle.localizedString(forKey: "overlay_layout_fan_footer")
        return footer
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.separatorInset = .zero
        if indexPath.section == 0 {
            cell.contentView.addSubview(previewView)
            previewView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([previewView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                previewView.heightAnchor.constraint(equalToConstant: 220)])
            return cell
        }
        let index = indexPath.row
        let keys = ["radius", "theta", "spread", "rings"]
        let ranges: [(Float, Float)] = [(0.5, 1.8), (-90, 90), (0.5, 2), (-60, 100)]
        let values = [fan.radiusScale, fan.thetaOffset, fan.spreadScale, fan.ringOffset]
        let label = UILabel()
        label.text = Bundle.localizedString(forKey: "overlay_layout_fan_" + keys[index])
        label.font = .preferredFont(forTextStyle: .body)
        let value = UILabel()
        value.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        value.textColor = .secondaryLabel
        value.text = formatted(values[index], index: index)
        let header = UIStackView(arrangedSubviews: [label, UIView(), value])
        header.axis = .horizontal
        let slider = UISlider()
        slider.minimumValue = ranges[index].0; slider.maximumValue = ranges[index].1
        slider.value = Float(values[index])
        slider.addAction(UIAction { [weak self, weak slider, weak value] _ in
            guard let self, let slider else { return }
            let amount = index == 1 || index == 3 ? Double(slider.value.rounded()) : Double((slider.value * 100).rounded()) / 100
            switch index {
            case 0: self.fan.radiusScale = amount
            case 1: self.fan.thetaOffset = amount
            case 2: self.fan.spreadScale = amount
            default: self.fan.ringOffset = amount
            }
            value?.text = self.formatted(amount, index: index)
            self.onChange(self.fan)
            self.updatePreview()
        }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [header, slider])
        stack.axis = .vertical; stack.spacing = 8
        cell.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)])
        return cell
    }
    private func formatted(_ amount: Double, index: Int) -> String {
        if index == 1 { return String(format: "%.0f°", amount) }
        if index == 3 { return String(format: "%+.0f", amount) }
        return String(format: "×%.2f", amount)
    }
    private func updatePreview() {
        guard previewView.bounds.width > 0 else { return }
        let scene = SKScene(size: previewView.bounds.size)
        scene.backgroundColor = .clear
        scene.anchorPoint = .zero
        let entries = preview()
        let bounds = entries.map(\.rect).reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else { previewView.presentScene(scene); return }
        let group = SKNode()
        group.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        let scale = min(1.5, (scene.size.width - 32) / max(1, bounds.width), (scene.size.height - 32) / max(1, bounds.height))
        group.setScale(scale)
        previewHits = []
        for entry in entries {
            let rect = entry.rect
            let node: SKNode
            if let element = entry.element {
                let button = GameOverlayActionButton(element: element, isTurboSupported: false, autoKeepTurbo: false, digitalChangeHandler: nil)
                button.usesFanStyle = true
                _ = button.updateRect(rect, shouldUpdatePosition: true)
                node = button
            } else {
                let empty = SKShapeNode(ellipseOf: rect.size)
                empty.strokeColor = .lightGray; empty.fillColor = .clear
                let plus = SKLabelNode(text: "+")
                plus.fontColor = .mainColor; plus.fontSize = 24; plus.verticalAlignmentMode = .center
                empty.addChild(plus)
                node = empty
            }
            node.position = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
            node.zRotation = entry.rotation
            node.alpha = entry.hidden ? 0.3 : 1
            node.isUserInteractionEnabled = false
            group.addChild(node)
            let center = CGPoint(x: scene.size.width / 2 + (rect.midX - bounds.midX) * scale,
                y: scene.size.height / 2 + (rect.midY - bounds.midY) * scale)
            previewHits.append((entry.id, CGRect(x: center.x - rect.width * scale / 2,
                y: scene.size.height - center.y - rect.height * scale / 2,
                width: rect.width * scale, height: rect.height * scale).insetBy(dx: -6, dy: -6)))
        }
        scene.addChild(group)
        previewView.presentScene(scene)
    }
    @objc private func tapSlot(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: previewView)
        guard presentedViewController == nil, let id = previewHits.first(where: { $0.1.contains(point) })?.0 else { return }
        let current = preview().first { $0.id == id }?.element?.id
        let slot = preview().first { $0.id == id }
        let picker = GameOverlayFanSlotPickerViewController(currentId: current,
            isHidden: slot?.hidden ?? false,
            candidates: candidates(id),
            onPick: { [weak self] newId in
                self?.onPick(id, newId)
                self?.updatePreview()
            },
            onToggleHidden: { [weak self] in
                self?.onToggleHidden(id)
                self?.updatePreview()
            })
        let navigation = UINavigationController(rootViewController: picker)
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
}
