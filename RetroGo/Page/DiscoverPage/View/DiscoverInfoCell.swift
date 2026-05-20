//
//  DiscoverInfoCell.swift
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

// ---------------------------------------------------------------------------
// MARK: - DiscoverInfoCell
//
// A two-line cell: small secondary title on top, primary value below.
// Used for all key→value rows in the Game Detail page.
// Self-sizing via auto layout; set tableView.rowHeight = UITableView.automaticDimension.
// ---------------------------------------------------------------------------

final class DiscoverInfoCell: UITableViewCell {

    static let reuseID = "DiscoverInfoCell"

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font      = .systemFont(ofSize: 11)
        l.textColor = .tertiaryLabel
        return l
    }()

    private let valueLabel: UILabel = {
        let l = UILabel()
        l.font          = .systemFont(ofSize: 15)
        l.textColor     = .label
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        return l
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.equalToSuperview().offset(20)
            make.trailing.equalToSuperview().offset(-20)
        }

        valueLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.leading.trailing.equalTo(titleLabel)
            make.bottom.equalToSuperview().offset(-12)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configure

    func configure(title: String, value: String) {
        titleLabel.text = title.uppercased()
        valueLabel.text = value
    }
}

// ---------------------------------------------------------------------------
// MARK: - DiscoverDescriptionCell
//
// Full-width cell for the game description (可能很长).
// ---------------------------------------------------------------------------

final class DiscoverDescriptionCell: UITableViewCell {

    static let reuseID = "DiscoverDescriptionCell"

    // MARK: - Subviews

    private let bodyLabel: UILabel = {
        let l = UILabel()
        l.font          = .systemFont(ofSize: 14)
        l.textColor     = .secondaryLabel
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        return l
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        contentView.addSubview(bodyLabel)
        bodyLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.leading.equalToSuperview().offset(20)
            make.trailing.equalToSuperview().offset(-20)
            make.bottom.equalToSuperview().offset(-14)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configure

    func configure(text: String) {
        bodyLabel.text = text
    }
}
