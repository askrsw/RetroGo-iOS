//
//  RetroRomCoreInfoViewCell.swift
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

final class RetroRomCoreInfoViewCell: UICollectionViewListCell {
    private let label = YYLabel()

    var item: RetroRomCoreInfoViewController.Item? {
        didSet {
            guard let item = item else {
                return label.attributedText = nil
            }

            switch item {
                case .normal(let tip, let value):
                    updateTipAndValue(tip: tip, value: value)
                case .extensions(let tip, let list, let platformKey):
                    updateTipAndExtensions(tip: tip, extensions: list, platformKey: platformKey)
                case .runCore(let tip, let value, let action):
                    updateRunCoreActionText(tip: tip, value: value, action: action)
                case .license(let tip, let licenses):
                    updateLicenses(tip: tip, licenses: licenses)
                case .link(let tip, let url):
                    updateLink(tip: tip, url: url)
                default:
                    label.attributedText = nil
            }
        }
    }

    let paragraphStyle: NSMutableParagraphStyle
    let tipAttributes: [NSAttributedString.Key: Any]
    let normalAttributes: [NSAttributedString.Key: Any]

    override init(frame: CGRect) {
        let normalFont = UIFont.systemFont(ofSize: UIFont.labelFontSize)
        let boldFont = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        // Key (tip) uses secondary color, value uses primary — creates a
        // visual hierarchy between the row label and its content.
        let tipColor = UIColor.secondaryLabel
        let valueColor = UIColor.label

        self.paragraphStyle = NSMutableParagraphStyle()
        self.paragraphStyle .lineSpacing = 5
        self.paragraphStyle .paragraphSpacing = 10
        self.paragraphStyle .lineBreakMode = .byWordWrapping

        self.tipAttributes = [
            .font: boldFont,
            .foregroundColor: tipColor,
            .paragraphStyle: self.paragraphStyle.copy() as! NSParagraphStyle
        ]

        self.normalAttributes = [
            .font: normalFont,
            .foregroundColor: valueColor,
        ]

        super.init(frame: frame)
        configViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension RetroRomCoreInfoViewCell {
    func updateLicenses(tip: String, licenses: [RetroRomCoreInfoViewController.License]) {
        label.preferredMaxLayoutWidth = contentView.width - 32
        let fullString = NSMutableAttributedString()

        // --- Tip ---
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)
        fullString.append(tipAttr)

        // Compute the hanging indent
        let tipRect = tipAttr.boundingRect(with: CGSize(width: label.preferredMaxLayoutWidth, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = 0

        // 1. Apply the base style and indent — license name acts as a tappable link,
        //    so it adopts the iOS link blue + matching underline.
        var linkAttr = self.normalAttributes
        linkAttr[.foregroundColor] = UIColor.link
        linkAttr[.paragraphStyle] = style.copy() as! NSParagraphStyle
        linkAttr[.baselineOffset] = 2

        // Non-link attributes for the separators between license names —
        // keeps the commas neutral so only the names look tappable.
        var separatorAttr = self.normalAttributes
        separatorAttr[.paragraphStyle] = style.copy() as! NSParagraphStyle
        separatorAttr[.baselineOffset] = 2

        // --- Value (retro link style) ---
        for i in 0 ..< licenses.count {
            let license = licenses[i]

            let valueAttr = NSMutableAttributedString(string: license.showName, attributes: linkAttr)

            // Set the underline style (via YYTextDecoration)
            let underline = YYTextDecoration(style: .single, width: 1, color: .link)
            valueAttr.setTextUnderline(underline, range: valueAttr.rangeOfAll())

            // 3. Core feature: tap highlight and action
            let highlight = YYTextHighlight()
            let highlightUnderline = YYTextDecoration(style: .single, width: 1, color: .mainColor)
            highlight.attributes = [
                NSAttributedString.Key.foregroundColor.rawValue: UIColor.mainColor,
                YYTextUnderlineAttributeName: highlightUnderline,
            ]
            highlight.tapAction = { (containerView, text, range, rect) in
                Vibration.selection.vibrate()

                let current = UIViewController.currentActive()
                let controller = RetroRomCoreLicenseViewController(showName: license.showName, fileName: license.fileName)
                let navController = UINavigationController(rootViewController: controller)
                current?.present(navController, animated: true)
            }
            valueAttr.setTextHighlight(highlight, range: valueAttr.rangeOfAll())
            fullString.append(valueAttr)

            if i != licenses.count - 1 {
                fullString.append(NSMutableAttributedString(string: ",  ", attributes: separatorAttr))
            }
        }

        label.attributedText = fullString
    }

    func updateRunCoreActionText(tip: String, value: String, action: (() -> Void)?) {
        label.preferredMaxLayoutWidth = contentView.width - 32
        let fullString = NSMutableAttributedString()

        // --- Tip ---
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)

        // Compute the hanging indent
        let tipRect = tipAttr.boundingRect(with: CGSize(width: label.preferredMaxLayoutWidth, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = 0

        // --- Value (retro link style) ---
        let valueAttr = NSMutableAttributedString(string: value)

        // 1. Apply the base style and indent
        var normalAttr = self.normalAttributes
        normalAttr[.foregroundColor] = UIColor.link
        normalAttr[.paragraphStyle] = style.copy() as! NSParagraphStyle
        normalAttr[.baselineOffset] = 2
        valueAttr.addAttributes(normalAttr, range: valueAttr.rangeOfAll())

        // Set the underline style (via YYTextDecoration)
        let underline = YYTextDecoration(style: .single, width: 1, color: .link)
        valueAttr.setTextUnderline(underline, range: valueAttr.rangeOfAll())

        // 3. Core feature: tap highlight and action
        let highlight = YYTextHighlight()
        let highlightUnderline = YYTextDecoration(style: .single, width: 1, color: .mainColor)
        highlight.attributes = [
            NSAttributedString.Key.foregroundColor.rawValue: UIColor.mainColor,
            YYTextUnderlineAttributeName: highlightUnderline,
        ]
        highlight.tapAction = { (containerView, text, range, rect) in
            Vibration.selection.vibrate()
            action?()
        }
        valueAttr.setTextHighlight(highlight, range: valueAttr.rangeOfAll())

        // --- Combine ---
        fullString.append(tipAttr)
        fullString.append(valueAttr)

        label.attributedText = fullString
    }

    private func updateLink(tip: String, url: String) {
        label.preferredMaxLayoutWidth = contentView.width - 32
        let fullString = NSMutableAttributedString()

        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)
        let tipRect = tipAttr.boundingRect(with: CGSize(width: label.preferredMaxLayoutWidth, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = 0

        let valueAttr = NSMutableAttributedString(string: url)

        // Override the value color with the iOS link blue, matching iOS
        // convention for tappable text.
        var normalAttr = self.normalAttributes
        normalAttr[.foregroundColor] = UIColor.link
        normalAttr[.paragraphStyle] = style.copy() as! NSParagraphStyle
        normalAttr[.baselineOffset] = 2
        valueAttr.addAttributes(normalAttr, range: valueAttr.rangeOfAll())

        let underline = YYTextDecoration(style: .single, width: 1, color: .link)
        valueAttr.setTextUnderline(underline, range: valueAttr.rangeOfAll())

        let highlight = YYTextHighlight()
        let highlightUnderline = YYTextDecoration(style: .single, width: 1, color: .mainColor)
        highlight.attributes = [
            NSAttributedString.Key.foregroundColor.rawValue: UIColor.mainColor,
            YYTextUnderlineAttributeName: highlightUnderline,
        ]
        highlight.tapAction = { (_, _, _, _) in
            Vibration.selection.vibrate()
            guard let link = URL(string: url) else {
                return
            }
            UIApplication.shared.open(link)
        }
        valueAttr.setTextHighlight(highlight, range: valueAttr.rangeOfAll())

        fullString.append(tipAttr)
        fullString.append(valueAttr)

        label.attributedText = fullString
    }

    func updateTipAndValue(tip: String, value: String) {
        label.preferredMaxLayoutWidth = contentView.width - 32

        let fullString = NSMutableAttributedString()

        // Tip (title style)
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)

        let tipRect = tipAttr.boundingRect(with: .zero, options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = tipRect.size.width

        // Value (content style)
        var normalAttributes = self.normalAttributes
        normalAttributes[.paragraphStyle] = style.copy() as! NSParagraphStyle

        let valueAttr = NSMutableAttributedString(string: value, attributes: normalAttributes)

        fullString.append(tipAttr)
        fullString.append(valueAttr)

        // Set line spacing and other paragraph styles
        fullString.lineSpacing = 8

        // 2. Precompute with YYTextLayout (if every bit of performance matters)
        // In List mode, just assign to the YYLabel; it updates its height from the constraints
        label.attributedText = fullString
    }

    private func updateTipAndExtensions(
        tip: String,
        extensions: [String],
        platformKey: IconRender.PlatformIconKey?
    ) {
        label.preferredMaxLayoutWidth = contentView.width - 32

        let fullString = NSMutableAttributedString()

        // 1. Configure the base style
        let tagFont = UIFont.systemFont(ofSize: UIFont.labelFontSize - 2) // Tags look better slightly smaller

        // 2. Append the Tip prefix
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)
        fullString.append(tipAttr)

        let tipRect = tipAttr.boundingRect(with: .zero, options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = tipRect.size.width

        var normalAttributes = self.normalAttributes
        normalAttributes[.paragraphStyle] = style.copy() as! NSParagraphStyle
        normalAttributes[.font] = tagFont

        // All tags inside one core share the same color — the core's
        // platform accent. Ties the format chips visually to the nav-bar
        // icon and reads calmer than per-extension random colors.
        //
        // Use the *tag* variant (not the raw icon color): for dark-themed
        // platforms like PSP, the raw color is near-black and would
        // disappear into systemBackground. `platformTagColor` auto-lifts
        // brightness only when needed; bright platforms are unchanged.
        //
        // Fallback: keep the original mainColor when the platform isn't
        // mapped (so non-platform cores like noneCore still look sane).
        let tagFill: UIColor = {
            if let key = platformKey {
                return IconRender.shared.platformTagColor(for: key)
            }
            return .mainColor
        }()

        // 3. Append the extension badges in a loop
        for ext in extensions {
            // Create the tag text
            let tagString = NSMutableAttributedString(string: "\(ext)", attributes: normalAttributes) // Padding on both sides

            // Create the badge background (border)
            let border = YYTextBorder()
            border.fillColor = tagFill
            border.cornerRadius = 6               // Corner radius
            border.insets = UIEdgeInsets(top: -2, left: -6, bottom: -2, right: -6) // Adjust the badge height

            // Apply the background to the whole tagString range
            tagString.setTextBackgroundBorder(border, range: tagString.rangeOfAll())

            // Append the tag

            fullString.append(tagString)

            // Append the spacing between tags (a space without background)
            let space = NSMutableAttributedString(string: "      ")
            fullString.append(space)
        }

        // 4. Set the line spacing
        fullString.lineSpacing = 14

        // 5. Assign
        label.attributedText = fullString
    }

    private func configViews() {
        // Configure the label
        label.numberOfLines = 0
        label.textContainerInset = .init(top: 4, left: 0, bottom: 4, right: 0)

        contentView.addSubview(label)

        label.snp.makeConstraints { make in
            // Key: the top/bottom/leading/trailing insets set where the cell's self-sizing starts and ends
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        }
    }
}
