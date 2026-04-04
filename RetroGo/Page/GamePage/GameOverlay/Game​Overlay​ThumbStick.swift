//
//  Game​Overlay​ThumbStick.swift
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

final class Game​Overlay​ThumbStick: SKNode, GameOverlayElementLayout {
    private(set) var radius: CGFloat = 0
    private var smallRaidusSquare: CGFloat = 0

    private let circlePannel = SKShapeNode()
    private let indicator  = SKShapeNode()
    private let decoration = SKShapeNode()

    private let originalStateAction = SKAction.move(to: .zero, duration: 0)

    private var touching: Bool = false {
        didSet {
            guard touching != oldValue else { return }
            if touching {
                circlePannel.fillColor = SKColor(white: 0.95, alpha: 0.35)
                decoration.fillColor = .white
            } else {
                indicator.run(originalStateAction, withKey: "stateChange")
                circlePannel.fillColor = SKColor(white: 0.95, alpha: 0.2)
                decoration.fillColor = SKColor(white: 0.95, alpha: 0.35)
                status = GameOverlayDirectionMask.none
            }
        }
    }

    private(set) var status: UInt = 0 {
        didSet {
            if status == oldValue {
                return
            }

            if analogHandler == nil, let digitalHandler = digitalHandler {
                digitalHandler(.right, status & GameOverlayDirectionMask.right > 0)
                digitalHandler(.down, status & GameOverlayDirectionMask.down > 0)
                digitalHandler(.left, status & GameOverlayDirectionMask.left > 0)
                digitalHandler(.up, status & GameOverlayDirectionMask.up > 0)
            }
        }
    }

    private(set) var element: GamePageOverlayElement
    private let digitalHandler: GameOverlayButtonDigitalChanged?
    private let analogHandler: GameOverlayDirectionAnalogChanged?

    init(element: GamePageOverlayElement, digitalHandler: GameOverlayButtonDigitalChanged? = nil, analogHandler: GameOverlayDirectionAnalogChanged? = nil) {
        self.element = element
        self.digitalHandler = digitalHandler
        self.analogHandler = analogHandler
        super.init()

        name = element.id
        isUserInteractionEnabled = true

        circlePannel.fillColor = SKColor(white: 0.95, alpha: 0.2)
        circlePannel.strokeColor = SKColor.white
        circlePannel.lineWidth = 2
        addChild(circlePannel)

        indicator.fillColor = .mainColor
        indicator.lineWidth = 0
        circlePannel.addChild(indicator)

        decoration.fillColor = SKColor(white: 0.95, alpha: 0.35)
        decoration.lineWidth = 0
        addChild(decoration)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRect(_ r: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        let radius = r.width * 0.5
        if self.radius != radius {
            updateRadius(radius)
        }

        let newPosition = CGPoint(x: r.midX, y: r.midY)
        if shouldUpdatePosition {
            self.position = newPosition
        }
        return newPosition
    }

    // MARK: - Touch event process

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            touching = true

            let touchPoint = touch.location(in: self)
            indicator.position = touchPoint

            if digitalHandler != nil, analogHandler == nil {
                updateDigitalIfNeeded(touchPoint)
            }

            if analogHandler != nil, digitalHandler == nil {
                updateAnalogIfNeeded(touchPoint)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            touching = true

            let touchPoint = touch.location(in: self)
            indicator.position = touchPoint

            if digitalHandler != nil, analogHandler == nil {
                updateDigitalIfNeeded(touchPoint)
            }

            if analogHandler != nil, digitalHandler == nil {
                updateAnalogIfNeeded(touchPoint)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touching = false
        sendAnalogZeroIfNeeded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touching = false
        sendAnalogZeroIfNeeded()
    }
}

extension Game​Overlay​ThumbStick {
    private func updateRadius(_ radius: CGFloat) {
        self.radius = radius
        self.smallRaidusSquare = radius * 0.2 * radius * 0.2

        let circleRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        let circlePath = UIBezierPath(ovalIn: circleRect)
        circlePannel.path = circlePath.cgPath

        let indicatorRadius = radius * 0.175
        let indicatorRect = CGRect(x: -indicatorRadius, y: -indicatorRadius, width: indicatorRadius * 2, height: indicatorRadius * 2)
        let indicatorPath = UIBezierPath(ovalIn: indicatorRect)
        indicator.path = indicatorPath.cgPath

        let range = SKRange(lowerLimit: 0, upperLimit: radius)
        let indicatorConstraint = SKConstraint.distance(range, to: .zero)
        indicator.constraints = [indicatorConstraint]

        let path = makeDecorationNode()
        decoration.path = path.cgPath
    }

    private func makeDecorationNode() -> UIBezierPath {
        let delta: CGFloat = 12.0 * CGFloat.pi / 180
        let longR = radius * 1.125
        let path = UIBezierPath()
        let array: [CGFloat] = [0, 0.5, 1, 1.5]
        for index in array {
            let angle = index * CGFloat.pi - delta * 0.5

            let pos1 = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            path.move(to: pos1)

            // Add arc
            path.addArc(withCenter: .zero, radius: radius, startAngle: angle, endAngle: angle + delta, clockwise: true)

            let pos2 = CGPoint(x: longR * cos(angle + delta * 0.5), y: longR * sin(angle + delta * 0.5))
            path.addLine(to: pos2)
            path.addLine(to: pos1)
        }
        return path
    }

    private func updateDigitalIfNeeded(_ pos: CGPoint) {
        let sum = pos.x * pos.x + pos.y * pos.y
        if sum < smallRaidusSquare {
            status = GameOverlayDirectionMask.none
            return
        }

        let angle = atan2(pos.y, pos.x)
        let M_PI = CGFloat.pi
        if(-M_PI/6.0 <= angle && angle <= M_PI/6.0) {
            status = GameOverlayDirectionMask.right
        } else if(M_PI/6.0 <= angle && angle <= M_PI/3.0) {
            status = GameOverlayDirectionMask.right | GameOverlayDirectionMask.up
        } else if(M_PI/3.0 <= angle && angle <= 2 * M_PI/3.0) {
            status = GameOverlayDirectionMask.up
        } else if(2 * M_PI/3.0 <= angle && angle <= 5 * M_PI/6.0) {
            status = GameOverlayDirectionMask.left | GameOverlayDirectionMask.up
        } else if(angle >= 5 * M_PI/6.0 || angle <= -5 * M_PI/6.0) {
            status = GameOverlayDirectionMask.left
        } else if(-5 * M_PI/6.0 <= angle && angle <= -2 * M_PI/3.0) {
            status = GameOverlayDirectionMask.left | GameOverlayDirectionMask.down
        } else if(-2 * M_PI/3.0 <= angle && angle <= -M_PI/3.0) {
            status = GameOverlayDirectionMask.down
        } else {
            status = GameOverlayDirectionMask.right | GameOverlayDirectionMask.down
        }
    }

    private func updateAnalogIfNeeded(_ pos: CGPoint) {
        guard let analogHandler, digitalHandler == nil else { return }

        let sum = pos.x * pos.x + pos.y * pos.y
        if sum < smallRaidusSquare {
            analogHandler(0, 0)
            return
        }

        var x = pos.x
        var y = pos.y
        let length = sqrt(sum)
        if length > radius, length > 0 {
            let scale = radius / length
            x *= scale
            y *= scale
        }

        let normX = x / radius
        let normY = y / radius
        analogHandler(normX, -normY)
    }

    private func sendAnalogZeroIfNeeded() {
        guard let analogHandler, digitalHandler == nil else { return }
        analogHandler(0, 0)
    }
}
