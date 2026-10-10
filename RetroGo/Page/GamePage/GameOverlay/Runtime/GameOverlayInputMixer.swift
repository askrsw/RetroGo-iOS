//
//  GameOverlayInputMixer.swift
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

import Foundation
import RACoordinator

/// Merges the digital output of the on-screen controls before it reaches the
/// virtual joypad, which keeps one bit per button.
///
/// Several controls can press the same button: A and an A+B combo, X and the
/// N64 C buttons (R2 + X). Sent straight through, releasing one would release
/// the button while the other still holds it. Here a button goes down when the
/// first control presses it and up when the last one lets go.
///
/// Turbo controls emit from the emulator frame callback, which runs on the game
/// logic thread with the thread runner, while touches arrive on the main
/// thread, hence the lock.
final class GameOverlayInputMixer {
    typealias Source = Int

    private let lock = NSLock()
    private var holders: [RetroArchJoypadCode: Set<Source>] = [:]
    private var nextSource: Source = 0

    /// A new identity for one control's output.
    func makeSource() -> Source {
        lock.lock()
        defer { lock.unlock() }
        nextSource += 1
        return nextSource
    }

    func send(_ code: RetroArchJoypadCode, down: Bool, from source: Source) {
        guard code != .none else { return }
        lock.lock()
        defer { lock.unlock() }
        var sources = holders[code] ?? []
        let wasDown = !sources.isEmpty
        if down {
            sources.insert(source)
        } else {
            sources.remove(source)
        }
        holders[code] = sources.isEmpty ? nil : sources
        let isDown = !sources.isEmpty
        if isDown != wasDown {
            RetroArchX.shared().send(code, down: isDown)
        }
    }

    /// A digital handler for one control.
    func handler() -> GameOverlayButtonDigitalChanged {
        let source = makeSource()
        return { [weak self] code, down in
            self?.send(code, down: down, from: source)
        }
    }
}

/// A value the main thread replaces and the game logic thread reads.
final class GameOverlayLockedValue<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
