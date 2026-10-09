//
//  GameOverlayLayoutData.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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

/// Device class a custom layout was made for. iPhone and iPad layouts are kept
/// apart: the space around the game screen differs too much to share positions.
enum GameOverlayLayoutIdiom: String {
    case phone
    case pad

    static var current: Self {
        UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }
}

/// What a user layout changes on top of the built-in overlay JSON.
///
/// Stored as JSON in `overlay_layout.data`, so new fields only need a new
/// optional property (and a `version` bump when old data must be read
/// differently), never a database migration. Every field is optional: anything
/// left out keeps the built-in value. Lengths are in the overlay JSON's
/// reference units, so they scale with the screen exactly like the built-in
/// layout does.
struct GameOverlayLayoutData: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    /// Opacity of the whole overlay, 0...1; nil keeps the built-in look.
    var opacity: Double?
    var portrait: Orientation?
    var landscape: Orientation?
    /// Arcade four-button layout (`four_button_geometry` in the overlay JSON),
    /// kept apart so moving a button in one layout leaves the other alone.
    /// Missing means the built-in four-button positions.
    var portraitFourButton: Orientation?
    var landscapeFourButton: Orientation?
    /// Combo buttons the user made. What they press is shared by every
    /// orientation; where each shows, and whether, is kept per orientation in
    /// `elements` like any other control.
    var combos: [Combo]?
    /// Turbo of the platform's built-in combos, keyed by element id, where this layout
    /// differs from the overlay JSON (A+B on NES is turbo there, for one).
    var presetComboTurbo: [String: Bool]?

    struct Orientation: Codable, Equatable {
        /// Keyed by overlay element id (`a`, `left-dpad`, `start`...).
        var elements: [String: Element] = [:]
        /// Keyed by group name; a group moves and scales its members together.
        var groups: [String: Group] = [:]

        var isEmpty: Bool { elements.isEmpty && groups.isEmpty }
    }

    struct Element: Codable, Equatable {
        /// Plain position replacing the JSON one; an element with its own
        /// position no longer follows the polar (arc) layout or its group.
        var layout: GamePageOverlayInsets?
        /// Size multiplier on top of the JSON size.
        var scale: Double?
        /// Only extension buttons (turbo, combo) may be hidden.
        var hidden: Bool?

        var isEmpty: Bool { layout == nil && scale == nil && hidden == nil }
    }

    struct Group: Codable, Equatable {
        var offsetX: Double = 0
        var offsetY: Double = 0
        var scale: Double?

        var isEmpty: Bool { offsetX == 0 && offsetY == 0 && scale == nil }
    }

    struct Combo: Codable, Equatable {
        static let idPrefix = "user-combo-"
        static let keyRange = 2...4

        var id: String
        /// RetroPad buttons (`A`, `L1`, `START`...), the vocabulary of the overlay JSON `binds`.
        var binds: [String]
        var turbo: Bool

        static func makeId() -> String {
            idPrefix + UUID().uuidString.prefix(8).lowercased()
        }
    }

    init() { }

    func orientation(portrait isPortrait: Bool, fourButton: Bool = false) -> Orientation? {
        switch (isPortrait, fourButton) {
        case (true, false): return portrait
        case (false, false): return landscape
        case (true, true): return portraitFourButton
        case (false, true): return landscapeFourButton
        }
    }

    mutating func setOrientation(_ value: Orientation?, portrait isPortrait: Bool, fourButton: Bool = false) {
        let stored = (value?.isEmpty ?? true) ? nil : value
        switch (isPortrait, fourButton) {
        case (true, false): portrait = stored
        case (false, false): landscape = stored
        case (true, true): portraitFourButton = stored
        case (false, true): landscapeFourButton = stored
        }
    }
}

extension GameOverlayLayoutData {
    private static let allOrientations: [(portrait: Bool, fourButton: Bool)] = [
        (true, false), (false, false), (true, true), (false, true)
    ]

    /// Adds a combo, or replaces the one with the same id.
    mutating func saveCombo(_ combo: Combo) {
        var list = combos ?? []
        if let index = list.firstIndex(where: { $0.id == combo.id }) {
            list[index] = combo
        } else {
            list.append(combo)
        }
        combos = list
    }

    /// Removes a combo together with its position and visibility in every orientation.
    mutating func removeCombo(id: String) {
        let list = (combos ?? []).filter { $0.id != id }
        combos = list.isEmpty ? nil : list
        for key in Self.allOrientations {
            guard var orientation = orientation(portrait: key.portrait, fourButton: key.fourButton) else { continue }
            orientation.elements[id] = nil
            setOrientation(orientation, portrait: key.portrait, fourButton: key.fourButton)
        }
    }
}

extension GameOverlayLayoutData {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func encodedString() throws -> String {
        let data = try Self.encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ string: String) throws -> Self {
        try decoder.decode(Self.self, from: Data(string.utf8))
    }
}
