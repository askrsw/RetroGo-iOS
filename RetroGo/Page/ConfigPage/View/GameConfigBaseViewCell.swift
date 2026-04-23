//
//  GameConfigBaseViewCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/19.
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
import SnapKit

class GameConfigBaseViewCell: UITableViewCell {
    let tipLabel = UILabel(frame: .zero)

    private(set) var descButton: UIButton?

    var config: GameConfigItem? {
        didSet {
            updateUI()
        }
    }

    var constrainTipLabelVertically: Bool {
        false
    }

    required override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateUI() {
        tipLabel.text = config?.tip

        if let _ = config?.desc {
            if descButton == nil {
                let button = UIButton(type: .system)
                button.addTarget(self, action: #selector(descButtonTapped(_:)), for: .touchUpInside)
                button.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
                button.tintColor = .label
                contentView.addSubview(button)
                button.snp.makeConstraints { make in
                    make.leading.equalTo(tipLabel.snp.trailing).offset(12)
                    make.centerY.equalToSuperview()
                    make.size.equalTo(CGSize(width: 20, height: 20))
                }
            }
        } else {
            descButton?.removeFromSuperview()
            descButton = nil
        }
    }

    func configUI() {
        tipLabel.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
        tipLabel.numberOfLines = 1
        tipLabel.setContentHuggingPriority(.required, for: .horizontal)
        tipLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentView.addSubview(tipLabel)

        if constrainTipLabelVertically {
            tipLabel.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(20)
                make.top.equalToSuperview().offset(12)
                make.bottom.equalToSuperview().offset(-12)
                make.trailing.lessThanOrEqualToSuperview().offset(-20)
            }
        } else {
            tipLabel.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(20)
                make.top.equalToSuperview().offset(12)
            }
        }
    }
}

extension GameConfigBaseViewCell {
    @objc
    private func descButtonTapped(_ sender: UIButton) {
        Vibration.selection.vibrate()

        guard let desc = config?.desc else { return }
        let descView = GameConfigDescView(desc: desc)
        descView.install(source: sender)
    }
}
