//
//  GameConfigPercentageSliderCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/11/21.
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

import SnapKit
import UIKit

final class GameConfigPercentageSliderCell: GameConfigBaseViewCell {
    private let slider = UISlider()
    private let valueLabel = UILabel()
    private var savedPercentage = 0

    override func configUI() {
        super.configUI()
        selectionStyle = .none

        valueLabel.font = .monospacedDigitSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        contentView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.firstBaseline.equalTo(tipLabel)
            make.leading.greaterThanOrEqualTo(tipLabel.snp.trailing).offset(12)
            make.trailing.equalToSuperview().inset(20)
        }

        slider.tintColor = .mainColor
        slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(commitValue), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        contentView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.top.equalTo(tipLabel.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(12)
        }
    }

    override func updateUI(aniamted: Bool) {
        super.updateUI(aniamted: aniamted)
        savedPercentage = entry?.getPercentage?() ?? 0
        slider.maximumValue = Float(entry?.maximumPercentage ?? 100)
        slider.value = Float(savedPercentage)
        slider.isEnabled = entry?.enabled ?? false
        slider.accessibilityLabel = entry?.title
        updateLabel(savedPercentage)
    }

    private func updateLabel(_ percentage: Int) {
        let text = (Double(percentage) / 100).formatted(.percent.precision(.fractionLength(0)))
        valueLabel.text = text
        slider.accessibilityValue = text
    }

    @objc private func valueChanged() {
        updateLabel(Int(slider.value.rounded()))
        if !slider.isTracking { commitValue() }
    }

    @objc private func commitValue() {
        let percentage = Int(slider.value.rounded())
        if percentage != savedPercentage, entry?.setPercentage?(percentage) == true {
            savedPercentage = percentage
        }
        slider.value = Float(savedPercentage)
        updateLabel(savedPercentage)
    }
}
