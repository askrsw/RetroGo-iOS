//
//  RGSectionFooterView.swift
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

final class RGSectionFooterView: UITableViewHeaderFooterView {
    class var className: String { String(describing: Self.self) }

    private let label = UILabel()

    var text: String? {
        didSet {
            guard let text else {
                label.attributedText = nil
                return
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            label.attributedText = NSAttributedString(string: text, attributes: [
                .paragraphStyle: style,
                .font: label.font!,
                .foregroundColor: label.textColor!
            ])
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

        label.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0

        contentView.addSubview(label)
        label.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().offset(-24).priority(.high)
        }
    }
}
