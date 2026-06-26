//
//  RGSectionHeaderView.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/28.
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

final class RGSectionHeaderView: UITableViewHeaderFooterView {
    class var className: String { String(describing: Self.self) }

    private let label = UILabel()
    private var leadingConstraint: Constraint?
    private var trailingConstraint: Constraint?

    var text: String? {
        didSet { label.text = text }
    }

    /// Horizontal inset for the title. Defaults to 0 so existing inset-grouped
    /// callers (which already provide their own card margins) are unaffected.
    /// Plain-style tables can set this to align the header with cell content.
    var horizontalInset: CGFloat = 0 {
        didSet {
            leadingConstraint?.update(offset: horizontalInset)
            trailingConstraint?.update(offset: -horizontalInset)
        }
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        configUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configUI() {
        contentView.backgroundColor = .clear

        label.font = UIFont.systemFont(ofSize: UIFont.labelFontSize, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 0

        contentView.addSubview(label)
        label.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            leadingConstraint = make.leading.equalToSuperview().constraint
            trailingConstraint = make.trailing.equalToSuperview().constraint
            make.bottom.equalToSuperview().offset(-8).priority(.high)
        }
    }
}
