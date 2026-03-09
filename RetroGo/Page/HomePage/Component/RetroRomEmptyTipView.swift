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
import YYText
import SnapKit
import ObjcHelper

final class RetroRomEmptyTipView: UIView {
    let imageView = UIImageView(image: UIImage(systemName: "tray"))
    let label = YYLabel(frame: .zero)

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
        paragraph.lineSpacing = 5.0
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
            .font: UIFont.systemFont(ofSize: UIFont.labelFontSize)
        ]

        let tip = Bundle.localizedString(forKey: "homepage_empty_tip")
        label.attributedText = NSAttributedString(string: tip, attributes: attributes)
    }

    private func configUI() {
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(30)
            make.size.equalTo(CGSize(width: 120, height: 120))
        }

        label.numberOfLines = 0
        label.textVerticalAlignment = .top
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.trailing.equalToSuperview().offset(-20)
            make.top.equalTo(imageView.snp.bottom).offset(20)
            make.bottom.equalToSuperview()
        }
    }
}
