//
//  RetroRomEmptyTipView.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/25.
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
import ObjcHelper

final class RetroRomEmptyTipView: UIView {
    let imageView = UIImageView(image: UIImage(systemName: "tray"))
    let titleLabel = UILabel()
    let tipLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configUI()
        updateTipText()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTipText() {
        let paragraph: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraph.alignment = .center
        paragraph.lineSpacing = 4.0
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraph,
            .font: UIFont.systemFont(ofSize: 15, weight: .regular)
        ]

        titleLabel.text = Bundle.localizedString(forKey: "homepage_empty_title")

        let tip = Bundle.localizedString(forKey: "homepage_empty_tip")
        tipLabel.attributedText = NSAttributedString(string: tip, attributes: attributes)
    }

    private func configUI() {
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(10)
            make.size.equalTo(CGSize(width: 120, height: 120))
        }

        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.equalTo(imageView.snp.bottom).offset(18)
        }

        tipLabel.numberOfLines = 0
        tipLabel.lineBreakMode = .byWordWrapping
        tipLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(tipLabel)
        tipLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.bottom.lessThanOrEqualToSuperview()
        }
    }
}
