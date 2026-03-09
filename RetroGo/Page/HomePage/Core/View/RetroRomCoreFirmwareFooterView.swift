//
//  RetroRomCoreFirmwareFooterView.swift
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

final class RetroRomCoreFirmwareFooterView: UICollectionReusableView {
    private lazy var label = YYLabel(frame: .zero)

    weak var holder: RetroRomCoreInfoViewController?

    var coreInfoItem: EmuCoreInfoItem? {
        didSet {
            subviews.forEach { $0.removeFromSuperview() }

            if coreInfoItem?.coreId == "ppsspp" {
                configUI()
                self.isHidden = false
            } else {
                self.isHidden = true
            }
        }
    }

    private func configUI() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle .lineSpacing = 3
        paragraphStyle .paragraphSpacing = 6
        paragraphStyle .lineBreakMode = .byWordWrapping

        let tipAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraphStyle.copy() as! NSParagraphStyle
        ]

        let tipText = Bundle.localizedString(forKey: "coreinfo_firmware_ppsspp_foot_tip")
        let restoreWord = Bundle.localizedString(forKey: "coreinfo_firmware_ppsspp_reload_word")

        let attributedTip = NSMutableAttributedString(string: tipText, attributes: tipAttributes)

        let nsText = tipText as NSString
        let range = nsText.range(of: restoreWord)
        if range.location != NSNotFound {
            let normalUnderline = YYTextDecoration(style: .single, width: 1, color: .mainColor)
            attributedTip.setTextUnderline(normalUnderline, range: range)
            attributedTip.setColor(UIColor.mainColor, range: range)

            let highlight = YYTextHighlight()
            let highlightUnderline = YYTextDecoration(style: .single, width: 1, color: .mainColor.withAlphaComponent(0.5))
            highlight.attributes = [
                NSAttributedString.Key.foregroundColor.rawValue: UIColor.mainColor.withAlphaComponent(0.5),
                YYTextUnderlineAttributeName: highlightUnderline,
            ]
            highlight.tapAction = { [weak self] containerView, text, range, rect in
                guard let self = self else { return }
                extractingWork()
            }
            attributedTip.setTextHighlight(highlight, range: range)
        }

        label.preferredMaxLayoutWidth = width
        label.attributedText = attributedTip
        label.numberOfLines = 0
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(8)
            make.bottom.equalToSuperview().offset(-10)
        }
    }

    private func extractingWork() {
        let title = Bundle.localizedString(forKey: "homepage_import_importing")
        let message = Bundle.localizedString(forKey: "coreinfo_firmware_ppsspp_importing")

        let indicatorView = RetroRomActivityView(mainTitle: title)
        indicatorView.install()

        indicatorView.activeMessage(message, title: title)

        DispatchQueue.global().async { [unowned self] in
            if let ret = coreInfoItem?.extractPPSSPPAssets() {
                DispatchQueue.main.async { [unowned self] in
                    if ret {
                        let message = Bundle.localizedString(forKey: "coreinfo_firmware_ppsspp_imported")
                        indicatorView.successMessage(message, title: title, canDismiss: true)

                        if let firmware = coreInfoItem?.firmwares?.first {
                            holder?.updateFirmware(firmware)
                        }
                    } else {
                        let message = Bundle.localizedString(forKey: "coreinfo_firmware_ppsspp_import_failed")
                        indicatorView.errorMessage(message, title: title, canDismiss: true)
                    }
                }
            }
        }

    }
}
