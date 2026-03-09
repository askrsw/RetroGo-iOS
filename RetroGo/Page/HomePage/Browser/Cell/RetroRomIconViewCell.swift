//
//  RetroRomIconViewCell.swift
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

class RetroRomBaseIconViewCell: UICollectionViewCell {
    static let titleHeight: CGFloat = 40

    let imageView = UIImageView(frame: .zero)
    let imageViewHost = UIView(frame: .zero)
    fileprivate let titleLabel = TopAlignedLabel(frame: .zero)
    let infoLabel = UILabel(frame: .zero)

    private(set) var titleEditor: UITextView?
    private var imageViewSizeFactor: CGFloat = 0
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

    override init(frame: CGRect) {
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        self.titleAttributes = [
            .font: UIFont.systemFont(ofSize: UIFont.labelFontSize - 3),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle,
        ]
        super.init(frame: frame)
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

        imageViewHost.frame = CGRect(x: 0, y: 0, width: width, height: height - Self.titleHeight)
        let imgX = imageViewHost.width * imageViewSizeFactor
        let imgY = imageViewHost.height * imageViewSizeFactor
        let imgW = imageViewHost.width - imgX * 2
        let imgH = imageViewHost.height - imgY * 2
        imageView.frame = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)

        if infoLabel.text != nil {
            titleLabel.numberOfLines = 1
            titleLabel.sizeToFit()
            titleLabel.frame = CGRect(x: 0, y: imageViewHost.maxY + 5, width: width, height: titleLabel.height)
            infoLabel.frame = CGRect(x: 0, y: titleLabel.maxY + 5, width: width, height: self.height - titleLabel.maxY - 5)
        } else {
            titleLabel.numberOfLines = 2

            let titleHeight = self.height - 5 - imageViewHost.maxY
            titleLabel.frame = CGRect(x: 0, y: imageViewHost.maxY + 5, width: width, height: titleHeight)
            infoLabel.frame = .zero
        }
    }

    func updateThumbnail() {
        if let thumbnail = item?.thumbnail {
            imageView.layer.borderWidth   = 0.5
            imageView.layer.borderColor   = UIColor.gray.withAlphaComponent(0.5).cgColor
            imageView.layer.shadowColor   = UIColor.gray.cgColor
            imageView.layer.shadowOpacity = 0.5
            imageView.layer.shadowRadius  = 1.5
            imageView.contentMode         = .scaleAspectFill
            imageViewSizeFactor = 0

            imageView.image = thumbnail
        } else {
            imageView.layer.borderWidth   = 0
            imageView.layer.borderColor   = UIColor.clear.cgColor
            imageView.layer.shadowColor   = UIColor.clear.cgColor
            imageView.layer.shadowOpacity = 0
            imageView.layer.shadowRadius  = 0
            imageView.contentMode         = .scaleAspectFit
            imageViewSizeFactor = 0

            guard let item = item else {
                imageView.image = nil
                return
            }
            switch item.retroRomType {
                case .folder:
                    imageView.image = UIImage(systemName: "folder.fill")
                case .file:
                    imageView.image = UIImage(named: "Icon_file")
                default:
                    break
            }
        }

        let imgX = imageViewHost.width * imageViewSizeFactor
        let imgY = imageViewHost.height * imageViewSizeFactor
        let imgW = imageViewHost.width - imgX * 2
        let imgH = imageViewHost.height - imgY * 2
        imageView.frame = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
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
            infoLabel.text = nil
            return
        }

        switch RetroRomHomePageState.shared.homeFileSortType {
            case .fileNameAsc, .fileNameDesc:
                infoLabel.text = nil
            case .addDateAsc, .addDateDesc:
                infoLabel.text = item.createAtSimpleString
            case .lastPlay:
                if let file = item as? RetroRomFileItem {
                    if file.lastPlayAt != nil {
                        infoLabel.text = file.lastPlayAtSimpleString
                    } else {
                        infoLabel.text = nil
                    }
                } else {
                    infoLabel.text = nil
                }
            case .playTime:
                if let file = item as? RetroRomFileItem {
                    if file.playTime > 0 {
                        infoLabel.text = file.playTimeString
                    } else {
                        infoLabel.text = nil
                    }
                } else {
                    infoLabel.text = nil
                }
        }

        if infoLabel.text != nil {
            titleLabel.numberOfLines = 1
            titleLabel.sizeToFit()
            titleLabel.frame = CGRect(x: 0, y: imageViewHost.maxY + 5, width: width, height: titleLabel.height)
            infoLabel.frame = CGRect(x: 0, y: titleLabel.maxY + 5, width: width, height: self.height - titleLabel.maxY - 5)
        } else {
            titleLabel.numberOfLines = 2
            titleLabel.sizeToFit()

            let titleHeight = titleLabel.height // self.height - 5 - imageViewHost.maxY
            titleLabel.frame = CGRect(x: 0, y: imageViewHost.maxY + 5, width: width, height: titleHeight)
            infoLabel.frame = .zero
        }
    }

    func editFileName() {
        if titleEditor != nil {
            return
        }

        RetroRomHomePageState.shared.couldShowItemMenu = false

        let editor = UITextView(frame: .zero)
        editor.textColor = .label
        editor.textAlignment = .center
        editor.font = UIFont.systemFont(ofSize: UIFont.labelFontSize - 3)
        editor.backgroundColor = UIColor.systemBackground.withAlphaComponent(1.0)
        editor.tintColor = .accent
        editor.delegate  = self
        editor.returnKeyType = .done
        editor.text = titleLabel.text
        editor.contentInset = .zero
        editor.frame = CGRect(x: 0, y: imageView.maxY + 5, width: width, height: height - 5 - imageView.maxY)
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

extension RetroRomBaseIconViewCell {
    private func configUI() {
        contentView.addSubview(imageViewHost)

        imageView.layer.cornerRadius = 6.0
        imageView.layer.masksToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageViewHost.addSubview(imageView)

        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.contentMode = .top
        contentView.addSubview(titleLabel)

        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 1
        infoLabel.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
        infoLabel.textColor = UIColor(hex: 0x999999, alpha: 1.0)
        contentView.addSubview(infoLabel)
    }
}

extension RetroRomBaseIconViewCell: UITextViewDelegate {
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
                    let message = Bundle.localizedString(forKey: "homepage_rename_failed")
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

final class RetroRomFileIconViewCell: RetroRomBaseIconViewCell {
    var firstTag: RetroRomFileTag?

    var wrappedItem: RetroRomFileItemWrapper? {
        didSet {
            self.firstTag = wrappedItem?.tag
            super.item    = wrappedItem?.item
        }
    }

    override func updateTitleLabel() {
        guard let item = item as? RetroRomFileItem else {
            return super.updateTitleLabel()
        }

        let attributedTitle = NSAttributedString(string: item.itemName, attributes: titleAttributes)

        let tagIdArray = item.tagIdArray
        var tags = RetroRomFileManager.shared.fileTags(in: tagIdArray)
        if tags.count == 0 {
            titleLabel.attributedText = attributedTitle
        } else {
            if let tag = firstTag {
                if let index = tags.firstIndex(where: { $0.id == tag.id }) {
                    tags.remove(at: index)
                    tags.insert(tag, at: 0)
                }
            }
            let font = UIFont.systemFont(ofSize: UIFont.labelFontSize - 3)
            let attributedTags = RetroRomFileTag.makeAttributedTagText(tags, attributes: titleAttributes, refFont: font)
            let attributedString = NSMutableAttributedString(attributedString: attributedTags)
            attributedString.append(attributedTitle)
            titleLabel.attributedText = attributedString
        }
    }
}

final class RetroRomFolderIconViewCell: RetroRomBaseIconViewCell {

}

final class RetroRomParentFolderIconViewCell: UICollectionViewCell {
    private let imageView = YYLabel(frame: .zero)
    private let imageViewHost = UIView(frame: .zero)
    private let titleLabel = YYLabel(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(imageViewHost)

        imageView.text = "··"
        imageView.textColor = .mainColor
        imageView.textAlignment = .center
        imageView.textVerticalAlignment = .center
        imageView.font = UIFont.systemFont(ofSize: 50, weight: .bold)
        imageViewHost.addSubview(imageView)

        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.textVerticalAlignment = .top
        titleLabel.textColor = UIColor.label
        titleLabel.font = UIFont.systemFont(ofSize: UIFont.labelFontSize - 3)
        titleLabel.text = Bundle.localizedString(forKey: "homepage_parent_folder")
        contentView.addSubview(titleLabel)

        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            self?.titleLabel.text = Bundle.localizedString(forKey: "homepage_parent_folder")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        imageViewHost.frame = CGRect(x: 0, y: 0, width: width, height: height - RetroRomBaseIconViewCell.titleHeight)
        let imgX = imageViewHost.width * 0.15
        let imgY = imageViewHost.height * 0.15
        let imgW = imageViewHost.width - imgX * 2
        let imgH = imageViewHost.height - imgY * 2
        imageView.frame = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)

        titleLabel.sizeToFit()
        titleLabel.frame = CGRect(x: 0, y: imageViewHost.maxY + 5, width: width, height: titleLabel.height)
    }
}

fileprivate final class TopAlignedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        if let attributedText = attributedText, numberOfLines == 2 {
            let size = attributedText.size()
            if size.width < rect.width {
                super.drawText(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: size.height))
            } else {
                super.drawText(in: rect)
            }
        } else {
            super.drawText(in: rect)
        }
    }
}
