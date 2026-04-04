//
//  GameOverlayNDSLayoutButton.swift
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

final class GameOverlayNDSLayoutButton: SKNode, GameOverlayElementLayout {
    private enum LayoutOrientation {
        case vertical
        case horizontal
    }

    private var orientation: LayoutOrientation = .vertical
    private var rect: CGRect?
    private(set) var touching: Bool = false {
        didSet {
            guard touching != oldValue else {
                return
            }

            let ringAlpha: CGFloat = touching ? 1.0 : 0.9
            let primaryAlpha: CGFloat = touching ? 0.85 : 0.65
            let secondaryAlpha: CGFloat = touching ? 0.75 : 0.55
            ringNode.strokeColor = SKColor(white: 1.0, alpha: ringAlpha)
            primaryScreenNode.fillColor = SKColor(white: 1.0, alpha: primaryAlpha)
            secondaryScreenNode.fillColor = SKColor(white: 1.0, alpha: secondaryAlpha)

            joypadCodes.forEach { digitalChangeHandler?($0, touching) }
        }
    }

    private let ringNode = SKShapeNode()
    private let contentNode = SKNode()
    private let primaryScreenNode = SKShapeNode()
    private let secondaryScreenNode = SKShapeNode()

    private(set) var element: GamePageOverlayElement
    private let joypadCodes: [RetroArchJoypadCode]
    private let digitalChangeHandler: GameOverlayButtonDigitalChanged?

    init(element: GamePageOverlayElement, digitalChangeHandler: GameOverlayButtonDigitalChanged?) {
        self.element = element
        self.joypadCodes = element.binds.map( { $0.code })
        self.digitalChangeHandler = digitalChangeHandler
        super.init()

        name = element.id
        isHidden = element.isHidden
        isUserInteractionEnabled = true

        ringNode.strokeColor = SKColor(white: 1.0, alpha: 0.9)
        ringNode.fillColor = .clear
        addChild(ringNode)

        addChild(contentNode)

        let primaryFill = SKColor(white: 1.0, alpha: 0.65)
        let secondaryFill = SKColor(white: 1.0, alpha: 0.55)

        primaryScreenNode.strokeColor = .clear
        primaryScreenNode.fillColor = primaryFill
        primaryScreenNode.lineWidth = 0
        contentNode.addChild(primaryScreenNode)

        secondaryScreenNode.strokeColor = .clear
        secondaryScreenNode.fillColor = secondaryFill
        secondaryScreenNode.lineWidth = 0
        contentNode.addChild(secondaryScreenNode)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRect(_ r: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        if rect != r {
            rect = r
            updateAppearance(for: r)
        }

        let newPosition = CGPoint(x: r.midX, y: r.midY)
        if shouldUpdatePosition {
            position = newPosition
        }
        return newPosition
    }

    func applyVerticalLayout(_ isVertical: Bool, animated: Bool = false) {
        let newOrientation: LayoutOrientation = isVertical ? .vertical : .horizontal
        guard orientation != newOrientation else {
            return
        }

        orientation = newOrientation
        applyOrientation(animated: animated)
    }

    // MARK: - Touch event process

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let _ = touches.first {
            touching = true
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let _ = touches.first {
            touching = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touching = false
        orientation = orientation == .vertical ? .horizontal : .vertical
        applyOrientation(animated: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touching = false
    }
}

extension GameOverlayNDSLayoutButton {
    private func updateAppearance(for rect: CGRect) {
        let size = min(rect.width, rect.height)
        let radius = size * 0.5
        ringNode.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: size, height: size), transform: nil)
        ringNode.lineWidth = max(2.0, size * 0.06)

        let screenWidth = size * 0.42
        let screenHeight = size * 0.27
        let cornerRadius = min(screenWidth, screenHeight) * 0.18
        let screenRect = CGRect(x: -screenWidth * 0.5, y: -screenHeight * 0.5, width: screenWidth, height: screenHeight)
        let screenPath = CGPath(roundedRect: screenRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        primaryScreenNode.path = screenPath
        secondaryScreenNode.path = screenPath

        let spacing = size * 0.16
        primaryScreenNode.position = CGPoint(x: 0, y: spacing)
        secondaryScreenNode.position = CGPoint(x: 0, y: -spacing)

        applyOrientation(animated: false)
    }

    private func applyOrientation(animated: Bool) {
        let targetRotation: CGFloat

        switch orientation {
            case .vertical:
                targetRotation = 0.0
            case .horizontal:
                targetRotation = -.pi * 0.5
        }

        if animated {
            removeAction(forKey: "layout-rotation")
            let duration = 0.2
            run(.rotate(toAngle: targetRotation, duration: duration, shortestUnitArc: true), withKey: "layout-rotation")
        } else {
            zRotation = targetRotation
        }
    }
}
