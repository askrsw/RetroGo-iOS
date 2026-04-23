//
//  GameOverLayFastButton.swift
//  RetroGo
//
//  Created by OpenAI Codex.
//

import SpriteKit
import RACoordinator

final class GameOverLayFastButton: SKNode, GameOverlayElementLayout {
    // MARK: - Constants
    private let longPressThreshold: TimeInterval = 0.15
    private let defaultMultiplier: Int = 2

    // MARK: - Properties
    private var shape: GameOverlayButtonShape?
    private let shapeNode = SKShapeNode()
    private let contentNode = SKNode()
    private var labelNode: SKLabelNode?
    private var baseTitle: String

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
            updateLabelText()
            updateAppearance()
            emitStateChange()
        }
    }

    private(set) var fastForwardMultiplier: Int = 2 {
        didSet {
            fastForwardMultiplier = sanitizeFastForwardMultiplier(fastForwardMultiplier)
            guard fastForwardMultiplier != oldValue else { return }
            updateLabelText()
            if isFastForwardEnabled {
                emitStateChange()
            }
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
    private let fastForwardChangedHandler: ((Bool, Int) -> Void)?

    // MARK: - Init
    init(element: GamePageOverlayElement, fastForwardChangedHandler: ((Bool, Int) -> Void)?) {
        self.element = element
        self.baseTitle = element.title ?? "FAST"
        self.fastForwardChangedHandler = fastForwardChangedHandler
        super.init()

        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true

        fastForwardMultiplier = defaultMultiplier
        setupNodes()
        updateLabelText()
        updateAppearance()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public
    func setFastForwardEnabled(_ enabled: Bool, multiplier: Int? = nil) {
        if let multiplier {
            fastForwardMultiplier = sanitizeFastForwardMultiplier(multiplier)
        }
        isFastForwardEnabled = enabled
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

    // MARK: - Touches
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

        setFastForwardEnabled(!isFastForwardEnabled, multiplier: fastForwardMultiplier)
    }
}

// MARK: - Appearance
extension GameOverLayFastButton {
    private func setupNodes() {
        contentNode.zPosition = 1
        addChild(contentNode)

        let labelNode = SKLabelNode(text: baseTitle)
        labelNode.fontName = "Helvetica"
        labelNode.fontColor = SKColor(white: 1.0, alpha: 0.75)
        labelNode.verticalAlignmentMode = .center
        labelNode.horizontalAlignmentMode = .center
        labelNode.zPosition = 1
        contentNode.addChild(labelNode)
        self.labelNode = labelNode

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
        } else if isFastForwardEnabled {
            fillColor = SKColor(white: 1.0, alpha: 0.25)
            foregroundAlpha = 0.95
        } else {
            fillColor = SKColor(white: 1.0, alpha: 0.1)
            foregroundAlpha = 0.75
        }

        shapeNode.fillColor = fillColor
        labelNode?.fontColor = SKColor(white: 1.0, alpha: foregroundAlpha)
    }

    private func updateShape(_ s: GameOverlayButtonShape) {
        shape = s
        shapeNode.path = s.path
        if let labelNode {
            labelNode.fontSize = s.fontSize
            s.fixLabelPosition(labelNode)
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

    private func updateLabelText() {
        guard let labelNode else { return }
        labelNode.text = isFastForwardEnabled ? "\(fastForwardMultiplier)x" : baseTitle
    }
}

// MARK: - State
extension GameOverLayFastButton {
    private func emitStateChange() {
        fastForwardChangedHandler?(isFastForwardEnabled, fastForwardMultiplier)
    }

    private func sanitizeFastForwardMultiplier(_ multiplier: Int) -> Int {
        switch multiplier {
        case 2, 3, 4, 6:
            return multiplier
        default:
            return defaultMultiplier
        }
    }

    private func handleLongPress() {
        /*
         * Reserved for future popup implementation.
         * Long-press should present the 2x / 3x / 4x / 6x selector here.
         */
    }
}
