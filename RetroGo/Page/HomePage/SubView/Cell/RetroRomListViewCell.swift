//
//  RetroRomListViewCell.swift
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

class RetroRomBaseListViewCell: UICollectionViewListCell {
    static let rowHeight: CGFloat = 68.0

    let thumbnailView = UIImageView(frame: .zero)
    let titleLabel = UILabel(frame: .zero)
    let infoLabel  = YYLabel(frame: .zero)

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
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail
        self.titleAttributes = [
            .font: UIFont.systemFont(ofSize: UIFont.labelFontSize),
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

        let sortType = RetroRomFolderPageState.shared.sortType

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
}

extension RetroRomBaseListViewCell {
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
        // `verticalInset` controls the breathing room between the
        // thumbnail and the cell's top/bottom edges. Together with
        // `Self.rowHeight = 68`, this gives:
        //   rowHeight 68 = top inset 8 + thumbHeight 52 + bottom inset 8
        let verticalInset: CGFloat = 8
        let thumbHeight = Self.rowHeight - verticalInset * 2
        let thumbWidth  = thumbHeight / 240 * 256
        thumbnailView.layer.cornerRadius = 6.0
        thumbnailView.layer.masksToBounds = true
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailView)

        // Required-priority constraints define how the thumbnail floats
        // inside contentView (anchors, width). The height is "preferred"
        // at priority 999, NOT required — see the rationale below the
        // activate block.
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalInset),
            thumbnailView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalInset),
            thumbnailView.widthAnchor.constraint(equalToConstant: thumbWidth),
        ])

        // Why priority 999, not 1000:
        //
        // `UICollectionViewListCell` under
        // `UICollectionLayoutListConfiguration` is self-sizing. The layout
        // first places the cell at an estimated height (~52pt), THEN asks
        // the cell to report its preferred size via systemLayoutSizeFitting.
        //
        // During that estimated-height frame, `contentView.height = 52` is
        // imposed by `UIView-Encapsulated-Layout-Height` at required
        // priority. Our other required constraints (top:+8, bottom:-8)
        // derive thumbnail height = 52-16 = 36 from that. If we ALSO say
        // thumbnail height == 52 at required priority, we have two
        // required constraints contradicting each other → UIKit logs the
        // "Unable to simultaneously satisfy constraints" warning and
        // breaks one of them.
        //
        // Lowering this explicit height to priority 999 lets it break
        // silently during the estimated frame. Once `preferredLayoutAttributesFitting`
        // returns 68pt (below) and the cell is resized, contentView
        // becomes 68pt and the 999-priority height==52 is satisfiable
        // again. Same trick applies to the title and info label heights.
        let thumbHeightConstraint = thumbnailView.heightAnchor.constraint(equalToConstant: thumbHeight)
        thumbHeightConstraint.priority = UILayoutPriority(999)
        thumbHeightConstraint.isActive = true

        titleLabel.numberOfLines = 1
        titleLabel.textColor = UIColor.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.topAnchor),
        ])
        let titleHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: thumbHeight * 0.5)
        titleHeightConstraint.priority = UILayoutPriority(999)
        titleHeightConstraint.isActive = true

        infoLabel.numberOfLines = 1
        infoLabel.textVerticalAlignment = .bottom
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoLabel)
        NSLayoutConstraint.activate([
            infoLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            infoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            infoLabel.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor),
        ])
        let infoHeightConstraint = infoLabel.heightAnchor.constraint(equalToConstant: thumbHeight * 0.5)
        infoHeightConstraint.priority = UILayoutPriority(999)
        infoHeightConstraint.isActive = true

        // Align the system list separator with the title text (not the
        // cell's leading edge). Matches iOS Files / Settings / Mail
        // convention: separators visually delimit content rows, so they
        // should start where content starts, not where the cell's
        // hit-test rectangle starts. `separatorLayoutGuide` is provided
        // by `UICollectionViewListCell` for exactly this purpose.
        NSLayoutConstraint.activate([
            separatorLayoutGuide.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor)
        ])
    }

    /// Force the cell to self-size to `rowHeight` (68pt) rather than
    /// letting `UICollectionLayoutListConfiguration`'s estimated-height
    /// pass settle at whatever it picks first. This is the second half
    /// of the fix for "Unable to satisfy constraints" warnings (the
    /// first half being the 999-priority dance in `configUI`):
    ///
    /// - Without this override, the cell self-sizes via
    ///   `systemLayoutSizeFitting`, which respects priority-999
    ///   constraints. The result tends to be 68pt (our 999-preferences
    ///   resolve correctly), but the estimated-height frame BEFORE the
    ///   self-sizing call would still trip the warning if we'd kept
    ///   `thumbnail.height == 52` at required priority.
    /// - With this override, the layout knows our preferred height
    ///   up-front. The cell goes from estimated → 68pt → final layout
    ///   in one step, and the 999-priority preferences never have to
    ///   "break" in practice — they're satisfied from the first real
    ///   layout pass.
    ///
    /// `UIView.noIntrinsicMetric` on width preserves whatever width the
    /// layout assigns (full-width in our list config; would be the grid
    /// item width if reused in a flow layout later).
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attrs = super.preferredLayoutAttributesFitting(layoutAttributes)
        attrs.size.height = Self.rowHeight
        return attrs
    }
}

final class RetroRomFolderListViewCell: RetroRomBaseListViewCell {

}

final class RetroRomFileListViewCell: RetroRomBaseListViewCell {
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
            let font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
            let attributedTags =  RetroRomFileTag.makeAttributedTagText(tags, attributes: titleAttributes, refFont: font)
            let attributedString = NSMutableAttributedString(attributedString: attributedTags)
            attributedString.append(attributedTitle)
            titleLabel.attributedText = attributedString
        }
    }
}
