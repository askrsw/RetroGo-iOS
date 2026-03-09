//
//  GameStateTableViewCell.swift
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

final class GameStateTableViewCell: UITableViewCell {
    static let cellHeight: CGFloat = 60

    let thumbnailView = UIImageView(frame: .zero)
    let titleTextField = UITextField(frame: .zero)
    let dateLabel  = UILabel(frame: .zero)

    let activityView = UIActivityIndicatorView(style: .medium)
    let deleteButton = UIButton(type: .system)

    var item: RetroRomGameStateItem? {
        didSet {
            if let item = item {
                if item.isAutoSaved {
                    titleTextField.text = Bundle.localizedString(forKey: "gamepage_autosave")
                    titleTextField.isEnabled = false
                } else {
                    titleTextField.text = item.itemName
                    titleTextField.isEnabled = true
                }
                dateLabel.text = Self.dateFormatter.string(from: item.createAt)

                loadThumbnail()
            } else {
                thumbnailView.image = nil
                titleTextField.text = nil
                dateLabel.text      = nil

                titleTextField.isEnabled = false
            }
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        thumbnailView.contentMode = .scaleAspectFill
        contentView.addSubview(thumbnailView)
        thumbnailView.snp.makeConstraints { make in
            make.leading.equalTo(20)
            make.top.equalTo(5)
            make.bottom.equalTo(-5)
            make.height.equalTo(thumbnailView.snp.width).multipliedBy(240.0 / 256)
        }

        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = .gray
        deleteButton.addTarget(self, action: #selector(deleteAction(_:)), for: .touchUpInside)
        contentView.addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.trailing.equalTo(-20)
            make.height.equalTo(24)
            make.width.equalTo(24)
            make.centerY.equalToSuperview()
        }

        titleTextField.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize + 1)
        titleTextField.delegate = self
        titleTextField.returnKeyType = .done
        contentView.addSubview(titleTextField)
        titleTextField.snp.makeConstraints { make in
            make.leading.equalTo(thumbnailView.snp.trailing).offset(12)
            make.trailing.equalTo(deleteButton.snp.leading).offset(-12)
            make.top.equalTo(thumbnailView)
        }

        dateLabel.numberOfLines = 1
        dateLabel.textColor = .gray
        dateLabel.font = UIFont.italicSystemFont(ofSize: UIFont.labelFontSize - 3)
        contentView.addSubview(dateLabel)
        dateLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleTextField)
            make.trailing.equalTo(titleTextField)
            make.bottom.equalTo(thumbnailView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension GameStateTableViewCell {
    static let dateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    @objc
    private func deleteAction(_ sender: UIButton) {
        guard let item = item else {
            return
        }

        if let parent = self.viewController as? GameStateListViewController {
            parent.deleteGameState(item)
        }
    }

    private func loadThumbnail() {
        thumbnailView.image = nil
        if activityView.superview == nil {
            thumbnailView.addSubview(activityView)
            activityView.snp.makeConstraints { make in
                make.center.equalToSuperview()
            }
        }
        activityView.isHidden = false
        activityView.startAnimating()

        guard let item = item else {
            return
        }

        DispatchQueue.global().async { [self] in
            if let png = UIImage(contentsOfFile: item.pngPath) {
                DispatchQueue.main.async {  [self] in
                    activityView.stopAnimating()
                    activityView.isHidden = true
                    thumbnailView.image = png
                }
            } else {
                DispatchQueue.main.async {  [self] in
                    activityView.stopAnimating()
                    activityView.isHidden = true
                    thumbnailView.image = UIImage(systemName: "archivebox")
                }
            }
        }
    }
}

extension GameStateTableViewCell: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if let parent = self.viewController as? GameStateListViewController {
            parent.activeTextField = textField
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let name = textField.text ?? ""
        textField.resignFirstResponder()
        DispatchQueue.global().async { [weak self] in
            guard let item = self?.item else {
                return
            }
            if RetroRomFileManager.shared.updateGameStateShowName(name, coreId: item.coreId, sha256: item.sha256, fileName: item.rawName) {
                DispatchQueue.main.async {
                    if let parent = self?.viewController as? GameStateListViewController {
                        let item = RetroRomGameStateItem(rawName: item.rawName, coreId: item.coreId, showName: name, romKey: item.romKey, sha256: item.sha256, createAt: item.createAt)
                        parent.updateGameState(item)
                    }
                }
            }
        }
        return true
    }
}
