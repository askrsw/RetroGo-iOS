//
//  GameOverlayTheme.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/1.
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

struct GameOverlayTheme {
    let primaryColor: SKColor
    let accentColor: SKColor

    let normalFillAlpha: CGFloat
    let pressedFillAlpha: CGFloat
    let activeFillAlpha: CGFloat
    let emphasizedPressedFillAlpha: CGFloat
    let emphasizedActiveFillAlpha: CGFloat
    let normalContentAlpha: CGFloat
    let pressedContentAlpha: CGFloat

    static let `default` = GameOverlayTheme(
        primaryColor: .white,
        accentColor: .mainColor,
        normalFillAlpha: 0.10,
        pressedFillAlpha: 0.40,
        activeFillAlpha: 0.25,
        emphasizedPressedFillAlpha: 0.55,
        emphasizedActiveFillAlpha: 0.35,
        normalContentAlpha: 0.75,
        pressedContentAlpha: 1.00
    )

    static let bindingConfiguration = GameOverlayTheme(
        primaryColor: SKColor(white: 0.72, alpha: 1.0),
        accentColor: SKColor(white: 0.72, alpha: 1.0),
        normalFillAlpha: 0.08,
        pressedFillAlpha: 0.22,
        activeFillAlpha: 0.16,
        emphasizedPressedFillAlpha: 0.28,
        emphasizedActiveFillAlpha: 0.20,
        normalContentAlpha: 0.78,
        pressedContentAlpha: 0.96
    )

    func primaryColor(alpha: CGFloat) -> SKColor {
        primaryColor.withAlphaComponent(alpha)
    }

    func accentColor(alpha: CGFloat) -> SKColor {
        accentColor.withAlphaComponent(alpha)
    }
}
