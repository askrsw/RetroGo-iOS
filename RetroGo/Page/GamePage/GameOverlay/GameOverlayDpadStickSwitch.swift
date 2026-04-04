//
//  GameOverlayDpadStickSwitch.swift
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

final class GameOverlayDpadStickSwitch: SKNode, GameOverlayElementLayout {
    enum `Type` {
        case dpad, stick
    }

    private(set) var type: `Type` = .dpad
    private var rect: CGRect?

    private let ringNode = SKShapeNode()
    private let crossNode = SKNode()
    private let crossVerticalNode = SKShapeNode()
    private let crossHorizontalNode = SKShapeNode()
    private let stickNode = SKShapeNode()

    private(set) var element: GamePageOverlayElement
    private let handler: GameOverlaySwitchHandler?

    init(element: GamePageOverlayElement, handler: GameOverlaySwitchHandler?) {
        self.element = element
        self.handler = handler
        super.init()

        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true

        ringNode.strokeColor = SKColor(white: 1.0, alpha: 0.75)
        addChild(ringNode)

        crossVerticalNode.fillColor = SKColor(white: 1.0, alpha: 0.85)
        crossVerticalNode.strokeColor = .clear
        crossNode.addChild(crossVerticalNode)
        crossHorizontalNode.fillColor = SKColor(white: 1.0, alpha: 0.85)
        crossHorizontalNode.strokeColor = .clear
        crossNode.addChild(crossHorizontalNode)
        addChild(crossNode)

        stickNode.fillColor = SKColor(white: 1.0, alpha: 0.85)
        stickNode.strokeColor = .clear
        addChild(stickNode)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRect(_ r: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        if r != rect {
            updateShape(r)
        }

        let newPosition = CGPoint(x: r.midX, y: r.midY)
        if shouldUpdatePosition {
            self.position = newPosition
        }
        return newPosition
    }

    func applyType(_ type: `Type`) {
        self.type = type
        switch type {
        case .dpad:
            crossNode.isHidden = true
            stickNode.isHidden = false
        case .stick:
            crossNode.isHidden = false
            stickNode.isHidden = true
        }
    }

    // MARK: - Touch event process

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        setPressed(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        setPressed(false)
        let nexType: `Type` = (type == .dpad) ? .stick : .dpad
        handler?(nexType)
        applyType(nexType)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        setPressed(false)
    }
}

extension GameOverlayDpadStickSwitch {
    private func updateShape(_ r: CGRect) {
        rect = r

        let size = min(r.width, r.height)
        let radius = size * 0.5

        ringNode.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: size, height: size), transform: nil)
        ringNode.lineWidth = max(2.0, size * 0.06)

        let crossSize = size * 0.7
        let crossThickness = size * 0.2
        let crossHalf = crossSize * 0.5
        let crossT = crossThickness * 0.5

        crossVerticalNode.path = CGPath(rect: CGRect(x: -crossT, y: -crossHalf, width: crossThickness, height: crossSize), transform: nil)
        crossHorizontalNode.path = CGPath(rect: CGRect(x: -crossHalf, y: -crossT, width: crossSize, height: crossThickness), transform: nil)

        let stickRadius = size * 0.35
        stickNode.path = CGPath(ellipseIn: CGRect(x: -stickRadius, y: -stickRadius, width: stickRadius * 2, height: stickRadius * 2), transform: nil)
    }

    private func setPressed(_ pressed: Bool) {
        let targetScale: CGFloat = pressed ? 0.85 : 1.0
        setScale(targetScale)
    }
}
