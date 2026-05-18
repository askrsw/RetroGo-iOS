//
//  RetroArchGamePauseToken.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/15.
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

import ObjectiveC
import RACoordinator

@MainActor
final class RetroArchGamePauseToken {
    private var didPause = false

    init() {
        didPause = RetroArchX.shared().pause()
    }

    deinit {
        if didPause {
            _ = RetroArchX.shared().resume()
        }
    }
}

private var retroArchPauseTokenKey: UInt8 = 0

extension UIAlertController {
    static func gamePausedAlert(
        title: String?,
        message: String?,
        preferredStyle: UIAlertController.Style = .alert
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: preferredStyle)
        let token = RetroArchGamePauseToken()
        objc_setAssociatedObject(alert, &retroArchPauseTokenKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return alert
    }
}
