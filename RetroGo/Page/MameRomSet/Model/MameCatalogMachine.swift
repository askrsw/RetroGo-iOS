//
//  MameCatalogMachine.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/26.
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

/// One `<machine>` of the MAME core's -listxml: a game set, a BIOS set or a device.
/// Only the fields the romset manager needs are kept.
struct MameCatalogMachine {
    struct Rom: Hashable {
        /// File name inside the set's zip.
        var name: String
        var size: Int64
        /// Nil for `nodump` entries.
        var crc: UInt32?
        var sha1: String?
        /// Non-nil when the file actually lives in the parent/BIOS set, under this name.
        var merge: String?
        /// BIOS option this file belongs to; nil means every option needs it.
        var bios: String?
        /// good / baddump / nodump
        var status: String
        var optional: Bool
    }

    struct Disk: Hashable {
        var name: String
        var sha1: String?
        var merge: String?
        var status: String
        var optional: Bool
    }

    var name: String
    var description: String?
    var year: String?
    var manufacturer: String?
    var cloneOf: String?
    var romOf: String?
    var isBios = false
    var isDevice = false
    var runnable = true
    /// good / imperfect / preliminary; nil for devices.
    var driverStatus: String?
    /// The BIOS option MAME uses when none is selected: the one marked
    /// `default="yes"`, otherwise the first listed.
    var defaultBios: String?

    /// Duplicates (the same file loaded into several regions) are already removed.
    var roms: [Rom] = []
    var disks: [Disk] = []
    /// `<device_ref>` names in listing order, without duplicates.
    var devices: [String] = []

    init(name: String) {
        self.name = name
    }
}
