//
//  GamePageOverlayConfig.swift
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

import RACoordinator

struct GamePageOverlayConfig: Codable, Equatable {
    let platformId: String
    let version: Int
    let portraitRefSize: GamePageOverlaySize
    let landscapeRefSize: GamePageOverlaySize
    let portraitPolarAnchor: GamePageOverlayInsets
    let landscapePolarAnchor: GamePageOverlayInsets
    let elements: [GamePageOverlayElement]
}

struct GamePageOverlayElement: Codable, Equatable {
    let id: String
    let type: GamePageOverlayElementType
    let geometry: GamePageOverlayGeometry
    let meta: [String: JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case geometry
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(GamePageOverlayElementType.self, forKey: .type)
        geometry = try container.decode(GamePageOverlayGeometry.self, forKey: .geometry)
        meta = try container.decodeIfPresent([String: JSONValue].self, forKey: .meta)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(geometry, forKey: .geometry)
        try container.encodeIfPresent(meta, forKey: .meta)
    }
}

enum GamePageOverlayElementType: String, Codable {
    case dpad
    case stick
    case button
    case fastButton = "fast-button"
    case digitalAnalogSwitch = "digital-analog-switch"
    case overlayCollapse = "overlay-collapse"
    case n64CButton = "n64-c-button"
    case ndsLayoutButton = "nds-layout-button"
}

struct GamePageOverlayGeometry: Codable, Equatable {
    let shape: GamePageOverlayShape?
    let size: GamePageOverlaySize
    let plainPortraitLayout: GamePageOverlayInsets
    let plainLandscapeLayout: GamePageOverlayInsets
    let polarPortraitLayout: GamePageOverlayPolar?
    let polarLandscapeLayout: GamePageOverlayPolar?
}

enum GamePageOverlayShape: String, Codable {
    case circle
    case capsule
    case rect
    case rounded
}

struct GamePageOverlaySize: Codable, Equatable {
    let width: Double
    let height: Double
}

struct GamePageOverlayInsets: Codable, Equatable {
    let top: Double?
    let left: Double?
    let bottom: Double?
    let right: Double?
    let centerX: Double?    // 元素左侧距离中心 X 的距离
    let centerY: Double?    // 元素底部距离中心 Y 的距离
}

struct GamePageOverlayPolar: Codable, Equatable {
    let theta: Double
    let radius: Double
}

enum GameOverlayPSActionButtonIcon: String, Codable, Equatable {
    case triangle, circle, cross, square
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .string(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .object(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
        }
    }
}

struct GamePageOverlayAction: Codable, Hashable, Equatable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var code: RetroArchJoypadCode {
        switch rawValue {
            case "UP": return .up
            case "DOWN": return .down
            case "LEFT": return .left
            case "RIGHT": return .right
            case "A": return .A
            case "B": return .B
            case "X": return .X
            case "Y": return .Y
            case "SELECT": return .select
            case "START": return .start
            case "L1": return .L1
            case "R1": return .R1
            case "L2": return .L2
            case "R2": return .R2
            case "L3": return .L3
            case "R3": return .R3
            default: return .none
        }
    }
}

extension GamePageOverlayElement {
    var isHidden: Bool {
        guard let v = meta?["is_hidden"], case .bool(let b) = v else {
            return false
        }
        return b
    }

    var title: String? {
        guard let v = meta?["title"], case .string(let s) = v else {
            return nil
        }
        return s
    }

    // Whether this button exists on the original hardware controller.
    // Default to false if the field is missing.
    var isNative: Bool {
        // We assume a button is not native unless explicitly marked as an extension.
        if case .bool(let value) = meta?["is_native"] {
            return value
        }
        return false
    }

    var isTurbo: Bool {
        guard let v = meta?["is_turbo"], case .bool(let b) = v else {
            return false
        }
        return b
    }

    // Determines if the turbo latch (auto-fire) should be activated
    // after a short tap (less than the long-press threshold).
    // Default to false: turbo requires a sustained press unless explicitly enabled.
    var isTurboAutoKeep: Bool {
        guard let v = meta?["is_turbo_auto_keep"], case .bool(let b) = v else {
            return false
        }
        return b
    }

    var binds: [GamePageOverlayAction] {
        guard let v = meta?["binds"], case .array(let array) = v else {
            return []
        }
        return array.compactMap({
            if case .string(let s) = $0 {
                return s
            } else {
                return nil
            }
        }).map({ GamePageOverlayAction($0) })
    }

    var psActionButtonIcon: GameOverlayPSActionButtonIcon? {
        guard let v = meta?["ps_action_button_icon"], case .string(let s) = v else {
            return nil
        }
        return GameOverlayPSActionButtonIcon(rawValue: s)
    }
}
