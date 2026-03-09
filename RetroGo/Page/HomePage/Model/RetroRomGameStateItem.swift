//
//  RetroRomGameStateItem.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

struct RetroRomGameStateItem {
    let rawName: String
    let coreId: String
    let showName: String?
    let romKey: String?
    let sha256: String?
    let createAt: Date

    var itemName: String {
        showName ?? rawName
    }

    var isAutoSaved: Bool {
        rawName == "auto_\(sha256 ?? coreId)"
    }

    var statePath: String {
        let stateFolder = AppConfig.shared.statesFolder + coreId
        return "\(stateFolder)/\(rawName).state"
    }

    var pngPath: String {
        if isAutoSaved {
            return AppConfig.shared.sharedAutoThumnailFolderPath + rawName + ".png"
        } else {
            let stateFolder = AppConfig.shared.statesFolder + coreId
            return "\(stateFolder)/\(rawName).png"
        }
    }
}

extension RetroRomGameStateItem {
    static let stateAutoSaveName = "auto_save"
}

