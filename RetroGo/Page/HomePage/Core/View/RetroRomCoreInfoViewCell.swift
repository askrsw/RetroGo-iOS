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
                case .extensions(let tip, let list):
                    updateTipAndExtensions(tip: tip, extensions: list)
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
        let labelColor = UIColor.label

        self.paragraphStyle = NSMutableParagraphStyle()
        self.paragraphStyle .lineSpacing = 5
        self.paragraphStyle .paragraphSpacing = 10
        self.paragraphStyle .lineBreakMode = .byWordWrapping

        self.tipAttributes = [
            .font: boldFont,
            .foregroundColor: labelColor,
            .paragraphStyle: self.paragraphStyle.copy() as! NSParagraphStyle
        ]

        self.normalAttributes = [
            .font: normalFont,
            .foregroundColor: labelColor,
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

        // --- Tip 部分 ---
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)
        fullString.append(tipAttr)

        // 计算悬挂缩进
        let tipRect = tipAttr.boundingRect(with: CGSize(width: label.preferredMaxLayoutWidth, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = 0

        // 1. 应用基础样式与缩进
        var normalAttr = self.normalAttributes
        normalAttr[.paragraphStyle] = style.copy() as! NSParagraphStyle
        normalAttr[.baselineOffset] = 2

        // --- Value 部分 (复古链接风格) ---
        for i in 0 ..< licenses.count {
            let license = licenses[i]

            let valueAttr = NSMutableAttributedString(string: license.showName, attributes: normalAttr)

            // 设置下划线样式 (使用 YYTextDecoration)
            let underline = YYTextDecoration(style: .single, width: 1, color: .label)
            valueAttr.setTextUnderline(underline, range: valueAttr.rangeOfAll())

            // 3. 核心功能：点击高亮与 Action
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
                fullString.append(NSMutableAttributedString(string: ",  ", attributes: normalAttr))
            }
        }

        label.attributedText = fullString
    }

    func updateRunCoreActionText(tip: String, value: String, action: (() -> Void)?) {
        label.preferredMaxLayoutWidth = contentView.width - 32
        let fullString = NSMutableAttributedString()

        // --- Tip 部分 ---
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)

        // 计算悬挂缩进
        let tipRect = tipAttr.boundingRect(with: CGSize(width: label.preferredMaxLayoutWidth, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = 0

        // --- Value 部分 (复古链接风格) ---
        let valueAttr = NSMutableAttributedString(string: value)

        // 1. 应用基础样式与缩进
        var normalAttr = self.normalAttributes
        normalAttr[.paragraphStyle] = style.copy() as! NSParagraphStyle
        normalAttr[.baselineOffset] = 2
        valueAttr.addAttributes(normalAttr, range: valueAttr.rangeOfAll())

        // 设置下划线样式 (使用 YYTextDecoration)
        let underline = YYTextDecoration(style: .single, width: 1, color: .label)
        valueAttr.setTextUnderline(underline, range: valueAttr.rangeOfAll())

        // 3. 核心功能：点击高亮与 Action
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

        // --- 合并 ---
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

        var normalAttr = self.normalAttributes
        normalAttr[.paragraphStyle] = style.copy() as! NSParagraphStyle
        normalAttr[.baselineOffset] = 2
        valueAttr.addAttributes(normalAttr, range: valueAttr.rangeOfAll())

        let underline = YYTextDecoration(style: .single, width: 1, color: .label)
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

        // Tip (标题风格)
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)

        let tipRect = tipAttr.boundingRect(with: .zero, options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = tipRect.size.width

        // Value (内容风格)
        var normalAttributes = self.normalAttributes
        normalAttributes[.paragraphStyle] = style.copy() as! NSParagraphStyle

        let valueAttr = NSMutableAttributedString(string: value, attributes: normalAttributes)

        fullString.append(tipAttr)
        fullString.append(valueAttr)

        // 设置行间距等排版样式
        fullString.lineSpacing = 8

        // 2. 利用 YYTextLayout 进行预计算（如果需要极致性能）
        // 在 List 模式下，直接赋值给 YYLabel，它会自动根据约束更新高度
        label.attributedText = fullString
    }

    private func updateTipAndExtensions(tip: String, extensions: [String]) {
        label.preferredMaxLayoutWidth = contentView.width - 32

        let fullString = NSMutableAttributedString()

        // 1. 配置基础样式
        let tagFont = UIFont.systemFont(ofSize: UIFont.labelFontSize - 2) // 标签通常稍微小一点更美观

        // 2. 拼接 Tip 前缀
        let tipAttr = NSMutableAttributedString(string: "\(tip) ", attributes: tipAttributes)
        fullString.append(tipAttr)

        let tipRect = tipAttr.boundingRect(with: .zero, options: .usesLineFragmentOrigin, context: nil)
        let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = tipRect.size.width
        style.firstLineHeadIndent = tipRect.size.width

        var normalAttributes = self.normalAttributes
        normalAttributes[.paragraphStyle] = style.copy() as! NSParagraphStyle
        normalAttributes[.font] = tagFont

        // 3. 循环添加 Extensions 气泡
        for ext in extensions {
            // 创建标签文本
            let tagString = NSMutableAttributedString(string: "\(ext)", attributes: normalAttributes) // 前后留白

            // 创建气泡背景 (Border)
            let border = YYTextBorder()
            border.fillColor = UIColor.mainColor // 气泡背景色
            border.cornerRadius = 6               // 圆角
            border.insets = UIEdgeInsets(top: -2, left: -6, bottom: -2, right: -6) // 调整气泡高度

            // 将背景应用到整个 tagString 范围
            tagString.setTextBackgroundBorder(border, range: tagString.rangeOfAll())

            // 拼接标签

            fullString.append(tagString)

            // 拼接标签间的间距（不带背景的空格）
            let space = NSMutableAttributedString(string: "      ")
            fullString.append(space)
        }

        // 4. 设置行间距
        fullString.lineSpacing = 14

        // 5. 赋值
        label.attributedText = fullString
    }

    private func configViews() {
        // 配置 label 属性
        label.numberOfLines = 0
        label.textContainerInset = .init(top: 4, left: 0, bottom: 4, right: 0)

        contentView.addSubview(label)

        label.snp.makeConstraints { make in
            // 重点：上下左右边距决定了 Cell 的高度自适应起点和终点
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        }
    }
}
