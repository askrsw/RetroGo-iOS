//
//  GameOverlayN64CButton.swift
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

final class GameOverlayN64CButton: SKNode, GameOverlayElementLayout {
    enum ArrowDirection {
        case up, right, down, left
    }

    struct CodeMap {
        let up: RetroArchJoypadCode
        let right: RetroArchJoypadCode
        let down: RetroArchJoypadCode
        let left: RetroArchJoypadCode
        let modifier: RetroArchJoypadCode

        static let dpad = CodeMap(up: .up, right: .right, down: .down, left: .left, modifier: .none)
        static let n64C = CodeMap(up: .X, right: .A, down: .B, left: .Y, modifier: .R2)
    }

    private(set) var radius: CGFloat = 0
    private var buttonRadius: CGFloat = 0
    private var squareButtonRadius: CGFloat = 0
    private var comboSquareRadius: CGFloat = 0
    private var upCenter: CGPoint = .zero
    private var rightCenter: CGPoint = .zero
    private var downCenter: CGPoint = .zero
    private var leftCenter: CGPoint = .zero
    private var upRightCenter: CGPoint = .zero
    private var upLeftCenter: CGPoint = .zero
    private var downRightCenter: CGPoint = .zero
    private var downLeftCenter: CGPoint = .zero

    private let up = SKShapeNode()
    private let right = SKShapeNode()
    private let down = SKShapeNode()
    private let left = SKShapeNode()

    private let upTriangle = SKShapeNode()
    private let rightTriangle = SKShapeNode()
    private let downTriangle = SKShapeNode()
    private let leftTriangle = SKShapeNode()

    private var touchMasks: [ObjectIdentifier: UInt] = [:]

    private(set) var status: UInt = 0 {
        didSet {
            if status == oldValue {
                return
            }

            let circleActive = SKColor(white: 0.95, alpha: 0.35)
            let circleInactive = SKColor.clear

            let isUp = status & GameOverlayDirectionMask.up > 0
            let isRight = status & GameOverlayDirectionMask.right > 0
            let isDown = status & GameOverlayDirectionMask.down > 0
            let isLeft = status & GameOverlayDirectionMask.left > 0

            up.fillColor = isUp ? circleActive : circleInactive
            up.lineWidth = isUp ? 2.5 : 1
            right.fillColor = isRight ? circleActive : circleInactive
            right.lineWidth = isRight ? 2.5 : 1
            down.fillColor = isDown ? circleActive : circleInactive
            down.lineWidth = isDown ? 2.5 : 1
            left.fillColor = isLeft ? circleActive : circleInactive
            left.lineWidth = isLeft ? 2.5 : 1

            let wasAny = oldValue != GameOverlayDirectionMask.none
            let isAny = status != GameOverlayDirectionMask.none
            if wasAny != isAny {
                digitalHandler?(codes.modifier, isAny)
            }

            if (oldValue ^ status) & GameOverlayDirectionMask.right > 0 {
                digitalHandler?(codes.right, isRight)
            }
            if (oldValue ^ status) & GameOverlayDirectionMask.down > 0 {
                digitalHandler?(codes.down, isDown)
            }
            if (oldValue ^ status) & GameOverlayDirectionMask.left > 0 {
                digitalHandler?(codes.left, isLeft)
            }
            if (oldValue ^ status) & GameOverlayDirectionMask.up > 0 {
                digitalHandler?(codes.up, isUp)
            }
        }
    }

    private(set) var element: GamePageOverlayElement
    private let codes: CodeMap
    private let digitalHandler: GameOverlayButtonDigitalChanged?

    init(element: GamePageOverlayElement, codes: CodeMap = .n64C, digitalHandler: GameOverlayButtonDigitalChanged?) {
        self.element = element
        self.codes = codes
        self.digitalHandler = digitalHandler
        super.init()

        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true

        up.fillColor = .clear
        right.fillColor = .clear
        down.fillColor = .clear
        left.fillColor = .clear

        up.strokeColor = SKColor(white: 1.0, alpha: 0.7)
        right.strokeColor = SKColor(white: 1.0, alpha: 0.7)
        down.strokeColor = SKColor(white: 1.0, alpha: 0.7)
        left.strokeColor = SKColor(white: 1.0, alpha: 0.7)

        up.lineWidth = 1.5
        right.lineWidth = 1.5
        down.lineWidth = 1.5
        left.lineWidth = 1.5

        addChild(up)
        addChild(right)
        addChild(down)
        addChild(left)

        let triangleStroke = SKColor(white: 1.0, alpha: 0.75)
        let triangleFill = SKColor.white
        for triangle in [upTriangle, rightTriangle, downTriangle, leftTriangle] {
            triangle.strokeColor = triangleStroke
            triangle.lineWidth = 1.5
            triangle.fillColor = triangleFill
        }
        up.addChild(upTriangle)
        right.addChild(rightTriangle)
        down.addChild(downTriangle)
        left.addChild(leftTriangle)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRect(_ r: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        let radius = min(r.width, r.height) * 0.5
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
        updateTouches(touches, isEnding: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouches(touches, isEnding: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouches(touches, isEnding: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouches(touches, isEnding: true)
    }
}

extension GameOverlayN64CButton {
    private func updateRadius(_ radius: CGFloat) {
        self.radius = radius
        self.buttonRadius = radius * 0.35
        self.squareButtonRadius = buttonRadius * buttonRadius
        let comboRadius = buttonRadius * 0.35
        self.comboSquareRadius = comboRadius * comboRadius
        let distance = radius * 0.65
        upCenter = CGPoint(x: 0, y: distance)
        rightCenter = CGPoint(x: distance, y: 0)
        downCenter = CGPoint(x: 0, y: -distance)
        leftCenter = CGPoint(x: -distance, y: 0)
        upRightCenter = CGPoint(x: distance * 0.5, y: distance * 0.5)
        upLeftCenter = CGPoint(x: -distance * 0.5, y: distance * 0.5)
        downRightCenter = CGPoint(x: distance * 0.5, y: -distance * 0.5)
        downLeftCenter = CGPoint(x: -distance * 0.5, y: -distance * 0.5)

        let circleRect = CGRect(x: -buttonRadius, y: -buttonRadius, width: buttonRadius * 2, height: buttonRadius * 2)
        let circlePath = UIBezierPath(ovalIn: circleRect).cgPath

        up.path = circlePath
        right.path = circlePath
        down.path = circlePath
        left.path = circlePath

        up.position = upCenter
        right.position = rightCenter
        down.position = downCenter
        left.position = leftCenter

        let triangleSize = buttonRadius * 0.8
        upTriangle.path = makeTrianglePath(direction: .up, size: triangleSize).cgPath
        rightTriangle.path = makeTrianglePath(direction: .right, size: triangleSize).cgPath
        downTriangle.path = makeTrianglePath(direction: .down, size: triangleSize).cgPath
        leftTriangle.path = makeTrianglePath(direction: .left, size: triangleSize).cgPath
    }

    private func makeTrianglePath(direction: ArrowDirection, size: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let side = size
        let height = side * sqrt(3.0) * 0.5

        var p1 = CGPoint(x: 0, y: 2.0 * height / 3.0)
        var p2 = CGPoint(x: -side * 0.5, y: -height / 3.0)
        var p3 = CGPoint(x: side * 0.5, y: -height / 3.0)

        let angle: CGFloat
        switch direction {
            case .up: angle = 0
            case .right: angle = -.pi / 2
            case .down: angle = .pi
            case .left: angle = .pi / 2
        }

        if angle != 0 {
            p1 = p1.rotated(by: angle)
            p2 = p2.rotated(by: angle)
            p3 = p3.rotated(by: angle)
        }

        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.close()
        return path
    }

    private func updateTouches(_ touches: Set<UITouch>, isEnding: Bool) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if isEnding {
                touchMasks.removeValue(forKey: key)
                continue
            }

            let touchPoint = touch.location(in: self)
            touchMasks[key] = maskForPoint(touchPoint)
        }
        recomputeStatus()
    }

    private func recomputeStatus() {
        var combined: UInt = GameOverlayDirectionMask.none
        for mask in touchMasks.values {
            combined |= mask
        }
        status = combined
    }

    private func maskForPoint(_ pos: CGPoint) -> UInt {
        let r2 = squareButtonRadius
        if pos.squaredDistance(to: upCenter) <= r2 {
            return GameOverlayDirectionMask.up
        }
        if pos.squaredDistance(to: rightCenter) <= r2 {
            return GameOverlayDirectionMask.right
        }
        if pos.squaredDistance(to: downCenter) <= r2 {
            return GameOverlayDirectionMask.down
        }
        if pos.squaredDistance(to: leftCenter) <= r2 {
            return GameOverlayDirectionMask.left
        }

        let rCombo = comboSquareRadius
        if pos.squaredDistance(to: upRightCenter) <= rCombo {
            return GameOverlayDirectionMask.up | GameOverlayDirectionMask.right
        }
        if pos.squaredDistance(to: upLeftCenter) <= rCombo {
            return GameOverlayDirectionMask.up | GameOverlayDirectionMask.left
        }
        if pos.squaredDistance(to: downRightCenter) <= rCombo {
            return GameOverlayDirectionMask.down | GameOverlayDirectionMask.right
        }
        if pos.squaredDistance(to: downLeftCenter) <= rCombo {
            return GameOverlayDirectionMask.down | GameOverlayDirectionMask.left
        }

        return GameOverlayDirectionMask.none
    }
}

private extension CGPoint {
    func squaredDistance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }

    func rotated(by angle: CGFloat) -> CGPoint {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGPoint(x: x * cosA - y * sinA, y: x * sinA + y * cosA)
    }
}
