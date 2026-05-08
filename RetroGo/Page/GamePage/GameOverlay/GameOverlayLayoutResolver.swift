//
//  GameOverlayLayoutResolver.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/29.
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

struct GameOverlayLayoutResolver {
    enum Mode {
        case portrait
        case landscape
    }

    let config: GamePageOverlayConfig

    private(set) var size: CGSize = .zero
    private(set) var mode: Mode = .portrait
    private(set) var scaleFactor: CGFloat = 1.0
    private(set) var contentOffset: CGPoint = .zero
    private(set) var polarAnchor: CGPoint = .zero

    init(config: GamePageOverlayConfig) {
        self.config = config
    }

    mutating func update(size: CGSize, contentOffset: CGPoint = .zero) {
        self.size = size
        self.contentOffset = contentOffset
        self.mode = size.width < size.height ? .portrait : .landscape
        self.scaleFactor = resolveScaleFactor()
        self.polarAnchor = resolvePolarAnchor()
    }

    func resolveRect(_ element: GamePageOverlayElement, usePolarLayout: Bool) -> CGRect {
        let elementSize = element.geometry.size
        let scaledSize = CGSize(
            width: CGFloat(elementSize.width) * scaleFactor,
            height: CGFloat(elementSize.height) * scaleFactor
        )

        if usePolarLayout, let polar = polarLayout(for: element) {
            return resolvePolarRect(size: scaledSize, polar: polar)
        }

        return resolvePlainRect(size: scaledSize, insets: plainLayout(for: element))
    }

    func resolveRotation(_ element: GamePageOverlayElement, usePolarLayout: Bool, rotatesWithPolarLayout: Bool) -> CGFloat {
        guard usePolarLayout,
              rotatesWithPolarLayout,
              let polar = polarLayout(for: element) else {
            return 0
        }

        // Note: theta is stored in degrees in overlay JSON.
        let thetaRadians = polar.theta * Double.pi / 180.0

        // SKLabelNode text runs along local +X, so local +Y should point to the radius.
        return CGFloat(thetaRadians - Double.pi / 2.0)
    }
}

private extension GameOverlayLayoutResolver {
    func resolvePolarRect(size: CGSize, polar: GamePageOverlayPolar) -> CGRect {
        let theta = polar.theta * Double.pi / 180.0
        let radius = polar.radius * Double(scaleFactor)

        let center = CGPoint(
            x: polarAnchor.x + cos(theta) * radius,
            y: polarAnchor.y + sin(theta) * radius
        )

        let origin = CGPoint(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5
        )

        return CGRect(origin: origin, size: size)
    }

    func resolvePlainRect(size: CGSize, insets: GamePageOverlayInsets) -> CGRect {
        let scaledInsets = scale(insets)

        let x: CGFloat
        if let centerXInset = scaledInsets.centerX {
            let centerX = self.size.width * 0.5
            x = centerX + centerXInset
        } else if let left = scaledInsets.left {
            x = left
        } else if let right = scaledInsets.right {
            x = self.size.width - right - size.width
        } else {
            let centerX = self.size.width * 0.5
            x = centerX - size.width * 0.5
        }

        let y: CGFloat
        if let centerYInset = scaledInsets.centerY {
            let centerY = self.size.height * 0.5
            y = centerY + centerYInset
        } else if let bottom = scaledInsets.bottom {
            y = bottom
        } else if let top = scaledInsets.top {
            y = self.size.height - top - size.height
        } else {
            let centerY = self.size.height * 0.5
            y = centerY - size.height * 0.5
        }

        let scaledOrigin = CGPoint(x: x + contentOffset.x, y: y + contentOffset.y)

        return CGRect(origin: scaledOrigin, size: size)
    }

    func resolvePolarAnchor() -> CGPoint {
        let insets = mode == .portrait ? config.portraitPolarAnchor : config.landscapePolarAnchor
        let scaledInsets = scale(insets)

        let x: CGFloat
        if let centerXInset = scaledInsets.centerX {
            let centerX = size.width * 0.5
            x = centerX + centerXInset
        } else if let left = scaledInsets.left {
            x = left
        } else if let right = scaledInsets.right {
            x = size.width - right
        } else {
            x = size.width * 0.5
        }

        let y: CGFloat
        if let centerYInset = scaledInsets.centerY {
            let centerY = size.height * 0.5
            y = centerY + centerYInset
        } else if let bottom = scaledInsets.bottom {
            y = bottom
        } else if let top = scaledInsets.top {
            y = size.height - top
        } else {
            y = size.height * 0.5
        }

        return CGPoint(x: x + contentOffset.x, y: y + contentOffset.y)
    }

    func resolveScaleFactor() -> CGFloat {
        let reference = mode == .portrait ? config.portraitRefSize : config.landscapeRefSize
        let refWidth = CGFloat(reference.width)
        let refHeight = CGFloat(reference.height)
        let scaleX = size.width / refWidth
        let scaleY = size.height / refHeight
        return min(1, scaleX, scaleY)
    }

    func scale(_ insets: GamePageOverlayInsets) -> GamePageOverlayInsets {
        GamePageOverlayInsets(
            top: insets.top.map { $0 * scaleFactor },
            left: insets.left.map { $0 * scaleFactor },
            bottom: insets.bottom.map { $0 * scaleFactor },
            right: insets.right.map { $0 * scaleFactor },
            centerX: insets.centerX.map { $0 * scaleFactor },
            centerY: insets.centerY.map { $0 * scaleFactor }
        )
    }

    func plainLayout(for element: GamePageOverlayElement) -> GamePageOverlayInsets {
        mode == .portrait ? element.geometry.plainPortraitLayout : element.geometry.plainLandscapeLayout
    }

    func polarLayout(for element: GamePageOverlayElement) -> GamePageOverlayPolar? {
        mode == .portrait ? element.geometry.polarPortraitLayout : element.geometry.polarLandscapeLayout
    }
}

protocol GameOverlaySceneLayouting: AnyObject {
    var overlayLayoutResolver: GameOverlayLayoutResolver { get set }
    var usePolarLayout: Bool { get }
}

extension GameOverlaySceneLayouting where Self: SKScene {
    func updateOverlayLayout(for size: CGSize, contentOffset: CGPoint = .zero) {
        self.size = size
        var resolver = overlayLayoutResolver
        resolver.update(size: size, contentOffset: contentOffset)
        overlayLayoutResolver = resolver
    }

    func resolveOverlayRect(_ element: GamePageOverlayElement) -> CGRect {
        overlayLayoutResolver.resolveRect(element, usePolarLayout: usePolarLayout)
    }

    func resolveOverlayRotation(_ element: GamePageOverlayElement, rotatesWithPolarLayout: Bool) -> CGFloat {
        overlayLayoutResolver.resolveRotation(
            element,
            usePolarLayout: usePolarLayout,
            rotatesWithPolarLayout: rotatesWithPolarLayout
        )
    }
}
