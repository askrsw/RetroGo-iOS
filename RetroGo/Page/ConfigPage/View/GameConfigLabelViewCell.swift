//
//  GameConfigLabelViewCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/24.
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

final class GameConfigLabelViewCell: GameConfigBaseViewCell {
    private let label = UILabel(frame: .zero)
    private var refreshObservation: NSKeyValueObservation?

    override var constrainTipLabelVertically: Bool {
        true
    }

    override func updateUI() {
        super.updateUI()

        guard let entry else { return }
        switch entry.ui {
        case .list, .controller:
            accessoryType = .disclosureIndicator
            label.text = entry.getListSelectedTitle?()
            if entry.enabled {
                label.textColor = .label
            } else {
                label.textColor = .secondaryLabel
            }
        default:
            accessoryType = .none
            label.text = nil
        }
    }

    override func configUI() {
        super.configUI()

        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)

        label.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        label.textAlignment = .right
        label.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(tipLabel.snp.trailing).offset(12)
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalTo(tipLabel.snp.centerY)
            make.top.greaterThanOrEqualToSuperview().offset(8)
            make.bottom.lessThanOrEqualToSuperview().offset(-8)
        }
    }

    override func entryChanged(new: GameConfigEntry?, old: GameConfigEntry?) {
        super.entryChanged(new: new, old: old)

        stopObserveRefresh()
        if let newEntry = new {
            startObserveRefresh(entry: newEntry)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopObserveRefresh()
        label.text = nil
    }

    deinit {
        stopObserveRefresh()
    }
}

private extension GameConfigLabelViewCell {
    func startObserveRefresh(entry: GameConfigEntry) {
        refreshObservation = entry.observe(\.refresh, options: [.new]) { [weak self, weak entry] (_, _) in
            guard let self, let entry else { return }
            guard let currentEntry = self.entry, currentEntry === entry else { return }
            switch entry.ui {
            case .list, .controller:
                self.label.text = entry.getListSelectedTitle?()
            default:
                break
            }
        }
    }

    func stopObserveRefresh() {
        refreshObservation?.invalidate()
        refreshObservation = nil
    }
}
