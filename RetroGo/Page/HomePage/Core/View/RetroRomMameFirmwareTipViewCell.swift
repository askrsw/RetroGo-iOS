//
//  RetroRomMameFirmwareTipViewCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

final class RetroRomMameFirmwareTipViewCell: UICollectionViewListCell {

    private let label = YYLabel()

    var core: EmuCoreInfoItem? {
        didSet {
            label.preferredMaxLayoutWidth = contentView.width - 32
            updateTipInfoText()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension RetroRomMameFirmwareTipViewCell {

    private func updateTipInfoText() {
        let text = Bundle.localizedString(forKey: "coreinfo_firmware_mame_tip")
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle .lineSpacing = 5
        paragraphStyle .paragraphSpacing = 15
        paragraphStyle .lineBreakMode = .byWordWrapping

        let normalFont = UIFont.systemFont(ofSize: UIFont.labelFontSize - 2)
        let labelColor = UIColor.secondaryLabel
        var textAttributes: [NSAttributedString.Key: Any] = [
            .font: normalFont,
            .foregroundColor: labelColor,
            .paragraphStyle: paragraphStyle.copy() as! NSParagraphStyle
        ]

        let attrText = NSMutableAttributedString(string: text, attributes: textAttributes)

        let iconSize: CGFloat = 14
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        if let symbolImage = UIImage(systemName: "plus", withConfiguration: config)?.withTintColor(.mainColor, renderingMode: .alwaysOriginal) {
            let renderer = UIGraphicsImageRenderer(size: symbolImage.size)
            let bitmapImage = renderer.image { context in
                symbolImage.draw(in: CGRect(origin: .zero, size: symbolImage.size))
            }
            let attachment = NSMutableAttributedString.attachmentString(withContent: bitmapImage, contentMode: .center, attachmentSize: bitmapImage.size, alignTo: UIFont.systemFont(ofSize: iconSize), alignment: .center)

            let range = (attrText.string as NSString).range(of: "plus")
            if range.location != NSNotFound {
                attrText.replaceCharacters(in: range, with: attachment)
            }
        }

        if let symbolImage = UIImage(systemName: "folder.badge.plus", withConfiguration: config)?.withTintColor(.mainColor, renderingMode: .alwaysOriginal) {
            let renderer = UIGraphicsImageRenderer(size: symbolImage.size)
            let bitmapImage = renderer.image { context in
                symbolImage.draw(in: CGRect(origin: .zero, size: symbolImage.size))
            }
            let attachment = NSMutableAttributedString.attachmentString(withContent: bitmapImage, contentMode: .center, attachmentSize: bitmapImage.size, alignTo: UIFont.systemFont(ofSize: iconSize), alignment: .center)

            let range = (attrText.string as NSString).range(of: "folder")
            if range.location != NSNotFound {
                attrText.replaceCharacters(in: range, with: attachment)
            }
        }

        if let count = core?.firmwares?.count, count > 0 {
            textAttributes[.foregroundColor] = UIColor.label
            textAttributes[.font] = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)

            let importedTip = Bundle.localizedString(forKey: "coreinfo_firmware_mame_already_imported")
            let attrImportedTip = NSAttributedString(string: importedTip, attributes: textAttributes)
            attrText.appendString("\n")
            attrText.append(attrImportedTip)
        }

        label.attributedText = attrText
    }

    private func configViews() {
        label.numberOfLines = 0
        label.textContainerInset = .init(top: 4, left: 0, bottom: 4, right: 0)

        // 建议：给 Cell 加一个淡淡的背景色或边框，使其看起来像一个 Tip 提示框
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        contentView.addSubview(label)
        label.snp.makeConstraints { make in
            // 增加左右缩进，使 Tip 看起来不那么拥挤
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        }
    }
}
