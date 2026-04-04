//
//  GameOverlayCollapseButton.swift
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

final class GameOverlayCollapseButton: SKNode, GameOverlayElementLayout {
    private var isCollapsed: Bool = false
    private var rect: CGRect?

    private let ringNode = SKShapeNode()
    private let chevronNode = SKShapeNode()
    private var chevronRadius: CGFloat = 0

    private(set) var element: GamePageOverlayElement
    private let handler: ((Bool) -> Void)?

    init(element: GamePageOverlayElement, handler: ((Bool) -> Void)?) {
        self.element = element
        self.handler = handler
        super.init()

        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true

        ringNode.strokeColor = SKColor(white: 1.0, alpha: 0.75)
        ringNode.fillColor = .clear
        addChild(ringNode)

        chevronNode.strokeColor = SKColor(white: 1.0, alpha: 0.9)
        chevronNode.lineCap = .round
        chevronNode.lineJoin = .round
        chevronNode.fillColor = .clear
        addChild(chevronNode)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRect(_ r: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        if r != rect {
            rect = r

            let size = min(r.width, r.height)
            let radius = size * 0.5

            ringNode.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: size, height: size), transform: nil)
            ringNode.lineWidth = max(2.0, size * 0.06)
            chevronNode.lineWidth = max(2.0, size * 0.08)
            chevronRadius = radius
            updateChevronPath(radius)
            applyChevronRotation(animated: false)
        }

        let newPosition = CGPoint(x: r.midX, y: r.midY)
        if shouldUpdatePosition {
            self.position = newPosition
        }
        return newPosition
    }

    func applyCollapsed(_ collapsed: Bool, animated: Bool = false) {
        guard isCollapsed != collapsed else {
            return
        }

        isCollapsed = collapsed
        applyChevronRotation(animated: animated)
    }

    // MARK: - Touch event process

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        setPressed(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        setPressed(false)
        handler?(!isCollapsed)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        setPressed(false)
    }
}

extension GameOverlayCollapseButton {
    private func setPressed(_ pressed: Bool) {
        let targetScale: CGFloat = pressed ? 0.85 : 1.0
        setScale(targetScale)
    }

    private func updateChevronPath(_ radius: CGFloat) {
        let chevronWidth = radius * 0.9
        let chevronHeight = radius * 0.5
        let halfW = chevronWidth * 0.5
        let halfH = chevronHeight * 0.5

        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfW, y: halfH))
        path.addLine(to: CGPoint(x: 0.0, y: -halfH))
        path.addLine(to: CGPoint(x: halfW, y: halfH))
        chevronNode.path = path
    }

    private func applyChevronRotation(animated: Bool) {
        let targetRotation: CGFloat = isCollapsed ? .pi : 0.0
        if animated {
            chevronNode.removeAction(forKey: "chevron-rotation")
            let action = SKAction.rotate(toAngle: targetRotation, duration: 0.2, shortestUnitArc: true)
            chevronNode.run(action, withKey: "chevron-rotation")
        } else {
            chevronNode.zRotation = targetRotation
        }
    }
}
