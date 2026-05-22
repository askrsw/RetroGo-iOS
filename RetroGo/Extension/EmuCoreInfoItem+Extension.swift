//
//  EmuCoreInfoItem+Extension.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/22.
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

extension EmuCoreInfoItem {
    var coreIcon: IconRender.PlatformIconKey? {
        switch coreId {
        case "dosbox-pure": return .dos
        case "fceumm": return .nes
        case "gambatte": return .gb
        case "gearboy": return .gbc
        case "mednafen-psx": return .psx
        case "melondsds": return .ds
        case "mesen": return .nes
        case "mesen-s": return .snes
        case "mupen64plus-next": return .n64
        case "nestopia": return .nes
        case "pcsx-rearmed": return .psx
        case "ppsspp": return .psp
        case "vbam": return .gba
        case "yabause": return .saturn
        default:
            return nil
        }
    }
}
