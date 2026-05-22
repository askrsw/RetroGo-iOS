//
//  RetroRomCoreItemTableViewCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/26.
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
import YYText
import SnapKit
import ObjcHelper
import RACoordinator

final class RetroRomCoreItemTableViewCell: UITableViewCell {
    let iconImageView = UIImageView(frame: .zero)
    let titleLabel = YYLabel(frame: .zero)
    let subtitleLabel = YYLabel(frame: .zero)

    private(set) var tailMarkImageView: UIImageView?

    var coreInfoItem: EmuCoreInfoItem? {
        didSet {
            guard let item = coreInfoItem else {
                return
            }

            titleLabel.text = item.coreName
            if let systemName = item.systemName {
                subtitleLabel.text = "System: " + systemName
            }
            updateIconImage(for: item)
        }
    }

    var check: Bool = false {
        didSet {
            guard check != oldValue else { return }
            if check {
                self.accessoryType = .checkmark
            } else {
                self.accessoryType = .none
            }
        }
    }

    class var className: String {
        String(describing: Self.self)
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configViews() {
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .label
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.top.equalToSuperview().offset(15)
            make.bottom.equalToSuperview().offset(-15)
            make.size.equalTo(CGSize(width: 30, height: 30))
        }

        titleLabel.textColor = .label
        titleLabel.textVerticalAlignment = .top
        titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconImageView.snp.trailing).offset(10)
            make.trailing.equalTo(contentView.snp.trailing).offset(-20)
            make.top.equalToSuperview().offset(10)
            make.height.equalTo(30 - 10)
        }

        subtitleLabel.textVerticalAlignment = .bottom
        subtitleLabel.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabel
        contentView.addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.trailing.equalTo(titleLabel)
            make.bottom.equalToSuperview().offset(-10)
            make.height.equalTo(30 - 10)
        }
    }

    private func updateIconImage(for item: EmuCoreInfoItem) {
        // Use the explicit per-core mapping from EmuCoreInfoItem+Extension.
        // Fall back to the chip glyph for the synthetic "no core" placeholder
        // and any core that hasn't been mapped yet.
        if let key = item.coreIcon {
            let icon = IconRender.shared.platformIcon(
                key: key,
                size: CGSize(width: 30, height: 30)
            )
            iconImageView.image = icon
        } else {
            iconImageView.tintColor = .label
            iconImageView.image = UIImage(systemName: "cpu.fill")
        }
    }
}
