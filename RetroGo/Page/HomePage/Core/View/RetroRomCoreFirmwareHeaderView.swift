//
//  RetroRomCoreFirmwareHeaderView.swift
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
import SnapKit
import ObjcHelper
import RACoordinator

final class RetroRomCoreFirmwareHeaderView: UICollectionReusableView {
    private lazy var label = UILabel(frame: .zero)
    private var folderButton: UIButton?
    private var plusButton: UIButton?

    weak var holder: RetroRomCoreInfoViewController?

    var coreInfoItem: EmuCoreInfoItem? {
        didSet {
            subviews.forEach { $0.removeFromSuperview() }
            if coreInfoItem != nil {
                configUI()
                self.isHidden = false
            } else {
                self.isHidden = true
            }
        }
    }

    private func configUI() {
        label.text = Bundle.localizedString(forKey: "coreinfo_firmwares")
        label.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        label.textColor = .secondaryLabel
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.bottom.equalToSuperview().offset(-10)
            make.top.equalToSuperview().offset(20).priority(.low)
        }

        if coreInfoItem?.coreId != "ppsspp" {
            let folderButton = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: UIFont.labelFontSize, weight: .medium)
            let icon = UIImage(systemName: "folder.badge.plus", withConfiguration: config)
            folderButton.setImage(icon, for: .normal)
            folderButton.tintColor = .mainColor
            folderButton.contentMode = .scaleAspectFill
            folderButton.addTarget(self, action: #selector(didTapFolderImportButton), for: .touchUpInside)
            addSubview(folderButton)
            folderButton.snp.makeConstraints { make in
                make.trailing.equalToSuperview()
                make.centerY.equalTo(label)
                make.height.equalTo(24)
                make.width.equalTo(28)
            }
            self.folderButton = folderButton

            if coreInfoItem?.coreId == "mame" {
                let plusButton = UIButton(type: .system)
                let icon = UIImage(systemName: "plus", withConfiguration: config)
                plusButton.setImage(icon, for: .normal)
                plusButton.tintColor = .mainColor
                plusButton.contentMode = .scaleAspectFill
                plusButton.addTarget(self, action: #selector(didTapFileImportButton), for: .touchUpInside)
                addSubview(plusButton)
                plusButton.snp.makeConstraints { make in
                    make.trailing.equalTo(folderButton.snp.leading).offset(-20)
                    make.centerY.equalTo(label)
                    make.height.equalTo(24)
                    make.width.equalTo(24)
                }

                self.plusButton = plusButton
            }
        }
    }

    @objc
    private func didTapFileImportButton() {
        Vibration.selection.vibrate()

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
        documentPicker.delegate = holder
        documentPicker.allowsMultipleSelection = false
        holder?.present(documentPicker, animated: true)
    }

    @objc
    private func didTapFolderImportButton() {
        Vibration.selection.vibrate()

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        documentPicker.delegate = holder
        documentPicker.allowsMultipleSelection = false
        holder?.present(documentPicker, animated: true)
    }
}
