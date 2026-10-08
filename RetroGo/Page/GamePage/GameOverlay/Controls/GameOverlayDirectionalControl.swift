//
//  GameOverlayDirectionalControl.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/16.
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

/// Combined direction control that switches between a D-pad form and a thumb
/// stick form. Only one form is visible at a time; an attached switch button
/// toggles between them.
///
/// A single `directional` overlay element drives all three sub-controls so that
/// their visibility coordination lives in one place instead of being threaded
/// through `GamePageOverlayScene`. The D-pad and the stick share the element's
/// `geometry` (same position and size). The switch button is small and is
/// placed automatically at a corner of that geometry; its position is therefore
/// derived, not described in JSON.
///
/// Layouts that want a D-pad and a stick visible at the same time (e.g. PSP)
/// use independent `dpad` and `stick` elements instead of this control.
final class GameOverlayDirectionalControl: SKNode, GameOverlayElementLayout {
    enum SwitchCorner {
        case topLeft
        case bottomLeft
    }

    /// Switch button size as a fraction of the control's width. Chosen so the
    /// historical 20pt switch on a 130pt control is reproduced exactly.
    private static let switchSizeRatio: CGFloat = 20.0 / 130.0

    private(set) var element: GamePageOverlayElement

    private let dpad: GameOverlayDirectionPad
    private let stick: GameOverlayThumbStick
    private var dpadStickSwitch: GameOverlayDpadStickSwitch!

    private let switchCorner: SwitchCorner
    private(set) var currentControl: GameOverlayDpadStickSwitch.`Type`

    init(element: GamePageOverlayElement,
         supportsAnalog: Bool,
         theme: GameOverlayTheme = .default,
         digitalHandler: GameOverlayButtonDigitalChanged?,
         analogHandler: GameOverlayDirectionAnalogChanged?) {
        self.element = element
        self.switchCorner = element.directionalSwitchAtBottomLeft ? .bottomLeft : .topLeft
        self.currentControl = element.directionalDefaultsToStick ? .stick : .dpad

        // The D-pad reuses the primary element verbatim, keeping `element.id`
        // stable so persisted binding profiles keyed by this id keep working.
        self.dpad = GameOverlayDirectionPad(element: element, theme: theme, digitalHandler: digitalHandler)

        // The stick shares the same geometry/position as the D-pad.
        let stickElement = GamePageOverlayElement(id: element.id + "-stick", type: .stick, geometry: element.geometry)
        if supportsAnalog {
            self.stick = GameOverlayThumbStick(element: stickElement, theme: theme, analogHandler: analogHandler)
        } else {
            self.stick = GameOverlayThumbStick(element: stickElement, theme: theme, digitalHandler: digitalHandler)
        }

        super.init()

        name = element.id

        addChild(dpad)
        addChild(stick)

        let switchElement = GamePageOverlayElement(id: element.id + "-switch", type: .directional, geometry: element.geometry)
        let switchNode = GameOverlayDpadStickSwitch(element: switchElement, theme: theme) { [weak self] type in
            self?.applyControl(type)
        }
        self.dpadStickSwitch = switchNode
        addChild(switchNode)

        applyControl(currentControl)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRect(_ rect: CGRect, shouldUpdatePosition: Bool) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if shouldUpdatePosition {
            self.position = center
        }

        // D-pad and stick share the geometry; both sit at this node's origin.
        let local = CGRect(x: -rect.width * 0.5, y: -rect.height * 0.5, width: rect.width, height: rect.height)
        _ = dpad.updateRect(local, shouldUpdatePosition: true)
        _ = stick.updateRect(local, shouldUpdatePosition: true)

        // The switch hugs a corner of the control, just outside its bounds.
        let switchSize = rect.width * Self.switchSizeRatio
        let half = switchSize * 0.5
        let switchCenter: CGPoint
        switch switchCorner {
        case .topLeft:
            switchCenter = CGPoint(x: -rect.width * 0.5 + half, y: rect.height * 0.5 + half)
        case .bottomLeft:
            switchCenter = CGPoint(x: -rect.width * 0.5 + half, y: -rect.height * 0.5 - half)
        }
        let switchRect = CGRect(x: switchCenter.x - half, y: switchCenter.y - half, width: switchSize, height: switchSize)
        _ = dpadStickSwitch.updateRect(switchRect, shouldUpdatePosition: true)

        return center
    }

    private func applyControl(_ control: GameOverlayDpadStickSwitch.`Type`) {
        currentControl = control
        dpad.isHidden = (control == .stick)
        stick.isHidden = (control == .dpad)
        // If the stick is being hidden out from under an in-progress drag, release
        // it cleanly so it doesn't keep tracking or stay off its home position.
        if control == .dpad {
            stick.cancelActiveTouch()
        }
        dpadStickSwitch?.applyType(control)
    }
}
