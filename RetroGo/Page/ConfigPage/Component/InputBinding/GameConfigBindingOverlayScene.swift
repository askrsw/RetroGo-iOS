//
//  GameConfigBindingOverlayScene.swift
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

import SpriteKit
import ObjcHelper
import RACoordinator

final class GameConfigBindingOverlayScene: SKScene, GameOverlaySceneLayouting {
    private var dpad: GameOverlayDirectionPad?
    private var actionButtons: [GameOverlayActionButton] = []
    private var n64CButton: GameOverlayN64CButton?
    private var fastButton: GameOverLayFastButton?
    private var bindingDisplayNames: [RetroArchJoypadCode: String] = [:]
    private var activeBinding: ActiveBinding?

    private(set) var isDirty: Bool = false {
        didSet {
            onDirtyChanged?(isDirty)
        }
    }

    let config: GamePageOverlayConfig
    let playerIndex: Int
    let inputActionManager: RAInputActionManager
    let overlayTheme: GameOverlayTheme
    let isReadOnly: Bool

    var overlayLayoutResolver: GameOverlayLayoutResolver
    var usePolarLayout = false

    var onDirtyChanged: ((Bool) -> Void)?
    var shouldAllowBindingChange: (() -> Bool)?

    init(
        size: CGSize,
        config: GamePageOverlayConfig,
        playerIndex: Int,
        overlayTheme: GameOverlayTheme = .bindingConfiguration,
        isReadOnly: Bool = false
    ) {
        self.config = config
        self.overlayLayoutResolver = GameOverlayLayoutResolver(config: config)
        self.playerIndex = playerIndex
        self.inputActionManager = RAInputActionManager.shared()
        self.overlayTheme = overlayTheme
        self.isReadOnly = isReadOnly
        super.init(size: size)

        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero

        let displayNames = inputActionManager.joypadBindingDisplayNames(forPort: Int32(playerIndex), useLock: true)
        bindingDisplayNames = displayNames.reduce(into: [:]) { result, item in
            guard let code = RetroArchJoypadCode(rawValue: item.key.int32Value) else { return }
            result[code] = item.value
        }

        updateOverlayLayout(for: size)
        buildNodes()

        if !isReadOnly {
            registerPhysicalSourcePressHandler()
        }
    }

    deinit {
        inputActionManager.physicalSourcePressHandler = nil
        inputActionManager.fastForwardMultiplierProvider = nil
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLayout(for size: CGSize) {
        updateOverlayLayout(for: size)
        layoutNodes()
    }

    func resetToDefault() {
        guard !isReadOnly else { return }
        inputActionManager.resetBindingsToDefault(forPort: Int32(playerIndex), useLock: true)
        activeBinding = nil
        isDirty = true
        reloadBindingDisplayNames()
        refreshBindingBubbles()
    }

    func exportBindingProfileForPersistence() -> RAInputBindingProfile? {
        inputActionManager.exportInputBindingProfileUseLock(true)
    }
}

private extension GameConfigBindingOverlayScene {
    struct BindingBubbleDisplay {
        let text: String
        let systemImageName: String?

        static func text(_ text: String) -> BindingBubbleDisplay {
            BindingBubbleDisplay(text: text, systemImageName: nil)
        }

        static func iconText(_ text: String, _ systemImageName: String) -> BindingBubbleDisplay {
            BindingBubbleDisplay(text: text, systemImageName: systemImageName)
        }
    }

    final class ActiveBinding {
        weak var presenter: (any GameConfigBindingSettingPresenting)?
        let actionId: String
        let target: BindingTarget

        init(presenter: any GameConfigBindingSettingPresenting, actionId: String, target: BindingTarget) {
            self.presenter = presenter
            self.actionId = actionId
            self.target = target
        }
    }

    enum BindingTarget {
        case joypad(RetroArchJoypadCode)
        case inputAction(RAInputActionDescriptor)
    }

    func buildNodes() {
        for element in config.elements {
            if let node = makeNode(for: element) {
                addChild(node)
            }
        }
    }

    func layoutNodes() {
        let nodes: [GameOverlayElementLayout] = [dpad, n64CButton, fastButton].compactMap({ $0 }) + actionButtons
        for node in nodes {
            let rect = resolveOverlayRect(node.element)
            _ = node.updateRect(rect, shouldUpdatePosition: true)
            configureBindingBubbles(for: node)
        }
    }

    func makeNode(for element: GamePageOverlayElement) -> SKNode? {
        let node: SKNode?
        switch element.type {
        case .dpad:
            let dpad = GameOverlayDirectionPad(element: element, allowsDiagonalInput: false, theme: overlayTheme) { [weak self] code, down in
                guard down else { return }
                self?.activateBinding(elementId: element.id, joypadCode: code)
            }
            self.dpad = dpad
            node = dpad
        case .button:
            let button = GameOverlayActionButton(element: element, isTurboSupported: false, autoKeepTurbo: false, theme: overlayTheme) { [weak self] code, down in
                guard down else { return }
                if element.isCombo {
                    self?.activateBinding(elementId: element.id)
                } else {
                    self?.activateBinding(elementId: element.id, joypadCode: code)
                }
            }
            self.actionButtons.append(button)
            node = button
        case .n64CButton:
            let button = GameOverlayN64CButton(element: element, theme: overlayTheme) { [weak self] code, down in
                guard down else { return }
                self?.activateBinding(elementId: element.id, joypadCode: code)
            }
            self.n64CButton = button
            node = button
        case .fastButton:
            if playerIndex != 0 {
                return nil
            }
            let button = GameOverLayFastButton(element: element, theme: overlayTheme) { [weak self] _ in
                self?.activateBinding(elementId: element.id)
            }
            self.fastButton = button
            node = button
        default:
            node = nil
        }

        return node
    }

    func activateBinding(elementId: String) {
        guard !isReadOnly else { return }
        let nodes: [GameOverlayElementLayout] = [dpad, n64CButton, fastButton].compactMap({ $0 }) + actionButtons
        guard let node = nodes.first(where: { $0.element.id == elementId }),
              let presenter = node as? GameConfigBindingSettingPresenting,
              let actionId = presenter.bindingActionIds().first,
              let target = bindingTarget(for: presenter, actionId: actionId) else {
            return
        }

        setActiveBinding(presenter: presenter, actionId: actionId, target: target)
    }

    func configureBindingBubbles(for node: GameOverlayElementLayout) {
        guard let presenter = node as? GameConfigBindingSettingPresenting else { return }
        for actionId in presenter.bindingActionIds() {
            updateBindingBubble(for: presenter, actionId: actionId)
            presenter.setBindingBubbleActive(isActiveBinding(presenter: presenter, actionId: actionId), for: actionId)
        }
    }

    func activateBinding(elementId: String, joypadCode: RetroArchJoypadCode) {
        guard !isReadOnly else { return }
        let nodes: [GameOverlayElementLayout] = [dpad, n64CButton, fastButton].compactMap({ $0 }) + actionButtons
        guard let node = nodes.first(where: { $0.element.id == elementId }),
              let presenter = node as? GameConfigBindingSettingPresenting else {
            return
        }

        guard let actionId = presenter.bindingActionIds().first(where: { presenter.bindingJoypadCode(for: $0) == joypadCode }) else {
            return
        }

        guard let target = bindingTarget(for: presenter, actionId: actionId) else {
            return
        }

        setActiveBinding(presenter: presenter, actionId: actionId, target: target)
    }

    func setActiveBinding(presenter: any GameConfigBindingSettingPresenting, actionId: String, target: BindingTarget) {
        if isActiveBinding(presenter: presenter, actionId: actionId) {
            return
        }

        if let oldBinding = activeBinding, let oldPresenter = oldBinding.presenter {
            setDefaultBindingBubble(for: oldPresenter, actionId: oldBinding.actionId)
            oldPresenter.setBindingBubbleActive(false, for: oldBinding.actionId)
        }

        activeBinding = ActiveBinding(presenter: presenter, actionId: actionId, target: target)
        updateBindingBubble(for: presenter, actionId: actionId)
        presenter.setBindingBubbleActive(true, for: actionId)
    }

    func registerPhysicalSourcePressHandler() {
        inputActionManager.physicalSourcePressHandler = { [weak self] source in
            if let ret = self?.handlePhysicalSourcePress(source) {
                return ret
            } else {
                return false
            }
        }
    }

    func handlePhysicalSourcePress(_ source: RAInputPhysicalSource) -> Bool {
        guard !isReadOnly else { return false }
        guard source.playerIndex == playerIndex,
              let activeBinding,
              let presenter = activeBinding.presenter else {
            return false
        }

        if shouldAllowBindingChange?() == false {
            return true
        }

        let didBind: Bool
        switch activeBinding.target {
        case .joypad(let code):
            didBind = inputActionManager.bindJoypadCode(code, to: source, forPort: Int32(playerIndex), useLock: true)
        case .inputAction(let descriptor):
            inputActionManager.setActionDescriptor(descriptor, useLock: true)
            inputActionManager.bindPhysicalSource(source, toActionIdentifier: descriptor.identifier, useLock: true)
            didBind = true
        }
        guard didBind else { return false }

        isDirty = true

        presenter.setBindingBubbleActive(false, for: activeBinding.actionId)
        self.activeBinding  = nil
        reloadBindingDisplayNames()
        refreshBindingBubbles()
        return true
    }

    func reloadBindingDisplayNames() {
        let displayNames = inputActionManager.joypadBindingDisplayNames(forPort: Int32(playerIndex), useLock: true)
        bindingDisplayNames = displayNames.reduce(into: [:]) { result, item in
            guard let code = RetroArchJoypadCode(rawValue: item.key.int32Value) else { return }
            result[code] = item.value
        }
    }

    func refreshBindingBubbles() {
        let nodes: [GameOverlayElementLayout] = [dpad, n64CButton, fastButton].compactMap({ $0 }) + actionButtons
        for node in nodes {
            configureBindingBubbles(for: node)
        }
    }

    func updateBindingBubble(for presenter: any GameConfigBindingSettingPresenting, actionId: String) {
        if !isReadOnly, isActiveBinding(presenter: presenter, actionId: actionId) {
            presenter.setBindingBubbleText(Bundle.localizedString(forKey: "configpage_press_button"), for: actionId)
        } else {
            setDefaultBindingBubble(for: presenter, actionId: actionId)
        }
    }

    func setDefaultBindingBubble(for presenter: any GameConfigBindingSettingPresenting, actionId: String) {
        guard let display = defaultBindingDisplay(for: presenter, actionId: actionId) else {
            presenter.setBindingBubbleText(nil, for: actionId)
            return
        }

        presenter.setBindingBubbleText(display.text, systemImageName: display.systemImageName, for: actionId)
    }

    func defaultBindingDisplay(for presenter: any GameConfigBindingSettingPresenting, actionId: String) -> BindingBubbleDisplay? {
        guard let node = presenter as? GameOverlayElementLayout else {
            return nil
        }

        return bindingDisplay(for: presenter, actionId: actionId, element: node.element)
    }

    func isActiveBinding(presenter: any GameConfigBindingSettingPresenting, actionId: String) -> Bool {
        guard let activeBinding,
              let activePresenter = activeBinding.presenter else {
            return false
        }

        return (activePresenter as AnyObject) === (presenter as AnyObject) && activeBinding.actionId == actionId
    }

    func bindingDisplay(for presenter: any GameConfigBindingSettingPresenting, actionId: String, element: GamePageOverlayElement) -> BindingBubbleDisplay? {
        if element.type == .n64CButton {
            let code = presenter.bindingJoypadCode(for: actionId)
            guard code != .none else { return nil }

            let codeName = bindingDisplayNames[code] ?? fallbackBindingDisplayName(for: code)
            let codeLabel = shortBindingDisplay(codeName, fallbackCode: code).text

            let modifierCode: RetroArchJoypadCode = .R2
            let modifierName = bindingDisplayNames[modifierCode] ?? fallbackBindingDisplayName(for: modifierCode)
            let modifierLabel = shortBindingDisplay(modifierName, fallbackCode: modifierCode).text

            return .text("\(modifierLabel)+\(codeLabel)")
        }

        if element.type == .ndsLayoutButton {
            guard let target = bindingTarget(for: presenter, actionId: actionId),
                  case .inputAction(let descriptor) = target else {
                return nil
            }

            // 已绑定物理键：显示物理键名
            if let displayName = inputActionManager.physicalSourceDisplayName(forActionIdentifier: descriptor.identifier, useLock: true) {
                return shortBindingDisplay(displayName, fallbackCode: .none)
            }

            // 未绑定：显示复合语义 R2+R3
            let labels = element.binds
                .map(\.code)
                .filter { $0 != .none }
                .map { fallbackBindingDisplayName(for: $0) }

            if labels.isEmpty { return nil }
            return .text(labels.joined(separator: "+"))
        }

        if element.isNative || element.type == .dpad || element.type == .n64CButton || element.type == .ndsLayoutButton {
            let code = presenter.bindingJoypadCode(for: actionId)
            guard code != .none else { return nil }
            guard let displayName = bindingDisplayNames[code] else { return nil }
            return shortBindingDisplay(displayName, fallbackCode: code)
        }

        guard let target = bindingTarget(for: presenter, actionId: actionId),
              case .inputAction(let descriptor) = target else {
            return nil
        }

        if let displayName = inputActionManager.physicalSourceDisplayName(forActionIdentifier: descriptor.identifier, useLock: true) {
            return shortBindingDisplay(displayName, fallbackCode: presenter.bindingJoypadCode(for: actionId))
        }

        // fallback: default turbo X/Y when profile is nil or no explicit overlay action binding
        if !element.isCombo, element.isTurbo, let defaultSourceIdentifier = defaultPhysicalSourceIdentifier(for: element), !isPhysicalSourceUsedByNativeOverlayBindings(defaultSourceIdentifier), let displayName = inputActionManager.displayName(forPhysicalSourceIdentifier: defaultSourceIdentifier, useLock: true) {
            return shortBindingDisplay(displayName, fallbackCode: presenter.bindingJoypadCode(for: actionId))
        }

        return nil
    }

    func bindingTarget(for presenter: any GameConfigBindingSettingPresenting, actionId: String) -> BindingTarget? {
        guard let node = presenter as? GameOverlayElementLayout else {
            return nil
        }

        let element = node.element
        let code = presenter.bindingJoypadCode(for: actionId)
        if element.isNative || element.type == .dpad || element.type == .n64CButton {
            guard code != .none else { return nil }
            return .joypad(code)
        }

        if element.type == .fastButton {
            if playerIndex == 0 {
                let descriptor = RAInputActionDescriptor.fastForwardAction(
                    withIdentifier: inputActionIdentifier(for: element, actionId: actionId),
                    displayName: element.title ?? actionId
                )
                return .inputAction(descriptor)
            } else {
                return nil
            }
        }

        if element.type == .ndsLayoutButton {
            let outputCodes = element.binds.map(\.code).filter { $0 != .none }
            guard !outputCodes.isEmpty else { return nil }

            let descriptor = RAInputActionDescriptor.joypadOutputAction(
                withIdentifier: inputActionIdentifier(for: element, actionId: actionId),
                displayName: element.title ?? actionId,
                outputJoypadCodes: outputCodes.map { NSNumber(value: $0.rawValue) },
                turboEnabled: false
            )
            return .inputAction(descriptor)
        }

        if element.isCombo || element.isTurbo {
            let outputCodes = element.binds.map(\.code).filter({ $0 != .none })
            guard !outputCodes.isEmpty else { return nil }

            let descriptor = RAInputActionDescriptor.joypadOutputAction(
                withIdentifier: inputActionIdentifier(for: element, actionId: actionId),
                displayName: element.title ?? actionId,
                outputJoypadCodes: outputCodes.map({ NSNumber(value: $0.rawValue) }),
                turboEnabled: element.isCombo || element.isTurbo
            )
            return .inputAction(descriptor)
        }

        return nil
    }

    func inputActionIdentifier(for element: GamePageOverlayElement, actionId: String) -> String {
        let normalizedActionId = actionId
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "player:\(playerIndex):overlay:\(element.id):\(normalizedActionId)"
    }

    func defaultPhysicalSourceIdentifier(for element: GamePageOverlayElement) -> String? {
        guard !element.isCombo,
              element.isTurbo,
              element.binds.count == 1 else {
            return nil
        }

        switch element.binds[0].code {
        case .A:
            return portScopedSourceIdentifier(joykey: RetroArchJoypadCode.X.rawValue)
        case .B:
            return portScopedSourceIdentifier(joykey: RetroArchJoypadCode.Y.rawValue)
        default:
            return nil
        }
    }

    func legacyDefaultPhysicalSourceIdentifier(for element: GamePageOverlayElement) -> String? {
        guard !element.isCombo,
              element.isTurbo,
              element.binds.count == 1 else {
            return nil
        }

        switch element.binds[0].code {
        case .A:
            return portScopedSourceIdentifier(joykey: RetroArchJoypadCode.Y.rawValue)
        case .B:
            return portScopedSourceIdentifier(joykey: RetroArchJoypadCode.X.rawValue)
        default:
            return nil
        }
    }

    func shouldApplyDefaultPhysicalSource(_ currentSourceIdentifier: String?, for element: GamePageOverlayElement) -> Bool {
        guard let currentSourceIdentifier else {
            guard let defaultSourceIdentifier = defaultPhysicalSourceIdentifier(for: element) else {
                return false
            }
            return !isPhysicalSourceUsedByNativeOverlayBindings(defaultSourceIdentifier)
        }

        return currentSourceIdentifier == legacyDefaultPhysicalSourceIdentifier(for: element)
            && !isPhysicalSourceUsedByNativeOverlayBindings(currentSourceIdentifier)
    }

    func isPhysicalSourceUsedByNativeOverlayBindings(_ sourceIdentifier: String) -> Bool {
        for element in config.elements where element.isNative || element.type == .dpad {
            for bind in element.binds {
                let code = bind.code
                guard code != .none else { continue }
                if inputActionManager.isPhysicalSourceIdentifier(sourceIdentifier, usedBy: code, forPort: Int32(playerIndex), useLock: true) {
                    return true
                }
            }
        }

        return false
    }

    func portScopedSourceIdentifier(joykey: Int32) -> String {
        "port:\(playerIndex):mfi:button:\(joykey)"
    }

    func shortBindingDisplay(_ displayName: String, fallbackCode: RetroArchJoypadCode) -> BindingBubbleDisplay {
        let primaryName = displayName
            .components(separatedBy: ",")
            .first?
            .replacingOccurrences(of: " (Auto)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch primaryName {
        case "D-Pad Up":
            return .text("Up")
        case "D-Pad Right":
            return .text("Right")
        case "D-Pad Down":
            return .text("Down")
        case "D-Pad Left":
            return .text("Left")
        case "Menu/Start":
            return .text("Menu")
        case "Select/Share":
            return .text("Select")
        case "A/Cross":
            return .text("A")
        case "B/Circle":
            return .text("B")
        case "X/Square":
            return .text("X")
        case "Y/Triangle":
            return .text("Y")
        case "Left Trigger":
            return .text("L2")
        case "Right Trigger":
            return .text("R2")
        case "Left Stick Left":
            return .iconText("L", "arcade.stick.and.arrow.left")
        case "Left Stick Right":
            return .iconText("L", "arcade.stick.and.arrow.right")
        case "Left Stick Up":
            return .iconText("L", "arcade.stick.and.arrow.up")
        case "Left Stick Down":
            return .iconText("L", "arcade.stick.and.arrow.down")
        case "Right Stick Left":
            return .iconText("R", "arcade.stick.and.arrow.left")
        case "Right Stick Right":
            return .iconText("R", "arcade.stick.and.arrow.right")
        case "Right Stick Up":
            return .iconText("R", "arcade.stick.and.arrow.up")
        case "Right Stick Down":
            return .iconText("R", "arcade.stick.and.arrow.down")
        case "L2 Axis +", "L2 Axis -":
            return .text("L2")
        case "R2 Axis +", "R2 Axis -":
            return .text("R2")
        case "":
            return .text(fallbackBindingDisplayName(for: fallbackCode))
        default:
            return .text(primaryName)
        }
    }

    func fallbackBindingDisplayName(for code: RetroArchJoypadCode) -> String {
        switch code {
        case .up:
            return "Up"
        case .right:
            return "Right"
        case .down:
            return "Down"
        case .left:
            return "Left"
        case .A:
            return "A"
        case .B:
            return "B"
        case .X:
            return "X"
        case .Y:
            return "Y"
        case .select:
            return "Select"
        case .start:
            return "Menu"
        case .L1:
            return "L1"
        case .R1:
            return "R1"
        case .L2:
            return "L2"
        case .R2:
            return "R2"
        case .L3:
            return "L3"
        case .R3:
            return "R3"
        default:
            return "Default"
        }
    }
}
