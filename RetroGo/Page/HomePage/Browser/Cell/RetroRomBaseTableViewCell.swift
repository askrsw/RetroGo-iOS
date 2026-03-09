//
//  RetroRomBaseTableViewCell.swift
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
import ObjcHelper

class RetroRomBaseTableViewCell: UITableViewCell {
    static let rowHeight: CGFloat = 60

    let thumbnailView = UIImageView(frame: .zero)
    let titleLabel = UILabel(frame: .zero)
    let infoLabel  = UILabel(frame: .zero)

    private(set) var titleEditor: UITextView?
    private(set) var titleAttributes: [NSAttributedString.Key: Any]

    var item: RetroRomBaseItem? {
        didSet {
            oldValue?.removeObserver(self, forKeyPath: "pulseText")
            oldValue?.removeObserver(self, forKeyPath: "pulseImage")

            item?.addObserver(self, forKeyPath: "pulseText", context: nil)
            item?.addObserver(self, forKeyPath: "pulseImage", context: nil)

            updateThumbnail()
            updateTitleLabel()
            updateInfoLabel()
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail
        self.titleAttributes = [
            .font: UIFont.systemFont(ofSize: UIFont.labelFontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle,
        ]
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        item?.removeObserver(self, forKeyPath: "pulseText")
        item?.removeObserver(self, forKeyPath: "pulseImage")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "pulseText" {
            updateTitleLabel()
            updateInfoLabel()
        } else if keyPath == "pulseImage" {
            updateThumbnail()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        titleLabel.sizeToFit()

        let height = Self.rowHeight - 6 - 6
        let width = height / 240 * 256
        thumbnailView.frame = CGRect(x: 20, y: 6, width: width, height: height)
        titleLabel.frame = CGRect(x: thumbnailView.maxX + 10, y: 6, width: self.width - thumbnailView.maxX - 10 - 20, height: titleLabel.height)

        infoLabel.sizeToFit()
        infoLabel.frame = CGRect(x: titleLabel.minX, y: self.height - 6 - infoLabel.height, width: titleLabel.width, height: infoLabel.height)
    }

    func updateThumbnail() {
        if let thumbnail = item?.thumbnail {
            thumbnailView.layer.borderWidth   = 0.5
            thumbnailView.layer.borderColor   = UIColor.gray.withAlphaComponent(0.5).cgColor
            thumbnailView.layer.shadowColor   = UIColor.gray.cgColor
            thumbnailView.layer.shadowOpacity = 0.5
            thumbnailView.layer.shadowRadius  = 1.5
            thumbnailView.contentMode = .scaleAspectFill

            thumbnailView.image = thumbnail
        } else {
            thumbnailView.layer.borderWidth   = 0
            thumbnailView.layer.borderColor   = UIColor.clear.cgColor
            thumbnailView.layer.shadowColor   = UIColor.clear.cgColor
            thumbnailView.layer.shadowOpacity = 0
            thumbnailView.layer.shadowRadius  = 0
            thumbnailView.contentMode = .scaleAspectFit

            guard let item = item else {
                thumbnailView.image = nil
                return
            }
            switch item.retroRomType {
                case .folder:
                    thumbnailView.image = UIImage(systemName: "folder.fill")
                case .file:
                    thumbnailView.image = UIImage(named: "Icon_file")
                default:
                    break
            }
        }
    }

    func updateTitleLabel() {
        if let title = item?.itemName {
            titleLabel.attributedText = NSAttributedString(string: title, attributes: titleAttributes)
        } else {
            titleLabel.attributedText = nil
        }
    }

    func updateInfoLabel() {
        guard let item = item else {
            infoLabel.attributedText = nil
            return
        }

        func makeInfoAtrributedText(name: String, value: String) {
            let tip = NSAttributedString(string: name, attributes: Self.infoTipAttributes)
            let text = NSAttributedString(string: value, attributes: Self.infoTextAttributes)
            let attributedString = NSMutableAttributedString()
            attributedString.append(tip)
            attributedString.append(text)
            infoLabel.attributedText = attributedString
        }

        if item.isFolder {
            let name = Bundle.localizedString(forKey: "homepage_add_date_colon")
            let value = item.createAtFullString
            return makeInfoAtrributedText(name: name, value: value)
        }

        let sortType = RetroRomHomePageState.shared.homeFileSortType

        switch sortType {
            case .fileNameAsc, .fileNameDesc, .addDateAsc, .addDateDesc:
                let name = Bundle.localizedString(forKey: "homepage_add_date_colon")
                let value = item.createAtFullString
                makeInfoAtrributedText(name: name, value: value)
            case .lastPlay:
                let value = (item as? RetroRomFileItem)?.lastPlayAtFullString ?? "-"
                let name = Bundle.localizedString(forKey: "homepage_last_play_colon")
                makeInfoAtrributedText(name: name, value: value)
            case .playTime:
                let value = (item as? RetroRomFileItem)?.playTimeString ?? "-"
                let name = Bundle.localizedString(forKey: "homepage_game_duration_colon")
                makeInfoAtrributedText(name: name, value: value)
        }
    }

    func editFileName() {
        if titleEditor != nil {
            return
        }

        RetroRomHomePageState.shared.couldShowItemMenu = false

        let editor = UITextView(frame: .zero)
        editor.textColor = .label
        editor.textAlignment = .left
        editor.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
        editor.backgroundColor = UIColor.systemBackground.withAlphaComponent(1.0)
        editor.tintColor = .accent
        editor.delegate  = self
        editor.returnKeyType = .done
        editor.text = titleLabel.text
        editor.frame = titleLabel.frame
        contentView.addSubview(editor)

        if let title = titleLabel.text as? NSString {
            let dotRange = title.range(of: ".")
            if dotRange.location != NSNotFound {
                editor.selectedRange = NSRange(location: 0, length: dotRange.location)
            } else {
                editor.selectedRange = NSRange(location: 0, length: title.length)
            }
        }
        editor.becomeFirstResponder()
        titleEditor = editor
    }
}

extension RetroRomBaseTableViewCell: UITextViewDelegate {
    func textViewDidEndEditing(_ textView: UITextView) {
        titleEditor?.removeFromSuperview()
        titleEditor = nil
        RetroRomHomePageState.shared.couldShowItemMenu = true
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            if textView.text != item?.showName {
                if let ret = item?.updateShowName(textView.text), ret {
                    let message = Bundle.localizedString(forKey: "homepage_rename_success")
                    AppToastManager.shared.toast(message, context: .ui, level: .success)
                } else {
                    let message = Bundle.localizedString(forKey: "homepage_operation_failed")
                    AppToastManager.shared.toast(message, context: .ui, level: .error)
                }
            }
            textView.resignFirstResponder()
            RetroRomHomePageState.shared.couldShowItemMenu = true
            return false
        } else {
            return true
        }
    }
}

extension RetroRomBaseTableViewCell {
    private static let infoTipAttributes: [NSAttributedString.Key: Any] = {
        let font = UIFont.systemFont(ofSize: UIFont.labelFontSize - 3)
        let color = UIColor(hex: 0x999999, alpha: 1.0)
        return [.font: font, .foregroundColor: color]
    }()

    private static let infoTextAttributes: [NSAttributedString.Key: Any] = {
        let font = UIFont.italicSystemFont(ofSize: UIFont.labelFontSize - 3)
        let color = UIColor(hex: 0x999999, alpha: 1.0)
        return [.font: font, .foregroundColor: color]
    }()

    private func configUI() {
        thumbnailView.layer.cornerRadius = 6.0
        thumbnailView.layer.masksToBounds = true
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        contentView.addSubview(thumbnailView)

        titleLabel.numberOfLines = 1
        titleLabel.textColor = UIColor.label
        contentView.addSubview(titleLabel)

        infoLabel.numberOfLines = 1
        contentView.addSubview(infoLabel)
    }
}

final class RetroRomFolderTableViewCell: RetroRomBaseTableViewCell {

}

final class RetroRomFileTableViewCell: RetroRomBaseTableViewCell {
    override func updateTitleLabel() {
        guard let item = item as? RetroRomFileItem else {
            return super.updateTitleLabel()
        }

        let attributedTitle = NSAttributedString(string: item.itemName, attributes: titleAttributes)

        let tagIdArray = item.tagIdArray
        let tags = RetroRomFileManager.shared.fileTags(in: tagIdArray)
        if tags.count == 0 {
            titleLabel.attributedText = attributedTitle
        } else {
            let font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
            let attributedTags =  RetroRomFileTag.makeAttributedTagText(tags, attributes: titleAttributes, refFont: font)
            let attributedString = NSMutableAttributedString(attributedString: attributedTags)
            attributedString.append(attributedTitle)
            titleLabel.attributedText = attributedString
        }
    }
}

final class RetroRomParentFolderTableViewCell: UITableViewCell {
    static let rowHeight: CGFloat = 44

    let thumbnailView = YYLabel(frame: .zero)
    let titleLabel = YYLabel(frame: .zero)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        thumbnailView.text = "··"
        thumbnailView.textColor = .mainColor
        thumbnailView.textAlignment = .center
        thumbnailView.textVerticalAlignment = .center
        thumbnailView.font = UIFont.systemFont(ofSize: 40, weight: .bold)
        contentView.addSubview(thumbnailView)

        titleLabel.textAlignment = .left
        titleLabel.textVerticalAlignment = .center
        titleLabel.text = Bundle.localizedString(forKey: "homepage_parent_folder")
        titleLabel.textColor = .label
        contentView.addSubview(titleLabel)

        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            self?.titleLabel.text = Bundle.localizedString(forKey: "homepage_parent_folder")
        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let imgH: CGFloat = 36
        let imgW: CGFloat = (RetroRomBaseTableViewCell.rowHeight - 6 - 6) / 240 * 256
        let imgX: CGFloat = 20
        let imgY: CGFloat = (height - imgH) * 0.5
        thumbnailView.frame = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)

        titleLabel.frame = CGRect(x: thumbnailView.maxX + 10, y: imgY, width: width - 20 - thumbnailView.maxX - 10, height: imgH)
    }
}
