//
//  GameOverlayThumbStick.swift
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

final class GameOverlayThumbStick: SKNode, GameOverlayElementLayout {
    private(set) var radius: CGFloat = 0
    private var smallRaidusSquare: CGFloat = 0

    private let circlePannel = SKShapeNode()
    private let indicator  = SKShapeNode()
    private let decoration = SKShapeNode()

    private let originalStateAction = SKAction.move(to: .zero, duration: 0)

    // Dynamic-stick drag state. The base follows the finger past the ring edge
    // (anchored to its laid-out home) and springs back on release.
    private static let springBackDuration: TimeInterval = 0.12
    private static let maxBaseTravelRatio: CGFloat = 1.0

    private var activeTouch: UITouch?
    private var homePosition: CGPoint = .zero
    private let baseZPosition: CGFloat = 0
    private let positionActionKey = "stickBasePosition"

    private var touching: Bool = false {
        didSet {
            guard touching != oldValue else { return }
            if touching {
                circlePannel.fillColor = theme.primaryColor(alpha: 0.35)
                decoration.fillColor = theme.primaryColor
            } else {
                indicator.run(originalStateAction, withKey: "stateChange")
                circlePannel.fillColor = theme.primaryColor(alpha: 0.2)
                decoration.fillColor = theme.primaryColor(alpha: 0.35)
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

    private enum HapticAxis {
        case up, down, left, right
    }
    /// Per axis, the share of full deflection that still counts as zero.
    private static let hapticDeadzone: CGFloat = 0.1
    /// Whether the thumb has left the center during this drag.
    private var hapticActivated = false
    /// The axis the thumb last sat on; nil in the center or between two axes.
    private var hapticAxis: HapticAxis?

    private(set) var element: GamePageOverlayElement
    private let digitalHandler: GameOverlayButtonDigitalChanged?
    private let analogHandler: GameOverlayDirectionAnalogChanged?
    var hapticHandler: GameOverlayHapticHandler?
    private let theme: GameOverlayTheme

    init(element: GamePageOverlayElement, theme: GameOverlayTheme = .default, digitalHandler: GameOverlayButtonDigitalChanged? = nil, analogHandler: GameOverlayDirectionAnalogChanged? = nil) {
        self.element = element
        self.digitalHandler = digitalHandler
        self.analogHandler = analogHandler
        self.theme = theme
        super.init()

        name = element.id
        isUserInteractionEnabled = true

        circlePannel.fillColor = theme.primaryColor(alpha: 0.2)
        circlePannel.strokeColor = theme.primaryColor
        circlePannel.lineWidth = 2
        addChild(circlePannel)

        indicator.fillColor = theme.accentColor
        indicator.lineWidth = 0
        circlePannel.addChild(indicator)

        decoration.fillColor = theme.primaryColor(alpha: 0.35)
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
            // A live drag owns `position`; record the home it should spring back to.
            homePosition = newPosition
            if activeTouch == nil {
                self.position = newPosition
            }
        }
        return newPosition
    }

    // MARK: - Touch event process

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch

        // Cancel any in-flight spring-back and resume from the true resting state,
        // so a rapid re-press doesn't anchor mid-animation or creep the z-order.
        // `homePosition` is maintained by layout; `baseZPosition` is the resting z.
        removeAction(forKey: positionActionKey)
        position = homePosition
        zPosition = baseZPosition + 1

        touching = true
        process(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        touching = true
        process(activeTouch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        endDrag()
    }

    /// Releases any in-progress drag immediately (no spring animation). Used when
    /// the stick is hidden out from under the finger, e.g. a form switch.
    func cancelActiveTouch() {
        guard activeTouch != nil else { return }
        activeTouch = nil
        removeAction(forKey: positionActionKey)
        position = homePosition
        zPosition = baseZPosition
        touching = false
        sendAnalogZeroIfNeeded()
        resetHapticState()
    }
}

extension GameOverlayThumbStick {
    private func process(_ touch: UITouch) {
        guard let parent = parent else { return }
        let finger = touch.location(in: parent)
        let v = CGPoint(x: finger.x - homePosition.x, y: finger.y - homePosition.y)
        let len = sqrt(v.x * v.x + v.y * v.y)

        // Base trails the finger once it passes the ring edge, capped so it can't
        // wander across the screen onto other controls.
        var base = homePosition
        if len > radius, len > 0 {
            let over = min(len - radius, radius * Self.maxBaseTravelRatio)
            base = CGPoint(x: homePosition.x + over * v.x / len, y: homePosition.y + over * v.y / len)
        }
        position = base

        // Thumb sits under the finger in local space; its constraint clamps to radius.
        indicator.position = CGPoint(x: finger.x - base.x, y: finger.y - base.y)

        // Input value is measured from home: direction follows the finger and
        // magnitude clamps at the ring, regardless of how far the base trailed.
        updateHaptic(for: v)
        if digitalHandler != nil, analogHandler == nil {
            updateDigitalIfNeeded(v)
        }
        if analogHandler != nil, digitalHandler == nil {
            updateAnalogIfNeeded(v)
        }
    }

    private func endDrag() {
        activeTouch = nil
        touching = false
        sendAnalogZeroIfNeeded()
        // The thumb springing back home taps once.
        hapticHandler?()
        resetHapticState()

        let back = SKAction.move(to: homePosition, duration: Self.springBackDuration)
        back.timingMode = .easeOut
        let restoreZ = SKAction.run { [weak self] in
            guard let self else { return }
            self.zPosition = self.baseZPosition
        }
        run(.sequence([back, restoreZ]), withKey: positionActionKey)
    }

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

    /// Taps when the thumb leaves the center and each time it comes onto an axis,
    /// like the notches of a real stick; moving between axes is silent.
    /// Both forms, analog and digital, feel the same.
    private func updateHaptic(for v: CGPoint) {
        guard radius > 0 else { return }
        // An axis is full at half the radius, so an axis is a narrow notch the thumb crosses.
        func axisValue(_ d: CGFloat) -> CGFloat {
            let value = max(-1, min(1, 2 * d / radius))
            return abs(value) < Self.hapticDeadzone ? 0 : value
        }
        let x = axisValue(v.x)
        let y = axisValue(v.y)
        let activated = hypot(x, y) > Self.hapticDeadzone

        let axis: HapticAxis?
        switch (x == 0, y == 0) {
        case (false, true): axis = x < 0 ? .left : .right
        case (true, false): axis = y < 0 ? .down : .up
        default:            axis = nil
        }

        if let axis {
            if axis != hapticAxis {
                hapticHandler?()
            }
        } else if activated, !hapticActivated {
            hapticHandler?()
        }
        hapticAxis = axis
        hapticActivated = activated
    }

    private func resetHapticState() {
        hapticActivated = false
        hapticAxis = nil
    }
}
