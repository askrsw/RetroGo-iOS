//
//  GameCheatItem.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/6.
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
import ObjcHelper

/// Which mechanism applies the cheat — mirrors `RACheatHandler` / `CHEAT_HANDLER_TYPE_*`.
/// EMU = code string handed to the core; RETRO = RetroArch writes memory itself.
enum GameCheatHandler: Int {
    case emu   = 0
    case retro = 1
}

/// The user-facing kind of cheat. This is the editor's top-level choice and the
/// stored identity. Two kinds are EMU (a code string the core parses) and differ
/// only in format/authoring; the third is RETRO (structured memory write):
/// - `numeric` (数值): an `address:value` code, e.g. `05C6:02`.
/// - `secret`  (秘籍): an encrypted letter code — Game Genie / PAR / GameShark.
/// - `memory`  (内存): structured address/value with write mode, size, etc.
///
/// `numeric` and `memory` are numerically equivalent (address+value) and the
/// editor links them; `secret` cannot be decoded to an address, so it never links.
enum GameCheatKind: Int {
    case numeric = 0
    case secret  = 1
    case memory  = 2

    var handler: GameCheatHandler {
        self == .memory ? .retro : .emu
    }
}

/// RETRO write mode — mirrors `enum cheat_type` (`cheat_manager.h`). The first
/// three are the everyday ones; the `runNextIf*` conditionals chain to the next
/// cheat and are surfaced only in the editor's advanced section.
enum GameCheatType: Int, CaseIterable {
    case setToValue   = 1
    case increase     = 2
    case decrease     = 3
    case runNextIfEq  = 4
    case runNextIfNeq = 5
    case runNextIfLt  = 6
    case runNextIfGt  = 7
}

/// RETRO memory width — raw value is `memory_search_size` (`2^raw` bits): the
/// byte sizes are the common picks; the sub-byte bit sizes are advanced-only.
enum GameCheatMemorySize: Int, CaseIterable {
    case bit1  = 0
    case bit2  = 1
    case bit4  = 2
    case byte1 = 3   // 8-bit
    case byte2 = 4   // 16-bit
    case byte4 = 5   // 32-bit
}

/// Rumble config (mirrors the `item_cheat.rumble_*` config fields). RESERVED:
/// not surfaced or applied in 1.6.0 (the `virtual_joypad_rumble` sink is still a
/// stub). Persisted as one JSON blob (`rumble_config_blob`) so enabling rumble
/// later needs no migration. Runtime rumble state (prev_value/initialized/
/// end_times) is intentionally NOT stored.
struct GameCheatRumbleConfig: Codable, Equatable {
    var type: Int = 0
    var value: Int = 0
    var port: Int = 0
    var primaryStrength: Int = 0
    var primaryDuration: Int = 0
    var secondaryStrength: Int = 0
    var secondaryDuration: Int = 0

    static let none = GameCheatRumbleConfig()
    var isDefault: Bool { self == .none }
}

/// One user-created cheat for a specific game. Full mirror of `struct item_cheat`
/// (minus the engine-internal `idx` and the runtime rumble state). EMU cheats use
/// `code`; RETRO cheats use the structured fields.
struct GameCheatItem {
    /// User cheats only need a stable row id inside `romcheat`; keep it aligned
    /// with RetroGo's short-key style instead of storing a 36-byte UUID string.
    static func makeID() -> String {
        NSString.randomString(10, caseInsensitive: false)
    }

    let id: String
    let romKey: String
    let coreId: String

    var kind: GameCheatKind
    var desc: String
    var enabled: Bool
    var sortIndex: Int

    /// Derived from `kind`: numeric/secret → EMU, memory → RETRO.
    var handler: GameCheatHandler { kind.handler }

    // EMU (numeric / secret)
    var code: String

    // RETRO
    var cheatType: GameCheatType
    var memorySize: GameCheatMemorySize
    var address: Int
    var value: Int
    var addressMask: Int
    var bigEndian: Bool
    var repeatCount: Int
    var repeatAddToValue: Int
    var repeatAddToAddress: Int

    // Reserved (rumble — not used in 1.6.0)
    var rumble: GameCheatRumbleConfig

    let createAt: Date
    var updateAt: Date

    init(
        id: String = GameCheatItem.makeID(),
        romKey: String,
        coreId: String,
        kind: GameCheatKind = .numeric,
        desc: String,
        enabled: Bool,
        sortIndex: Int,
        code: String = "",
        cheatType: GameCheatType = .setToValue,
        memorySize: GameCheatMemorySize = .byte1,
        address: Int = 0,
        value: Int = 0,
        addressMask: Int = 0,
        bigEndian: Bool = false,
        repeatCount: Int = 1,
        repeatAddToValue: Int = 0,
        repeatAddToAddress: Int = 1,
        rumble: GameCheatRumbleConfig = .none,
        createAt: Date = Date(),
        updateAt: Date = Date()
    ) {
        self.id = id
        self.romKey = romKey
        self.coreId = coreId
        self.kind = kind
        self.desc = desc
        self.enabled = enabled
        self.sortIndex = sortIndex
        self.code = code
        self.cheatType = cheatType
        self.memorySize = memorySize
        self.address = address
        self.value = value
        self.addressMask = addressMask
        self.bigEndian = bigEndian
        self.repeatCount = repeatCount
        self.repeatAddToValue = repeatAddToValue
        self.repeatAddToAddress = repeatAddToAddress
        self.rumble = rumble
        self.createAt = createAt
        self.updateAt = updateAt
    }

    func replacingID(_ id: String) -> GameCheatItem {
        GameCheatItem(
            id: id,
            romKey: romKey,
            coreId: coreId,
            kind: kind,
            desc: desc,
            enabled: enabled,
            sortIndex: sortIndex,
            code: code,
            cheatType: cheatType,
            memorySize: memorySize,
            address: address,
            value: value,
            addressMask: addressMask,
            bigEndian: bigEndian,
            repeatCount: repeatCount,
            repeatAddToValue: repeatAddToValue,
            repeatAddToAddress: repeatAddToAddress,
            rumble: rumble,
            createAt: createAt,
            updateAt: updateAt
        )
    }
}
