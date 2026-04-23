//
//  GameConfigSegmentViewCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/20.
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

final class GameConfigSegmentViewCell: GameConfigBaseViewCell {
    let segmentControl = UISegmentedControl(frame: .zero)

    override func updateUI() {
        super.updateUI()

        segmentControl.isEnabled = config?.enabled ?? true
        segmentControl.removeAllSegments()

        if let array = config?.getSegmentArray?() {
            for item in array {
                switch item {
                case .image(let img):
                    segmentControl.insertSegment(with: img, at: segmentControl.numberOfSegments, animated: false)
                case .text(let text):
                    segmentControl.insertSegment(withTitle: text, at: segmentControl.numberOfSegments, animated: false)
                }
            }
        }

        segmentControl.sizeToFit()

        guard let selectedIndex = config?.getSegmentSelectedIndex?(), segmentControl.numberOfSegments > 0 else {
            segmentControl.selectedSegmentIndex = UISegmentedControl.noSegment
            return
        }

        let maxIndex = segmentControl.numberOfSegments - 1
        segmentControl.selectedSegmentIndex = min(max(selectedIndex, 0), maxIndex)
    }

    override func configUI() {
        super.configUI()

        segmentControl.addTarget(self, action: #selector(segmentIndexValueChanged(_:)), for: .valueChanged)
        segmentControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        segmentControl.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(segmentControl)
        segmentControl.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(tipLabel.snp.trailing).offset(12)
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalTo(tipLabel.snp.centerY)
            make.top.greaterThanOrEqualToSuperview().offset(8)
            make.bottom.lessThanOrEqualToSuperview().offset(-8)
        }
    }
}

extension GameConfigSegmentViewCell {
    @objc
    private func segmentIndexValueChanged(_ sender: UISegmentedControl) {
        config?.setSegmentSelectedIndex?(sender.selectedSegmentIndex)
    }
}
