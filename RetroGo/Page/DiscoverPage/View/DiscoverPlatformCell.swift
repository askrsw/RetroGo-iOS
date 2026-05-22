//
//  DiscoverPlatformCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/20.
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
import RACoordinator

final class DiscoverPlatformCell: UITableViewCell {

    static let reuseID = "DiscoverPlatformCell"
    static let rowHeight: CGFloat = 64

    // MARK: - Subviews

    private let displayNameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.textColor = .label
        return l
    }()

    private let manufacturerLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        return l
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        l.textColor = .tertiaryLabel
        l.textAlignment = .right
        return l
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        let stack = UIStackView(arrangedSubviews: [displayNameLabel, manufacturerLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        contentView.addSubview(iconView)
        contentView.addSubview(stack)
        contentView.addSubview(countLabel)

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 32, height: 32))
        }

        stack.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(14)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(countLabel.snp.leading).offset(-20)
        }

        countLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-4)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Manufacturer fallback
    //
    // Some rdb names have no "Manufacturer - Platform" format (e.g. "DOS", "MAME"),
    // so manufacturer parses as empty. Provide display values for known cases.
    private static let manufacturerFallback: [String: String] = [
        "DOS":  "Microsoft",
        "MAME": "Arcade",
    ]

    // MARK: - Configure

    func configure(with platform: RAPlatformItem) {
        displayNameLabel.text = platform.displayName

        let mfr = platform.manufacturer.isEmpty
            ? Self.manufacturerFallback[platform.displayName]
            : platform.manufacturer
        manufacturerLabel.text = mfr

        let count = platform.gameCount
        countLabel.text = count > 0
            ? String(format: "%d", count)
            : nil

        // Explicit rdbName → icon mapping lives in RAPlatformItem+Extension.
        // If a future rdb is added without a mapping, the icon view simply
        // stays empty rather than showing a guessed/wrong icon.
        if let key = platform.platformIcon {
            iconView.image = IconRender.shared.platformIcon(
                key: key,
                size: CGSize(width: 32, height: 32)
            )
        } else {
            iconView.image = nil
        }
    }
}
