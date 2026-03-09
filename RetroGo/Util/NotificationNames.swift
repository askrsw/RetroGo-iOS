//
//  NotificationNames.swift
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

extension NSNotification.Name {
    static let deleteGameState     = NSNotification.Name(rawValue: "notif_deleteGameState")
    static let showInGameMessage   = NSNotification.Name(rawValue: "notif_showInGameMessage")
    static let languageChanged     = NSNotification.Name(rawValue: "notif_languageChanged")
    static let retroFolderImported = NSNotification.Name(rawValue: "notif_retroFolderImported")
    static let retroFileImported   = NSNotification.Name(rawValue: "notif_retroFileImported")
    static let romCountChanged     = NSNotification.Name(rawValue: "notif_romCountChanged")
    static let fileTagColorChanged = NSNotification.Name(rawValue: "notif_fileTagColorChanged")
    static let fileTagTitleChanged = NSNotification.Name(rawValue: "notif_fileTagTitleChanged")
    static let fileTagFileChanged  = NSNotification.Name(rawValue: "notif_fileTagFileChanged")
    static let fileTagDeleted      = NSNotification.Name(rawValue: "notif_fileTagDeleted")
    static let fileTagAdded        = NSNotification.Name(rawValue: "notif_fileTagAdded")
    static let fileCoreAssigned    = NSNotification.Name(rawValue: "notif_fileCoreAssigned")
}
