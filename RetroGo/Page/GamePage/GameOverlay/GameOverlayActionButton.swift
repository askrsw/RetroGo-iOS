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
    private let longPressThreshold: TimeInterval = 0.15

    // Turbo cadence in emulator frames: each cycle is `period` frames with `duty`
    // of them held down. Injected from the game config's TurboSpeed preset and
    // updatable at runtime via setTurboTiming(period:duty:). Defaults to the
    // historical 4/2 (≈15Hz @60fps). The button itself is preset-agnostic — the
    // scene maps the tier to frames.
    private var period: Int
    private var duty: Int

    // Latch indicator (the pulsing ring shown when turbo is latched but untouched —
    // i.e. "hands-off auto-fire", the state most likely to be mistaken for a stuck
    // button). Kept as named constants so the brand-color ring is easy to retune
    // after on-device contrast checking.
    // Latched (hands-off auto-fire) is marked only by a slow, gentle breathing of
    // the button's own fill alpha — deliberately subtle so it confirms the state at
    // a glance without pulling the player's eye away from gameplay. The border never
    // moves; there is no halo. Breathes between activeFillAlpha and
    // emphasizedActiveFillAlpha (read from the theme at runtime).
    private static let latchBreatheActionKey = "latch-breathe"
    private static let latchBreatheCycle: TimeInterval = 1.0

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
    private let theme: GameOverlayTheme

    // MARK: - Init
    init(element: GamePageOverlayElement, isTurboSupported: Bool, autoKeepTurbo: Bool, turboPeriod: Int = 4, turboDuty: Int = 2, theme: GameOverlayTheme = .default, digitalChangeHandler: GameOverlayButtonDigitalChanged?) {
        self.element = element
        self.joypadCodes = element.binds.map({ $0.code })
        self.autoKeepTurbo = autoKeepTurbo
        self.isTurboSupported = isTurboSupported
        self.period = max(1, turboPeriod)
        self.duty = max(0, min(turboDuty, max(1, turboPeriod)))
        self.digitalChangeHandler = digitalChangeHandler
        self.theme = theme
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

    /// Toggle the 0.15s tap-to-latch shortcut at runtime (driven by the game config
    /// switch). Disabling it must also drop any currently latched turbo: a button
    /// left latched would keep bursting after the user turned the feature off, which
    /// reads as a stuck button. Holding (finger-down) turbo is unaffected.
    func setAutoKeepTurbo(_ enabled: Bool) {
        guard autoKeepTurbo != enabled else { return }
        autoKeepTurbo = enabled
        if !enabled {
            isTurboLatched = false
        }
    }

    /// Update the turbo cadence at runtime (driven by the game config TurboSpeed
    /// preset). Clamps to valid frames and resets the cycle index so a shrunk
    /// period can't leave a stale out-of-range index.
    func setTurboTiming(period: Int, duty: Int) {
        let p = max(1, period)
        let d = max(0, min(duty, p))
        guard p != self.period || d != self.duty else { return }
        self.period = p
        self.duty = d
        frameIndex = 0
    }

    func applyBindingBubbleTouch(_ touching: Bool) {
        emit(touching)
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
            lNode.fontColor = theme.primaryColor(alpha: theme.normalContentAlpha)
            lNode.verticalAlignmentMode = .center
            lNode.horizontalAlignmentMode = .center
            lNode.zPosition = 1
            contentNode.addChild(lNode)
            self.labelNode = lNode
        }

        shapeNode.strokeColor = theme.primaryColor
        shapeNode.lineWidth = 2
        shapeNode.zPosition = 0
        shapeNode.fillColor = theme.primaryColor(alpha: theme.normalFillAlpha)
        addChild(shapeNode)
    }

    private func updateAppearance() {
        let fillColor: SKColor
        let foregroundAlpha: CGFloat

        // Latched-and-untouched (the only way to reach isTurboActive && !isTouching,
        // since holding always implies isTouching) gets a gentle fill breathing
        // instead of a static color, handled by updateLatchBreathing below.
        let latchedHandsOff = isTurboActive && !isTouching

        if isTouching {
            fillColor = theme.primaryColor(alpha: theme.pressedFillAlpha)
            foregroundAlpha = theme.pressedContentAlpha
        } else if latchedHandsOff {
            // Fill is driven by the breathing action; seed a sensible static value
            // for the frame before the action's first tick.
            fillColor = theme.primaryColor(alpha: theme.activeFillAlpha)
            foregroundAlpha = 0.95
        } else {
            fillColor = theme.primaryColor(alpha: theme.normalFillAlpha)
            foregroundAlpha = theme.normalContentAlpha
        }

        if !latchedHandsOff {
            shapeNode.fillColor = fillColor
        }
        labelNode?.fontColor = theme.primaryColor(alpha: foregroundAlpha)
        updatePSIconAppearance(alpha: foregroundAlpha)
        updateLatchBreathing(latchedHandsOff, seedFill: fillColor)
    }

    /// Slow, subtle breathing of the fill alpha for the hands-off latched state.
    /// Centralized here because every state change that can enter/leave latch
    /// (touch, latch/hold didSet, reset, runtime turbo/auto-keep toggles) funnels
    /// through `updateAppearance`, so a single condition can't leave it stuck on.
    /// Pure per-frame fill writes on one node — negligible CPU, no GPU cost.
    private func updateLatchBreathing(_ active: Bool, seedFill: SKColor) {
        guard active else {
            shapeNode.removeAction(forKey: Self.latchBreatheActionKey)
            return
        }
        guard shapeNode.action(forKey: Self.latchBreatheActionKey) == nil else { return }

        shapeNode.fillColor = seedFill
        let lo = theme.activeFillAlpha
        let hi = theme.emphasizedActiveFillAlpha
        let cycle = Self.latchBreatheCycle
        let breathe = SKAction.customAction(withDuration: cycle) { [weak self] node, elapsed in
            guard let self, let shape = node as? SKShapeNode else { return }
            let phase = cycle > 0 ? CGFloat(elapsed) / CGFloat(cycle) : 0
            let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)   // 0 -> 1 -> 0
            shape.fillColor = self.theme.primaryColor(alpha: lo + (hi - lo) * wave)
        }
        shapeNode.run(.repeatForever(breathe), withKey: Self.latchBreatheActionKey)
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
        let strokeColor = theme.primaryColor(alpha: alpha)
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
