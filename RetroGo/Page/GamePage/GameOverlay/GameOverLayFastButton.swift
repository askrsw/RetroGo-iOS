//
//  GameOverLayFastButton.swift
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

final class GameOverLayFastButton: SKNode, GameOverlayElementLayout {
    // MARK: - Constants
    private let longPressThreshold: TimeInterval = 0.15

    // MARK: - Properties
    private var shape: GameOverlayButtonShape?
    private let shapeNode = SKShapeNode()
    private let contentNode = SKNode()
    private let leftChevronNode = SKShapeNode()
    private let rightChevronNode = SKShapeNode()

    private var trackingTouch: ObjectIdentifier?
    private var touchBeganAt: TimeInterval?

    private(set) var isTouching: Bool = false {
        didSet {
            guard isTouching != oldValue else { return }
            updateAppearance()
            updateContentScale(animated: true)
        }
    }

    private(set) var isFastForwardEnabled: Bool = false {
        didSet {
            guard isFastForwardEnabled != oldValue else { return }
            updateAppearance()
        }
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
    private let fastStateChangeHander: GameOverlayFastStateChanged?

    // MARK: - Init
    init(element: GamePageOverlayElement, fastStateChangeHander: GameOverlayFastStateChanged?) {
        self.element = element
        self.fastStateChangeHander = fastStateChangeHander
        super.init()

        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true

        setupNodes()
        updateAppearance()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            position = newPosition
        }
        return newPosition
    }

    // MARK: - Touch event process
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingTouch == nil, let touch = touches.first else { return }

        trackingTouch = ObjectIdentifier(touch)
        touchBeganAt = CACurrentMediaTime()
        isTouching = true
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
}

// MARK: - Appearance Extension
extension GameOverLayFastButton {
    private func setupNodes() {
        contentNode.zPosition = 1
        addChild(contentNode)

        [leftChevronNode, rightChevronNode].forEach {
            $0.lineWidth = 0
            $0.strokeColor = .clear
            $0.fillColor = .white
            $0.zPosition = 1
            contentNode.addChild($0)
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
            fillColor = SKColor(white: 1.0, alpha: 0.55)
            foregroundAlpha = 1.0
        } else if isFastForwardEnabled {
            fillColor = SKColor(white: 1.0, alpha: 0.35)
            foregroundAlpha = 0.95
        } else {
            fillColor = SKColor.clear
            foregroundAlpha = 0.75
        }

        shapeNode.fillColor = fillColor
        leftChevronNode.alpha = foregroundAlpha
        rightChevronNode.alpha = foregroundAlpha
    }

    private func updateShape(_ s: GameOverlayButtonShape) {
        shape = s
        shapeNode.path = s.path
        updateForwardIcon(size: s.size)
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

    private func handleTouchEnd(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let tracking = trackingTouch, touches.contains(where: { ObjectIdentifier($0) == tracking }) else { return }

        let beganAt = touchBeganAt
        trackingTouch = nil
        touchBeganAt = nil
        isTouching = false

        guard !cancelled else { return }

        let elapsed = beganAt.map { CACurrentMediaTime() - $0 } ?? 0
        if elapsed >= longPressThreshold {
            handleLongPress()
            return
        }

        isFastForwardEnabled.toggle()
        emitStateChange()
    }

    private func updateForwardIcon(size: CGSize) {
        let iconWidth = min(size.width, size.height) * 0.55
        let iconHeight = iconWidth * 0.9
        let chevronWidth = iconWidth * 0.42
        let chevronGap = iconWidth * 0.10

        leftChevronNode.path = makeForwardChevronPath(width: chevronWidth, height: iconHeight)
        rightChevronNode.path = makeForwardChevronPath(width: chevronWidth, height: iconHeight)

        let centerOffset = (chevronWidth + chevronGap) * 0.5
        leftChevronNode.position = CGPoint(x: -centerOffset, y: 0)
        rightChevronNode.position = CGPoint(x: centerOffset, y: 0)
    }

    private func makeForwardChevronPath(width: CGFloat, height: CGFloat) -> CGPath {
        let halfWidth = width * 0.5
        let halfHeight = height * 0.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfWidth, y: -halfHeight))
        path.addLine(to: CGPoint(x: halfWidth, y: 0))
        path.addLine(to: CGPoint(x: -halfWidth, y: halfHeight))
        path.closeSubpath()
        return path
    }
}

// MARK: - State Extension
extension GameOverLayFastButton {
    private func emitStateChange() {
        fastStateChangeHander?(isFastForwardEnabled)
    }

    private func handleLongPress() {
        // Reserved for the fast-forward multiplier popup menu.
    }
}
