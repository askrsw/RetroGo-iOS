//
//  GamePageOverlayScene.swift
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
import RACoordinator

protocol GameOverlayElementLayout: SKNode {
    var element: GamePageOverlayElement { get }
    func updateRect(_ rect: CGRect, shouldUpdatePosition: Bool) -> CGPoint
}

typealias GameOverlayButtonDigitalChanged = (RetroArchJoypadCode, Bool) -> Void
typealias GameOverlayDirectionAnalogChanged = (CGFloat, CGFloat) -> Void
typealias GameOverlaySwitchHandler = (GameOverlayDpadStickSwitch.`Type`) -> Void
typealias GameOverlayFastStateChanged = (Bool) -> Void

final class GamePageOverlayScene: SKScene, GameOverlaySceneLayouting {
    private let config: GamePageOverlayConfig
    private let supportsAnalog: Bool
    private let theme: GameOverlayTheme

    var overlayLayoutResolver: GameOverlayLayoutResolver
    var usePolarLayout = true

    private var dpad: GameOverlayDirectionPad?
    private var stick: Game​Overlay​ThumbStick?
    private var dpadStickSwitch: GameOverlayDpadStickSwitch?
    private var overlayCollapseButton: GameOverlayCollapseButton?
    private var actionButtons: [GameOverlayActionButton] = []
    private var fastButton: GameOverLayFastButton?
    private var n64CButton: GameOverlayN64CButton?
    private var ndsLayoutButton: GameOverlayNDSLayoutButton?
    private var emuFrameActionToken: String?

    private struct CollapseVisualState {
        var position: CGPoint
        let xScale: CGFloat
        let yScale: CGFloat
        let alpha: CGFloat
    }

    private lazy var overlayCollapseSupportNode = SKNode()
    private var overlayCollapsed: Bool?
    private var collapseVisualStates: [ObjectIdentifier: CollapseVisualState] = [:]
    private var isAnimatingCollapse = false

    private var dpadOrStick: GameOverlayDpadStickSwitch.`Type`?

    init(size: CGSize, config: GamePageOverlayConfig, supportsAnalog: Bool, theme: GameOverlayTheme = .default) {
        self.config = config
        self.supportsAnalog = supportsAnalog
        self.theme = theme
        self.overlayLayoutResolver = GameOverlayLayoutResolver(config: config)
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero

        updateOverlayLayout(for: size)
        buildNodes()
        updateEmuFrameCallbackRegistration()
    }

    deinit {
        if let emuFrameActionToken {
            RetroArchX.shared().removeEmuPrevFrameAction(forToken: emuFrameActionToken)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLayout(for size: CGSize) {
        updateOverlayLayout(for: size)
        layoutNodes()
    }

    func setUsePolarLayout(_ enabled: Bool) {
        guard usePolarLayout != enabled else { return }
        usePolarLayout = enabled

        // Only button-like nodes participate in polar layout, so only they need to be re-laid out when toggling.
        let basePostion: CGPoint?
        if let overlayCollapseButton {
            let rect = resolveOverlayRect(overlayCollapseButton.element)
            basePostion = overlayCollapseButton.updateRect(rect, shouldUpdatePosition: true)
        } else {
            basePostion = nil
        }

        let shouldUpdatePosition = !(overlayCollapsed ?? false)
        let polarNodes: [GameOverlayElementLayout] = actionButtons
        layout(nodes: polarNodes, shouldUpdatePosition: shouldUpdatePosition, basePostion: basePostion)
    }
}

extension GamePageOverlayScene {
    private func buildNodes() {
        for element in config.elements {
            let node = makeNode(for: element)
            addChild(node)
        }

        if let overlayCollapseButton {
            children.forEach({
                if $0 != overlayCollapseButton {
                    $0.move(toParent: overlayCollapseSupportNode)
                }
            })
            addChild(overlayCollapseSupportNode)
        }
    }

    private func layoutNodes() {
        let basePostion: CGPoint?
        if let overlayCollapseButton {
            let rect = resolveOverlayRect(overlayCollapseButton.element)
            basePostion = overlayCollapseButton.updateRect(rect, shouldUpdatePosition: true)
        } else {
            basePostion = nil
        }

        let shouldUpdatePosition = !(overlayCollapsed ?? false)
        let nodes: [GameOverlayElementLayout] = [dpad, stick, dpadStickSwitch, ndsLayoutButton, n64CButton, fastButton].compactMap({ $0 }) + actionButtons
        layout(nodes: nodes, shouldUpdatePosition: shouldUpdatePosition, basePostion: basePostion)
    }

    private func layout(nodes: [GameOverlayElementLayout], shouldUpdatePosition: Bool, basePostion: CGPoint?) {
        for node in nodes {
            let rect = resolveOverlayRect(node.element)
            let newPosition = node.updateRect(rect, shouldUpdatePosition: shouldUpdatePosition)

            // Only button-like nodes use polar layout; other overlay elements keep zero rotation.
            let rotatesWithPolarLayout = node is GameOverlayActionButton || node is GameOverLayFastButton
            node.zRotation = resolveOverlayRotation(node.element, rotatesWithPolarLayout: rotatesWithPolarLayout)

            if !shouldUpdatePosition, let basePostion {
                node.position = basePostion
            }

            let key = ObjectIdentifier(node)
            if var state = collapseVisualStates[key] {
                state.position = newPosition
                collapseVisualStates[key] = state
            }
        }
    }

    private func makeNode(for element: GamePageOverlayElement) -> SKNode {
        switch element.type {
        case .dpad:
            return makeDPadNode(element: element)
        case .stick:
            return makeStickNode(element: element)
        case .digitalAnalogSwitch:
            return makeDigitalAnalogSwithNode(element: element)
        case .button:
            return makeButtonNode(element: element)
        case .fastButton:
            return makeFastButtonNode(element: element)
        case .overlayCollapse:
            return makeOverlayCollapseNode(element: element)
        case .n64CButton:
            return makeN64CButtonNode(element: element)
        case .ndsLayoutButton:
            return makeNDSLayoutButtonNode(element: element)
        }
    }

    private func makeDPadNode(element: GamePageOverlayElement) -> SKNode {
        let node = GameOverlayDirectionPad(element: element, theme: theme) { code, down in
            RetroArchX.shared().send(code, down: down)
        }
        node.isHidden = { [weak self] in
            if let v = self?.dpadOrStick {
                return v == .stick
            } else {
                return element.isHidden
            }
        }()
        self.dpad = node
        return node
    }

    private func makeStickNode(element: GamePageOverlayElement) -> SKNode {
        let node: Game​Overlay​ThumbStick
        if supportsAnalog {
            node = Game​Overlay​ThumbStick(element: element, theme: theme, analogHandler: { x, y in
                RetroArchX.shared().send(.leftX, value: x)
                RetroArchX.shared().send(.leftY, value: y)
            })
        } else {
            node = Game​Overlay​ThumbStick(element: element, theme: theme, digitalHandler: { code, down in
                RetroArchX.shared().send(code, down: down)
            })
        }
        node.isHidden = { [weak self] in
            if let v = self?.dpadOrStick {
                return v == .dpad
            } else {
                return element.isHidden
            }
        }()
        self.stick = node
        return node
    }

    private func makeDigitalAnalogSwithNode(element: GamePageOverlayElement) -> SKNode {
        let type: GameOverlayDpadStickSwitch.`Type`
        if let dpadOrStick {
            type = dpadOrStick
            switch type {
                case .dpad:
                    dpad?.isHidden = false
                    stick?.isHidden = true
                case .stick:
                    dpad?.isHidden = true
                    stick?.isHidden = false
            }
        } else if let dpad, dpad.isHidden == false {
            type = .dpad
        } else {
            type = .stick
        }

        let node = GameOverlayDpadStickSwitch(element: element, theme: theme) { [weak self] v in
            guard let self = self else { return }
            switch v {
                case .dpad:
                    dpad?.isHidden = false
                    stick?.isHidden = true
                case .stick:
                    dpad?.isHidden = true
                    stick?.isHidden = false
            }
            dpadOrStick = v
        }
        node.applyType(type)
        self.dpadStickSwitch = node
        return node
    }

    private func makeButtonNode(element: GamePageOverlayElement) -> SKNode {
        let node = GameOverlayActionButton(element: element, isTurboSupported: element.isTurbo, autoKeepTurbo: element.isTurboAutoKeep, theme: theme) { code, down in
            RetroArchX.shared().send(code, down: down)
        }
        self.actionButtons.append(node)
        return node
    }

    private func makeFastButtonNode(element: GamePageOverlayElement) -> SKNode {
        let node = GameOverLayFastButton(element: element, theme: theme) { enabled in
            guard let multiplier = GamePageViewController.instance?.configSession.getFastForwardMultiplier() else {
                return
            }
            RetroArchX.shared().setFastForwardEnabled(enabled, multiplier: multiplier)
        }
        self.fastButton = node
        return node
    }

    private func makeOverlayCollapseNode(element: GamePageOverlayElement) -> SKNode {
        let node = GameOverlayCollapseButton(element: element, theme: theme) { [weak self] collapsed in
            guard let self else { return }
            overlayCollapsed = collapsed
            setOverlayCollapsed(collapsed, animated: true)
        }
        node.applyCollapsed(overlayCollapsed ?? false, animated: false)
        self.overlayCollapseButton = node
        return node
    }

    private func makeN64CButtonNode(element: GamePageOverlayElement) -> SKNode {
        let node = GameOverlayN64CButton(element: element, theme: theme) { code, down in
            RetroArchX.shared().send(code, down: down)
        }
        self.n64CButton = node
        return node
    }

    private func makeNDSLayoutButtonNode(element: GamePageOverlayElement) -> SKNode {
        let node = GameOverlayNDSLayoutButton(element: element, theme: theme) { code, down in
            RetroArchX.shared().send(code, down: down)
        }
        self.ndsLayoutButton = node
        return node
    }

    private func setOverlayCollapsed(_ collapsed: Bool, animated: Bool) {
        overlayCollapseButton?.applyCollapsed(collapsed, animated: animated)

        guard let overlayCollapseButton else {
            overlayCollapseSupportNode.isHidden = collapsed
            return
        }

        if isAnimatingCollapse {
            overlayCollapseSupportNode.removeAllActions()
            overlayCollapseSupportNode.children.forEach { $0.removeAllActions() }
            isAnimatingCollapse = false
        }

        let collapsibleNodes = overlayCollapseSupportNode.children
        guard collapsibleNodes.isEmpty == false else {
            overlayCollapseSupportNode.isHidden = collapsed
            return
        }

        let targetPosition = overlayCollapseSupportNode.convert(overlayCollapseButton.position, from: self)
        let duration: TimeInterval = animated ? 0.2 : 0.0

        if collapsed {
            refreshCollapseVisualStates()
            overlayCollapseSupportNode.isHidden = false
            applyCollapseAnimation(to: collapsibleNodes, targetPosition: targetPosition, animated: animated, duration: duration) { [weak self] in
                guard let self else { return }
                self.overlayCollapseSupportNode.isHidden = true
                collapsibleNodes.forEach { node in
                    let state = self.collapseVisualStates[ObjectIdentifier(node)]
                    node.alpha = state?.alpha ?? 1.0
                }
                self.isAnimatingCollapse = false
            }
        } else {
            overlayCollapseSupportNode.isHidden = false
            collapsibleNodes.forEach { node in
                node.alpha = 0.0
                if duration == 0.0 {
                    node.removeAllActions()
                }
            }
            applyExpandAnimation(to: collapsibleNodes, animated: animated, duration: duration) { [weak self] in
                self?.isAnimatingCollapse = false
            }
        }
    }

    private func refreshCollapseVisualStates() {
        for node in overlayCollapseSupportNode.children {
            let key = ObjectIdentifier(node)
            collapseVisualStates[key] = CollapseVisualState(position: node.position, xScale: node.xScale, yScale: node.yScale, alpha: node.alpha)
        }
    }

    private func applyCollapseAnimation(to nodes: [SKNode], targetPosition: CGPoint, animated: Bool, duration: TimeInterval, completion: @escaping () -> Void) {
        isAnimatingCollapse = true
        let targetSize = overlayCollapseButton?.calculateAccumulatedFrame().size ?? .zero

        for node in nodes {
            let targetScale = collapseScale(for: node, targetSize: targetSize)
            if animated {
                let group = SKAction.group([
                    .move(to: targetPosition, duration: duration),
                    .scaleX(to: targetScale.x, duration: duration),
                    .scaleY(to: targetScale.y, duration: duration),
                    .fadeAlpha(to: 0.0, duration: duration)
                ])
                node.run(group)
            } else {
                node.position = targetPosition
                node.xScale = targetScale.x
                node.yScale = targetScale.y
                node.alpha = 0.0
            }
        }

        if animated {
            run(.sequence([.wait(forDuration: duration), .run(completion)]), withKey: "overlay-collapse")
        } else {
            completion()
        }
    }

    private func applyExpandAnimation(to nodes: [SKNode], animated: Bool, duration: TimeInterval, completion: @escaping () -> Void) {
        isAnimatingCollapse = true

        for node in nodes {
            let key = ObjectIdentifier(node)
            let state = collapseVisualStates[key] ?? CollapseVisualState(position: node.position, xScale: 1.0, yScale: 1.0, alpha: 1.0)

            if animated {
                let group = SKAction.group([
                    .move(to: state.position, duration: duration),
                    .scaleX(to: state.xScale, duration: duration),
                    .scaleY(to: state.yScale, duration: duration),
                    .fadeAlpha(to: state.alpha, duration: duration)
                ])
                node.run(group)
            } else {
                node.position = state.position
                node.xScale = state.xScale
                node.yScale = state.yScale
                node.alpha = state.alpha
            }
        }

        if animated {
            run(.sequence([.wait(forDuration: duration), .run(completion)]), withKey: "overlay-expand")
        } else {
            completion()
        }
    }

    private func collapseScale(for node: SKNode, targetSize: CGSize) -> (x: CGFloat, y: CGFloat) {
        let sourceSize = node.calculateAccumulatedFrame().size
        guard sourceSize.width > 0.001,
              sourceSize.height > 0.001,
              targetSize.width > 0.001,
              targetSize.height > 0.001 else {
            return (1.0, 1.0)
        }

        let widthScale = targetSize.width / sourceSize.width
        let heightScale = targetSize.height / sourceSize.height
        return (widthScale, heightScale)
    }

    private func updateEmuFrameCallbackRegistration() {
        if let emuFrameActionToken {
            RetroArchX.shared().removeEmuPrevFrameAction(forToken: emuFrameActionToken)
            self.emuFrameActionToken = nil
        }

        guard actionButtons.isEmpty == false else {
            return
        }

        emuFrameActionToken = RetroArchX.shared().addEmuPrevFrameAction { [weak self] in
            guard let self else { return }
            self.actionButtons.forEach { $0.updateTurboFrameOutput() }
        }
    }
}
