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

/// Device class a layout belongs to. iPhone and iPad layouts are independent
/// because the space around the game screen differs between them.
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
    static let currentVersion = 2

    var version: Int = Self.currentVersion
    var portrait: Orientation?
    var landscape: Orientation?
    /// Combo buttons the user made. What they press is shared by every
    /// orientation; where each shows, and whether, is kept per orientation in
    /// `elements` like any other control. Each definition is self-contained;
    /// migrated IDs never require a lookup in a built-in recommendation.
    var combos: [Combo]?
    /// Definitions belong to this layout; positions reference their local IDs.
    var macros: [GameOverlayMacro]?

    var hasValidMacros: Bool {
        let definitions = macros ?? []
        let ids = definitions.map(\.id)
        return Set(ids).count == ids.count && definitions.allSatisfy { !$0.id.isEmpty && $0.isValid }
    }

    struct Orientation: Codable, Equatable {
        /// Keyed by overlay element id (`a`, `left-dpad`, `start`...).
        var elements: [String: Element] = [:]
        /// Keyed by group name; a group moves and scales its members together.
        var groups: [String: Group] = [:]
        /// Slot ids come from bundle JSON; an empty string explicitly vacates a slot.
        var slots: [String: String]?

        var isEmpty: Bool { elements.isEmpty && groups.isEmpty && (slots?.isEmpty ?? true) }
    }

    struct Element: Codable, Equatable {
        /// Plain position replacing the JSON one; an element with its own
        /// position no longer follows the polar (arc) layout or its group.
        var layout: GamePageOverlayInsets?
        /// Size multiplier on top of the JSON size.
        var scale: Double?
        /// Rotation in degrees retained when taking a member out of its group.
        var rotation: Double?
        /// Visibility override for controls allowed by `isHideableInCustomLayout`.
        var hidden: Bool?

        var isEmpty: Bool { layout == nil && scale == nil && hidden == nil && rotation == nil }
    }

    struct Group: Codable, Equatable {
        var offsetX: Double = 0
        var offsetY: Double = 0
        var scale: Double?
        var fan: Fan?

        var isEmpty: Bool { offsetX == 0 && offsetY == 0 && scale == nil && fan == nil }
    }

    struct Fan: Codable, Equatable {
        var radiusScale: Double = 1
        var thetaOffset: Double = 0
        var spreadScale: Double = 1
        var ringOffset: Double = 0

        var isDefault: Bool { self == Self() }
        func adjusted(_ polar: GamePageOverlayPolar, centerTheta: Double, innerRadius: Double) -> GamePageOverlayPolar {
            let radius = polar.radius * min(1.8, max(0.5, radiusScale))
                + (polar.radius > innerRadius + 1 ? min(100, max(-60, ringOffset)) : 0)
            return GamePageOverlayPolar(theta: centerTheta + (polar.theta - centerTheta) * min(2, max(0.5, spreadScale))
                + min(90, max(-90, thetaOffset)), radius: max(1, radius))
        }
    }

    struct Combo: Codable, Equatable {
        static let idPrefix = "user-combo-"
        static let keyRange = 1...4

        var id: String
        /// RetroPad buttons (`A`, `L1`, `START`...), the vocabulary of the overlay JSON `binds`.
        var binds: [String]
        var turbo: Bool

        /// Canonical identity for a newly created button set, independent of
        /// selection order and turbo. Keep an existing id when editing it.
        static func makeId(binds: [String], reservedIds: Set<String> = []) -> String {
            let base = idPrefix + Set(binds).sorted().map { $0.lowercased() }.joined(separator: "-")
            var id = base
            var suffix = 2
            // An edited button keeps its identity even if its binds change.
            while reservedIds.contains(id) {
                id = "\(base)-\(suffix)"
                suffix += 1
            }
            return id
        }
    }

    init() { }

    func orientation(portrait isPortrait: Bool) -> Orientation? {
        isPortrait ? portrait : landscape
    }

    mutating func setOrientation(_ value: Orientation?, portrait isPortrait: Bool) {
        let stored = (value?.isEmpty ?? true) ? nil : value
        if isPortrait { portrait = stored } else { landscape = stored }
    }
}

extension GameOverlayLayoutData {
    private static let allOrientations = [true, false]

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
            guard var orientation = orientation(portrait: key) else { continue }
            orientation.elements[id] = nil
            for slot in orientation.slots?.keys.filter({ orientation.slots?[$0] == id }) ?? [] { orientation.slots?[slot] = "" }
            setOrientation(orientation, portrait: key)
        }
    }

    /// Delete the definition and every orientation's placement/slot reference.
    mutating func removeMacro(id: String) {
        let remaining = (macros ?? []).filter { $0.id != id }
        macros = remaining.isEmpty ? nil : remaining
        for portrait in Self.allOrientations {
            guard var orientation = orientation(portrait: portrait) else { continue }
            orientation.elements[id] = nil
            for slot in orientation.slots?.keys.filter({ orientation.slots?[$0] == id }) ?? [] {
                orientation.slots?[slot] = ""
            }
            setOrientation(orientation, portrait: portrait)
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
