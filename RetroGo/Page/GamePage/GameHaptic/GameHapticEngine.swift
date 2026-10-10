//
//  GameHapticEngine.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/9.
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

import UIKit

/// How the phone answers a press on the on-screen controls: off, or one of the
/// system impact styles. The stored value is the `rawValue` (stable — never renumber).
enum GameHapticLevel: Int, CaseIterable {
    case off    = 0
    case soft   = 1
    case light  = 2
    case medium = 3
    case heavy  = 4
    case rigid  = 5

    static let `default`: GameHapticLevel = .soft

    fileprivate var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle? {
        switch self {
        case .off:    return nil
        case .soft:   return .soft
        case .light:  return .light
        case .medium: return .medium
        case .heavy:  return .heavy
        case .rigid:  return .rigid
        }
    }
}

typealias GameOverlayHapticHandler = () -> Void

/// The phone's own haptics in game.
///
/// Every control answers a press with the same system impact, so the whole pad
/// feels like one device: a press, a new direction on the D-pad, a stick leaving
/// its center or crossing onto an axis. Lifting off a button is silent; only the
/// stick ticks as it springs back. The system styles are tuned by Apple for the
/// Taptic Engine and fire with less delay than a hand-made Core Haptics pattern.
///
/// Rumble a core requests is a separate path with its own setting: the ObjC
/// `RAPhoneRumble` plays it on Core Haptics straight from the virtual joypad.
///
/// Main thread only: presses come from the overlay's touch handlers.
final class GameHapticEngine {
    static let shared = GameHapticEngine()

    /// Presses closer than this are one input update (two fingers landing
    /// together, or a D-pad diagonal adding its second direction), so they give one tap.
    private static let coalesceInterval: TimeInterval = 0.012

    private var level: GameHapticLevel = .off
    private var generator: UIImpactFeedbackGenerator?
    private var lastImpactTime: TimeInterval = 0

    private init() {}

    /// Begins a game session at `level`.
    func start(level: GameHapticLevel) {
        setLevel(level)
    }

    /// Changes the level of the running session.
    func setLevel(_ level: GameHapticLevel) {
        self.level = level
        if let style = level.impactStyle {
            let generator = UIImpactFeedbackGenerator(style: style)
            // Wakes the Taptic Engine so the first press is not late.
            generator.prepare()
            self.generator = generator
        } else {
            generator = nil
        }
    }

    /// Ends the game session.
    func stop() {
        setLevel(.off)
    }

    /// One press of the on-screen controls.
    func impact() {
        guard let generator else { return }
        let now = CACurrentMediaTime()
        guard now - lastImpactTime >= Self.coalesceInterval else { return }
        lastImpactTime = now
        generator.impactOccurred()
        // Keeps the engine ready for the next press; it idles again after a few seconds without one.
        generator.prepare()
    }
}
