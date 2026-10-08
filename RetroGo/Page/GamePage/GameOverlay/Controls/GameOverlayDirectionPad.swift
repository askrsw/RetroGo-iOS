//
//  GameOverlayDirectionPad.swift
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

enum GameOverlayDirectionMask {
    static let none: UInt  = 0
    static let left: UInt  = 0b1
    static let up: UInt    = 0b10
    static let right: UInt = 0b100
    static let down: UInt  = 0b1000
}

final class GameOverlayDirectionPad: SKNode, GameOverlayElementLayout {
    enum Direction {
        case up, right, down, left
    }

    private(set) var radius: CGFloat = 0

    private let shape  = SKShapeNode()
    private let circle = SKShapeNode()

    private let up    = SKShapeNode()
    private let right = SKShapeNode()
    private let down  = SKShapeNode()
    private let left  = SKShapeNode()

    private(set) var status: UInt = 0 {
        didSet {
            if status == oldValue {
                return
            }

            let inactive = theme.primaryColor(alpha: 0.5)
            let active = theme.primaryColor(alpha: 1)
            up.fillColor = inactive
            right.fillColor = inactive
            down.fillColor = inactive
            left.fillColor = inactive

            if status & GameOverlayDirectionMask.up > 0 {
                up.fillColor = active
            }
            if status & GameOverlayDirectionMask.right > 0 {
                right.fillColor = active
            }
            if status & GameOverlayDirectionMask.down > 0 {
                down.fillColor = active
            }
            if status & GameOverlayDirectionMask.left > 0 {
                left.fillColor = active
            }

            digitalHandler?(.right, status & GameOverlayDirectionMask.right > 0)
            digitalHandler?(.down, status & GameOverlayDirectionMask.down > 0)
            digitalHandler?(.left, status & GameOverlayDirectionMask.left > 0)
            digitalHandler?(.up, status & GameOverlayDirectionMask.up > 0)
        }
    }

    private var upRect: CGRect    = .zero
    private var rightRect: CGRect = .zero
    private var downRect: CGRect  = .zero
    private var leftRect: CGRect  = .zero
    private var upRightRect: CGRect = .zero
    private var downRightRect: CGRect = .zero
    private var downLeftRect: CGRect = .zero
    private var upLeftRect: CGRect = .zero

    private(set) var element: GamePageOverlayElement
    let allowsDiagonalInput: Bool
    let digitalHandler: GameOverlayButtonDigitalChanged?
    private let theme: GameOverlayTheme
    private var activeTouch: UITouch?

    init(element: GamePageOverlayElement, allowsDiagonalInput: Bool = true, theme: GameOverlayTheme = .default, digitalHandler: GameOverlayButtonDigitalChanged?) {
        self.element = element
        self.allowsDiagonalInput = allowsDiagonalInput
        self.digitalHandler = digitalHandler
        self.theme = theme
        super.init()

        name = element.id
        isUserInteractionEnabled = true

        shape.strokeColor = theme.primaryColor
        shape.lineWidth = 2
        addChild(shape)

        circle.fillColor = theme.accentColor
        circle.lineWidth = 0
        addChild(circle)

        up.fillColor = theme.primaryColor(alpha: 0.5)
        up.lineWidth = 0
        shape.addChild(up)

        right.fillColor = theme.primaryColor(alpha: 0.5)
        right.lineWidth = 0
        shape.addChild(right)

        down.fillColor = theme.primaryColor(alpha: 0.5)
        down.lineWidth = 0
        shape.addChild(down)

        left.fillColor = theme.primaryColor(alpha: 0.5)
        left.lineWidth = 0
        shape.addChild(left)
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

    func getButtonRect(_ dir: Direction) -> CGRect {
        let length = radius
        let delta = length * 0.32
        let size: CGSize
        let pos: CGPoint

        switch dir {
            case .up:
                pos = CGPoint(x: -delta, y: delta * 3)
                size = CGSize(width: delta * 2, height: length - delta)
            case .right:
                pos = CGPoint(x: delta, y: delta)
                size = CGSize(width: length - delta, height: delta * 2)
            case .down:
                pos = CGPoint(x: -delta, y: -delta)
                size = CGSize(width: delta * 2, height: length - delta)
            case .left:
                pos = CGPoint(x: -length, y: delta)
                size = CGSize(width: delta * 2, height: length - delta)
        }

        return CGRect(origin: pos, size: size)
    }

    // MARK: - Touch event process

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        updateStatus(for: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        updateStatus(for: activeTouch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        self.activeTouch = nil
        status = GameOverlayDirectionMask.none
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        self.activeTouch = nil
        status = GameOverlayDirectionMask.none
    }
}

extension GameOverlayDirectionPad {
    func applyBindingBubbleTouch(_ touching: Bool, actionId: String) {
        switch actionId {
        case "up":
            digitalHandler?(.up, touching)
        case "right":
            digitalHandler?(.right, touching)
        case "down":
            digitalHandler?(.down, touching)
        case "left":
            digitalHandler?(.left, touching)
        default:
            break
        }
    }

    private func updateStatus(for touchPoint: CGPoint) {
        if allowsDiagonalInput {
            if upRightRect.contains(touchPoint) {
                status = GameOverlayDirectionMask.up | GameOverlayDirectionMask.right
                return
            }
            if downRightRect.contains(touchPoint) {
                status = GameOverlayDirectionMask.down | GameOverlayDirectionMask.right
                return
            }
            if downLeftRect.contains(touchPoint) {
                status = GameOverlayDirectionMask.down | GameOverlayDirectionMask.left
                return
            }
            if upLeftRect.contains(touchPoint) {
                status = GameOverlayDirectionMask.up | GameOverlayDirectionMask.left
                return
            }
        }

        if upRect.contains(touchPoint) {
            status = GameOverlayDirectionMask.up
            return
        }
        if rightRect.contains(touchPoint) {
            status = GameOverlayDirectionMask.right
            return
        }
        if downRect.contains(touchPoint) {
            status = GameOverlayDirectionMask.down
            return
        }
        if leftRect.contains(touchPoint) {
            status = GameOverlayDirectionMask.left
            return
        }

        // No precise zone matched. If the finger has drifted beyond the pad, keep
        // producing a direction from the angle so input doesn't drop; inside the
        // pad (a gap or the dead center) stay neutral as before.
        if touchPoint.x * touchPoint.x + touchPoint.y * touchPoint.y > radius * radius {
            status = directionMask(forAngleAt: touchPoint)
        } else {
            status = GameOverlayDirectionMask.none
        }
    }

    private func directionMask(forAngleAt p: CGPoint) -> UInt {
        let angle = atan2(p.y, p.x)
        let pi = CGFloat.pi
        if allowsDiagonalInput {
            // Eight 45° sectors centered on each cardinal / diagonal direction.
            if angle >= -pi / 8 && angle < pi / 8 { return GameOverlayDirectionMask.right }
            if angle >= pi / 8 && angle < 3 * pi / 8 { return GameOverlayDirectionMask.up | GameOverlayDirectionMask.right }
            if angle >= 3 * pi / 8 && angle < 5 * pi / 8 { return GameOverlayDirectionMask.up }
            if angle >= 5 * pi / 8 && angle < 7 * pi / 8 { return GameOverlayDirectionMask.up | GameOverlayDirectionMask.left }
            if angle >= 7 * pi / 8 || angle < -7 * pi / 8 { return GameOverlayDirectionMask.left }
            if angle >= -7 * pi / 8 && angle < -5 * pi / 8 { return GameOverlayDirectionMask.down | GameOverlayDirectionMask.left }
            if angle >= -5 * pi / 8 && angle < -3 * pi / 8 { return GameOverlayDirectionMask.down }
            return GameOverlayDirectionMask.down | GameOverlayDirectionMask.right
        } else {
            // Four 90° quadrants.
            if angle >= -pi / 4 && angle < pi / 4 { return GameOverlayDirectionMask.right }
            if angle >= pi / 4 && angle < 3 * pi / 4 { return GameOverlayDirectionMask.up }
            if angle >= 3 * pi / 4 || angle < -3 * pi / 4 { return GameOverlayDirectionMask.left }
            return GameOverlayDirectionMask.down
        }
    }

    private func updateRadius(_ radius: CGFloat) {
        self.radius = radius

        let shapePath = makeShpae(radius)
        shape.path = shapePath.cgPath

        let circleRadius = radius * 0.15 * 0.9
        let circleRect = CGRect(x: -circleRadius, y: -circleRadius, width: circleRadius * 2, height: circleRadius * 2)
        let circlePath = UIBezierPath(ovalIn: circleRect)
        circle.path = circlePath.cgPath

        let triangle = makeTriangle(radius)
        up.path = triangle.cgPath

        let transform = CGAffineTransform(rotationAngle: .pi * -0.5)
        triangle.apply(transform)
        right.path = triangle.cgPath

        triangle.apply(transform)
        down.path = triangle.cgPath

        triangle.apply(transform)
        left.path = triangle.cgPath

        let length = radius
        let delta = length * 0.32
        upRect    = CGRect(x: -delta, y: delta, width: delta * 2, height: length - delta)
        rightRect = CGRect(x: delta, y: -delta, width: length - delta, height: delta * 2)
        downRect  = CGRect(x: -delta, y: -length, width: delta * 2, height: length - delta)
        leftRect  = CGRect(x: -length, y: -delta, width: delta * 2, height: length - delta)

        let diagSize = delta * 2
        upRightRect = CGRect(x: delta, y: delta, width: diagSize, height: diagSize)
        downRightRect = CGRect(x: delta, y: -delta - diagSize, width: diagSize, height: diagSize)
        downLeftRect = CGRect(x: -delta - diagSize, y: -delta - diagSize, width: diagSize, height: diagSize)
        upLeftRect = CGRect(x: -delta - diagSize, y: delta, width: diagSize, height: diagSize)
    }

    private func makeTriangle(_ radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let length = radius * 0.875
        let delta = length * 0.35

        let pos1 = CGPoint(x: 0, y: length * 0.95)
        path.move(to: pos1)

        let pos2 = CGPoint(x: delta * 0.5, y: length * 0.95 - delta * sin(.pi / 3.0))
        path.addLine(to: pos2)

        let pos3 = CGPoint(x: -delta * 0.5, y: pos2.y)
        path.addLine(to: pos3)

        path.close()

        return path
    }

    private func makeShpae(_ radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let length = radius
        let delta = length * 0.32
        let cr = length * 0.1

        // 1
        path.move(to: CGPoint(x: length, y: delta - cr))
        path.addArc(withCenter: CGPoint(x: length - cr, y: delta - cr), radius: cr, startAngle: 0, endAngle: CGFloat.pi * 0.5, clockwise: true)

        // 2
        path.addLine(to: CGPoint(x: delta + cr, y: delta))
        path.addArc(withCenter: CGPoint(x: delta + cr, y: delta + cr), radius: cr, startAngle: .pi * 1.5, endAngle: .pi, clockwise: false)

        // 3
        path.addLine(to: CGPoint(x: delta, y: length - cr))
        path.addArc(withCenter: CGPoint(x: delta - cr, y: length - cr), radius: cr, startAngle: 0, endAngle: CGFloat.pi * 0.5, clockwise: true)

        // 4
        path.addLine(to: CGPoint(x: -delta + cr, y: length))
        path.addArc(withCenter: CGPoint(x: -delta + cr, y: length - cr), radius: cr, startAngle: CGFloat.pi * 0.5, endAngle: .pi, clockwise: true)

        // 5
        path.addLine(to: CGPoint(x: -delta, y: delta + cr))
        path.addArc(withCenter: CGPoint(x: -delta - cr, y: delta + cr), radius: cr, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)

        // 6
        path.addLine(to: CGPoint(x: -length + cr, y: delta))
        path.addArc(withCenter: CGPoint(x: -length + cr, y: delta - cr), radius: cr, startAngle: .pi * 0.5, endAngle: .pi, clockwise: true)

        // 7
        path.addLine(to: CGPoint(x: -length, y: -delta + cr))
        path.addArc(withCenter: CGPoint(x: -length + cr, y: -delta + cr), radius: cr, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)

        // 8
        path.addLine(to: CGPoint(x: -delta - cr, y: -delta))
        path.addArc(withCenter: CGPoint(x: -delta - cr, y: -delta - cr), radius: cr, startAngle: .pi * 0.5, endAngle: 0, clockwise: false)

        // 9
        path.addLine(to: CGPoint(x: -delta, y: -length + cr))
        path.addArc(withCenter: CGPoint(x: -delta + cr, y: -length + cr), radius: cr, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)

        // 10
        path.addLine(to: CGPoint(x: delta - cr, y: -length))
        path.addArc(withCenter: CGPoint(x: delta - cr, y: -length + cr), radius: cr, startAngle: .pi * 1.5, endAngle: 0, clockwise: true)

        // 11
        path.addLine(to: CGPoint(x: delta, y: -delta - cr))
        path.addArc(withCenter: CGPoint(x: delta + cr, y: -delta - cr), radius: cr, startAngle: .pi, endAngle: .pi * 0.5, clockwise: false)

        // 12
        path.addLine(to: CGPoint(x: length - cr, y: -delta))
        path.addArc(withCenter: CGPoint(x: length - cr, y: -delta + cr), radius: cr, startAngle: .pi * 1.5, endAngle: 0, clockwise: true)

        path.close()

        return path
    }
}
