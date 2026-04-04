//
//  GameOverlayActionButton.swift
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

final class GameOverlayActionButton: SKNode, GameOverlayElementLayout {
    // MARK: - Constants
    private let period: Int = 4
    private let duty: Int = 2
    private let longPressThreshold: TimeInterval = 0.15

    // MARK: - Properties

    private(set) var isTurboSupported: Bool {
        didSet {
            if !isTurboSupported {
                // Do not clear trackingTouch here; otherwise, if turbo is disabled while touching,
                // touchesEnded will no longer be able to release the button.
                resetTurboState(preservingTrackingTouch: true)

                // Switching from turbo -> normal should reflect current touch state immediately.
                emit(isTouching)
            }
        }
    }

    private var autoKeepTurbo: Bool
    private var shape: GameOverlayButtonShape?
    private let shapeNode = SKShapeNode()
    private let contentNode = SKNode()
    private var labelNode: SKLabelNode?
    private var psIconNode: SKNode?
    private var psIconShapeNodes: [SKShapeNode] = []

    // Turbo State Tracking
    private var trackingTouch: ObjectIdentifier?
    private var touchBeganAt: TimeInterval?
    private var touchStartedWithTurboEnabled: Bool = false
    private var frameIndex: Int = 0
    private var lastEmittedValue: Bool = false

    private(set) var isTouching: Bool = false {
        didSet {
            guard isTouching != oldValue else { return }
            updateAppearance()
            updateContentScale(animated: true)

            // If turbo is not enabled for this button, send plain down/up events.
            if !isTurboSupported {
                emit(isTouching)
            }
        }
    }

    private(set) var isTurboLatched: Bool = false {
        didSet {
            guard isTurboLatched != oldValue else { return }
            syncTurboStateChange()
        }
    }

    private(set) var isTurboHolding: Bool = false {
        didSet {
            guard isTurboHolding != oldValue else { return }
            syncTurboStateChange()
        }
    }

    var isTurboActive: Bool {
        isTurboSupported && (isTurboLatched || isTurboHolding)
    }

    var size: CGSize {
        shape?.size ?? .zero
    }

    override var frame: CGRect {
        let size = size
        let pos = CGPoint(x: position.x - size.width * 0.5, y: position.y - size.height * 0.5)
        return CGRect(origin: pos, size: size)
    }

    private(set) var element: GamePageOverlayElement
    private let joypadCodes: [RetroArchJoypadCode]
    private let digitalChangeHandler: GameOverlayButtonDigitalChanged?

    // MARK: - Init
    init(element: GamePageOverlayElement, isTurboSupported: Bool, autoKeepTurbo: Bool, digitalChangeHandler: GameOverlayButtonDigitalChanged?) {
        self.element = element
        self.joypadCodes = element.binds.map({ $0.code })
        self.autoKeepTurbo = autoKeepTurbo
        self.isTurboSupported = isTurboSupported
        self.digitalChangeHandler = digitalChangeHandler
        super.init()

        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true

        setupNodes()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Logic Updates

    // Must be called by outer emu frame loop.
    func updateTurboFrameOutput() {
        // 1. If turbo is active (either via Latched or Holding state)
        if isTurboActive {
            let nextValue = frameIndex < duty
            frameIndex = (frameIndex + 1) % period
            emit(nextValue)
            return
        }

        // 2. If turbo is not active, but the user is physically touching the button (Plain Mode)
        if isTouching {
            // Let the isTouching logic handle emit(true), we do nothing here
            // to prevent turbo reset from overriding the solid press.
            return
        }

        // 3. Reset to false only when there is no active turbo and no physical touch
        if isTurboSupported {
            frameIndex = 0
            emit(false)
        }
    }

    /// Enable/disable turbo behavior at runtime (e.g. a global lightning toggle).
    func setTurboEnabled(_ enabled: Bool, autoKeepTurbo: Bool? = nil) {
        if let autoKeepTurbo {
            self.autoKeepTurbo = autoKeepTurbo
        }

        guard enabled != isTurboSupported else { return }

        isTurboSupported = enabled

        if enabled {
            // If user enables turbo while finger is down, enter turbo-hold immediately.
            if isTouching {
                touchBeganAt = CACurrentMediaTime()
                touchStartedWithTurboEnabled = false
                isTurboHolding = true
            }
        } else {
            // Switching from turbo -> normal should reflect current touch state immediately.
            emit(isTouching)
        }
    }

    private func resetTurboState(preservingTrackingTouch: Bool) {
        if !preservingTrackingTouch {
            trackingTouch = nil
        }
        touchBeganAt = nil
        isTurboHolding = false
        isTurboLatched = false
        frameIndex = 0
        emit(false)
        updateAppearance()
    }

    private func emit(_ value: Bool) {
        guard lastEmittedValue != value else { return }
        lastEmittedValue = value
        joypadCodes.forEach({ digitalChangeHandler?($0, value) })
    }

    private func syncTurboStateChange() {
        frameIndex = 0
        if !isTurboActive {
            emit(false)
        }
        updateAppearance()
    }

    // MARK: - Layout
    func updateRect(_ rect: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        if let s = element.geometry.shape {
            let ss = GameOverlayButtonShape.makeShape(from: s, rect: rect)
            if ss != shape {
                updateShape(ss)
            }
        }

        let newPosition = CGPoint(x: rect.midX, y: rect.midY)
        if shouldUpdatePosition {
            self.position = newPosition
        }
        return newPosition
    }

    // MARK: - Touch event process
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingTouch == nil, let touch = touches.first else { return }

        trackingTouch = ObjectIdentifier(touch)
        isTouching = true

        if isTurboSupported {
            touchBeganAt = CACurrentMediaTime()
            touchStartedWithTurboEnabled = isTurboActive
            if !touchStartedWithTurboEnabled {
                isTurboHolding = true
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracking = trackingTouch else { return }
        if touches.contains(where: { ObjectIdentifier($0) == tracking }) {
            isTouching = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouchEnd(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouchEnd(touches, cancelled: true)
    }

    private func handleTouchEnd(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let tracking = trackingTouch, touches.contains(where: { ObjectIdentifier($0) == tracking }) else { return }

        let beganAt = touchBeganAt
        let startedWithTurbo = touchStartedWithTurboEnabled

        self.trackingTouch = nil
        self.isTouching = false

        guard isTurboSupported else { return }

        self.isTurboHolding = false
        self.touchBeganAt = nil

        if cancelled {
            isTurboLatched = false
            return
        }

        if let beganAt = beganAt {
            let elapsed = CACurrentMediaTime() - beganAt
            if startedWithTurbo {
                isTurboLatched = false
            } else if autoKeepTurbo {
                isTurboLatched = elapsed < longPressThreshold
            }
        }
    }
}

// MARK: - Appearance Extension
extension GameOverlayActionButton {
    private func setupNodes() {
        contentNode.zPosition = 1
        addChild(contentNode)

        if let psActionButtonIcon = element.psActionButtonIcon {
            let iconNode = makePSActionIconNode(for: psActionButtonIcon)
            iconNode.zPosition = 1
            contentNode.addChild(iconNode)
            self.psIconNode = iconNode
        } else if let title = element.title {
            let lNode = SKLabelNode(text: title)
            lNode.fontName = "Helvetica"
            lNode.fontColor = SKColor(white: 1.0, alpha: 0.75)
            lNode.verticalAlignmentMode = .center
            lNode.horizontalAlignmentMode = .center
            lNode.zPosition = 1
            contentNode.addChild(lNode)
            self.labelNode = lNode
        }

        shapeNode.strokeColor = SKColor.white
        shapeNode.lineWidth = 2
        shapeNode.zPosition = 0
        shapeNode.fillColor = SKColor(white: 1, alpha: 0.1)
        addChild(shapeNode)
    }

    private func updateAppearance() {
        let fillColor: SKColor
        let foregroundAlpha: CGFloat

        if isTouching {
            fillColor = SKColor(white: 1.0, alpha: 0.4)
            foregroundAlpha = 1.0
        } else if isTurboActive {
            // Turbo active (latched or holding) but not touching.
            fillColor = SKColor(white: 1.0, alpha: 0.25)
            foregroundAlpha = 0.95
        } else {
            fillColor = SKColor(white: 1.0, alpha: 0.1)
            foregroundAlpha = 0.75
        }

        shapeNode.fillColor = fillColor
        labelNode?.fontColor = SKColor(white: 1.0, alpha: foregroundAlpha)
        updatePSIconAppearance(alpha: foregroundAlpha)
    }

    private func updateShape(_ s: GameOverlayButtonShape) {
        shape = s
        shapeNode.path = s.path
        if let labelNode = labelNode {
            labelNode.fontSize = s.fontSize
            s.fixLabelPosition(labelNode)
        }
        if let psIconNode = psIconNode, let psActionButtonIcon = element.psActionButtonIcon {
            psIconNode.position = .zero
            let targetExtent = min(s.size.width, s.size.height) * psActionButtonIcon.scaleFactor
            let scale = targetExtent / GameOverlayPSActionButtonIcon.artboardSize
            psIconNode.setScale(scale)
        }
    }

    private func makePSActionIconNode(for icon: GameOverlayPSActionButtonIcon) -> SKNode {
        let container = SKNode()
        let nodes = icon.makeShapeNodes()
        nodes.forEach {
            $0.zPosition = 1
            container.addChild($0)
        }
        self.psIconShapeNodes = nodes
        updatePSIconAppearance(alpha: 0.75)
        return container
    }

    private func updatePSIconAppearance(alpha: CGFloat) {
        let strokeColor = SKColor(white: 1.0, alpha: alpha)
        psIconShapeNodes.forEach {
            $0.strokeColor = strokeColor
        }
    }

    private func updateContentScale(animated: Bool) {
        let targetScale: CGFloat = isTouching ? 1.12 : 1.0
        contentNode.removeAction(forKey: "touch-scale")

        guard animated else {
            contentNode.setScale(targetScale)
            return
        }

        let action = SKAction.scale(to: targetScale, duration: 0.10)
        action.timingMode = .easeOut
        contentNode.run(action, withKey: "touch-scale")
    }
}

private extension GameOverlayPSActionButtonIcon {
    static let artboardSize: CGFloat = 100

    var scaleFactor: CGFloat {
        switch self {
        case .triangle:
            return 0.60
        case .circle:
            return 0.62
        case .cross:
            return 0.58
        case .square:
            return 0.58
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .triangle:
            return 7
        case .circle:
            return 7
        case .cross:
            return 9
        case .square:
            return 7.5
        }
    }

    func makeShapeNodes() -> [SKShapeNode] {
        switch self {
        case .triangle:
            return [Self.makeShapeNode(path: trianglePath, lineWidth: lineWidth)]
        case .circle:
            return [Self.makeShapeNode(path: circlePath, lineWidth: lineWidth)]
        case .cross:
            return [Self.makeShapeNode(path: crossPathA, lineWidth: lineWidth), Self.makeShapeNode(path: crossPathB, lineWidth: lineWidth)]
        case .square:
            return [Self.makeShapeNode(path: squarePath, lineWidth: lineWidth)]
        }
    }

    private static func makeShapeNode(path: CGPath, lineWidth: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.lineWidth = lineWidth
        node.lineJoin = .round
        node.fillColor = .clear
        return node
    }

    private var trianglePath: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 34))
        path.addLine(to: CGPoint(x: -32, y: -26))
        path.addLine(to: CGPoint(x: 32, y: -26))
        path.closeSubpath()
        return path
    }

    private var circlePath: CGPath {
        CGPath(ellipseIn: CGRect(x: -30, y: -30, width: 60, height: 60), transform: nil)
    }

    private var crossPathA: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -26, y: -26))
        path.addLine(to: CGPoint(x: 26, y: 26))
        return path
    }

    private var crossPathB: CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -26, y: 26))
        path.addLine(to: CGPoint(x: 26, y: -26))
        return path
    }

    private var squarePath: CGPath {
        CGPath(rect: CGRect(x: -28, y: -28, width: 56, height: 56), transform: nil)
    }
}

