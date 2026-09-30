//
//  GameOverlayArcadeLayoutButton.swift
//  RetroGo
//
//  Copyright © 2026 haharsw. All rights reserved.
//
//  This file is part of RetroGo.
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SpriteKit

/// Shows the layout available on the next tap, matching RetroArch's arcade overlay.
final class GameOverlayArcadeLayoutButton: SKNode, GameOverlayElementLayout {
    let element: GamePageOverlayElement
    private let theme: GameOverlayTheme
    private let handler: () -> Void
    private let ringNode = SKShapeNode()
    private let dotsNode = SKNode()
    private var diameter: CGFloat = 0
    private var usesFourButtons = false
    private var trackingTouch: ObjectIdentifier?

    init(element: GamePageOverlayElement, theme: GameOverlayTheme = .default, handler: @escaping () -> Void) {
        self.element = element
        self.theme = theme
        self.handler = handler
        super.init()
        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true
        ringNode.strokeColor = theme.primaryColor
        ringNode.lineWidth = 2
        ringNode.fillColor = .clear
        dotsNode.alpha = theme.normalContentAlpha
        dotsNode.zPosition = 1
        addChild(ringNode)
        addChild(dotsNode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRect(_ rect: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        let newDiameter = min(rect.width, rect.height)
        if diameter != newDiameter {
            diameter = newDiameter
            ringNode.path = CGPath(ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter), transform: nil)
            updateDots()
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if shouldUpdatePosition { position = center }
        return center
    }

    func applyFourButtonLayout(_ enabled: Bool) {
        usesFourButtons = enabled
        updateDots()
    }

    private func updateDots() {
        dotsNode.removeAllChildren()
        let points: [CGPoint]
        if usesFourButtons {
            points = [-0.22, 0.0, 0.22].flatMap { x in
                [-0.13, 0.13].map { y in CGPoint(x: x, y: y) }
            }
        } else {
            points = [CGPoint(x: 0, y: 0.24), CGPoint(x: -0.24, y: 0),
                      CGPoint(x: 0.24, y: 0), CGPoint(x: 0, y: -0.24)]
        }
        for point in points {
            let dot = SKShapeNode(circleOfRadius: diameter * 0.075)
            dot.position = CGPoint(x: point.x * diameter, y: point.y * diameter)
            dot.fillColor = theme.primaryColor
            dot.strokeColor = .clear
            dot.lineWidth = 0
            dotsNode.addChild(dot)
        }
    }

    private func setPressed(_ pressed: Bool) {
        ringNode.fillColor = pressed ? theme.primaryColor(alpha: theme.emphasizedPressedFillAlpha) : .clear
        dotsNode.alpha = pressed ? theme.pressedContentAlpha : theme.normalContentAlpha
        dotsNode.removeAction(forKey: "touch-scale")
        let action = SKAction.scale(to: pressed ? 1.12 : 1.0, duration: 0.10)
        action.timingMode = .easeOut
        dotsNode.run(action, withKey: "touch-scale")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingTouch == nil, let touch = touches.first else { return }
        trackingTouch = ObjectIdentifier(touch)
        setPressed(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let trackingTouch, let touch = touches.first(where: { ObjectIdentifier($0) == trackingTouch }) else { return }
        self.trackingTouch = nil
        setPressed(false)
        let location = touch.location(in: self)
        guard hypot(location.x, location.y) <= diameter / 2 else { return }
        handler()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let trackingTouch, touches.contains(where: { ObjectIdentifier($0) == trackingTouch }) else { return }
        self.trackingTouch = nil
        setPressed(false)
    }
}
