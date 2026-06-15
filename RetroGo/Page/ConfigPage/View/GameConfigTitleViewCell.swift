//
//  GameConfigTitleViewCell.swift
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
import SnapKit

final class GameConfigTitleViewCell: GameConfigBaseViewCell {
    let titleLabel = UILabel(frame: .zero)
    private lazy var detailButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "info.circle"), for: .normal)
        button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        button.tintColor = .label
        button.addTarget(self, action: #selector(detailButtonTapAction(_:)), for: .touchUpInside)
        button.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        return button
    }()

    override func updateUI(aniamted: Bool) {
        super.updateUI(aniamted: aniamted)
        titleLabel.text = entry?.getStringValue?()
        if entry?.detailButtonTapHandler != nil {
            accessoryView = detailButton
        } else {
            accessoryView = nil
        }
    }

    override func configUI() {
        super.configUI()

        titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        titleLabel.numberOfLines = 0
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(tipLabel.snp.trailing).offset(10)
            make.firstBaseline.equalTo(tipLabel.snp.firstBaseline)
            make.bottom.equalToSuperview().offset(-12)
            make.trailing.equalToSuperview().offset(-20)
        }
    }
}

extension GameConfigTitleViewCell {
    @objc
    private func detailButtonTapAction(_ sender: UIButton) {
        Vibration.selection.vibrate()
        entry?.detailButtonTapHandler?()
    }
}
