//
//  GameConfigSwitchViewCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/18.
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

final class GameConfigSwitchViewCell: GameConfigBaseViewCell {
    let `switch` = UISwitch(frame: .zero)

    override var constrainTipLabelVertically: Bool {
        true
    }

    override func updateUI() {
        super.updateUI()
        
        `switch`.isEnabled = config?.enabled ?? true
        `switch`.isOn = config?.getBoolValue?() ?? false
    }

    override func configUI() {
        super.configUI()
        `switch`.onTintColor = .mainColor
        `switch`.addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)
        accessoryView = `switch`
    }
}

extension GameConfigSwitchViewCell {
    @objc
    private func switchValueChanged(_ sender: UISwitch) {
        config?.setBoolValue?(sender.isOn)
    }
}
