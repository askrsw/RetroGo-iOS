//
//  RetroRomCoreFrimwareViewCell.swift
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
import UniformTypeIdentifiers

final class RetroRomCoreFrimwareViewCell: UICollectionViewListCell {

    let nameTipLabel = YYLabel(frame: .zero)
    let nameLabel = YYLabel(frame: .zero)
    let pathTipLabel = YYLabel(frame: .zero)
    let pathLabel = YYLabel(frame: .zero)
    let tipAttributes: [NSAttributedString.Key: Any]
    let valueAttributes: [NSAttributedString.Key: Any]

    var firmware: EmuCoreFirmware? {
        didSet {
            updateNameLabel()
            updatePathLabel()
        }
    }

    weak var holder: RetroRomCoreInfoViewController?

    override init(frame: CGRect) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 10
        style.lineBreakMode = .byWordWrapping
        self.tipAttributes = [
            .font: UIFont.boldSystemFont(ofSize: UIFont.labelFontSize),
            .foregroundColor: UIColor.label,
        ]
        self.valueAttributes = [
            .font: UIFont.systemFont(ofSize: UIFont.labelFontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style.copy() as! NSParagraphStyle
        ]
        super.init(frame: frame)
        configViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension RetroRomCoreFrimwareViewCell {
    private func updateNameLabel() {
        guard let firmware = firmware else {
            return nameLabel.attributedText = nil
        }

        // 1. 设置最大宽度（保持你原有的逻辑）
        nameLabel.preferredMaxLayoutWidth = contentView.width - nameTipLabel.width - 16 - 10 - 16

        // 2. 创建基础名称字符串
        let fullString = NSMutableAttributedString(string: firmware.name, attributes: valueAttributes)

        if !firmware.fileExists {
            // 3. 文件不存在：显示 “必须/可选” 气泡
            let isRequired = !firmware.optional
            let tagText = isRequired ? Bundle.localizedString(forKey: "coreinfo_firmware_required") : Bundle.localizedString(forKey: "coreinfo_firmware_optional")
            let tagColor = isRequired ? UIColor.systemRed : UIColor.systemOrange
            appendTag(to: fullString, text: tagText, color: tagColor)
        } else if !firmware.isValid {
            // 4. 文件存在但 MD5 无效：显示 “无效” 气泡
            let isRequired = !firmware.optional
            let tagText = Bundle.localizedString(forKey: "coreinfo_firmware_invalid")
            let tagColor = isRequired ? UIColor.systemRed : UIColor.systemOrange
            appendTag(to: fullString, text: tagText, color: tagColor)
        } else {
            // 5. 文件存在且有效
            let iconSize: CGFloat = 20
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)

            // 1. 获取原始图标
            if let symbolImage = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal) {
                // 2. 关键：将矢量图绘制成位图 (Bitmap)
                let renderer = UIGraphicsImageRenderer(size: symbolImage.size)
                let bitmapImage = renderer.image { context in
                    symbolImage.draw(in: CGRect(origin: .zero, size: symbolImage.size))
                }

                // 3. 插入 YYText 附件
                let attachment = NSMutableAttributedString.attachmentString(withContent: bitmapImage, contentMode: .center, attachmentSize: bitmapImage.size, alignTo: UIFont.systemFont(ofSize: iconSize), alignment: .center)
                fullString.append(NSAttributedString(string: "  "))
                fullString.append(attachment)
            }
        }

        // 6. 赋值
        nameLabel.attributedText = fullString
    }

    private func updatePathLabel() {
        guard let firmware = firmware else {
            return pathLabel.attributedText = nil
        }

        pathLabel.preferredMaxLayoutWidth = contentView.width - pathTipLabel.width - 16 - 10 - 16

        let fullString = NSMutableAttributedString(string: firmware.path, attributes: valueAttributes)
        let allRange = fullString.rangeOfAll()

        // 1. 设置普通状态下的下划线 (白色)
        let normalUnderline = YYTextDecoration(style: .single, width: 1, color: .label)
        fullString.setTextUnderline(normalUnderline, range: allRange)

        // 2. 配置高亮状态
        let highlight = YYTextHighlight()

        // 高亮时的下划线颜色 (关键：通过 attributes 设置高亮时的下划线样式)
        let highlightUnderline = YYTextDecoration(style: .single, width: 1, color: .mainColor)
        highlight.attributes = [
            NSAttributedString.Key.foregroundColor.rawValue: UIColor.mainColor,
            YYTextUnderlineAttributeName: highlightUnderline,
        ]

        highlight.tapAction = { [weak self] container, text, range, rect in
            Vibration.selection.vibrate()
            self?.loadFirmwareFile()
        }

        // 3. 应用高亮
        fullString.setTextHighlight(highlight, range: allRange)

        if !firmware.fileExists {
            // 4. 文件不存在：显示 “缺失” 气泡
            let isRequired = !firmware.optional
            let tagText = Bundle.localizedString(forKey: "coreinfo_firmware_missed")
            let tagColor = isRequired ? UIColor.systemRed : UIColor.systemOrange
            appendTag(to: fullString, text: tagText, color: tagColor)
        } else if firmware.isValid {
            // 5. 文件存在且有效
            let tagText = Bundle.localizedString(forKey: "coreinfo_firmware_ready")
            let tagColor = UIColor.systemGreen
            appendTag(to: fullString, text: tagText, color: tagColor)
        }

        pathLabel.attributedText = fullString
    }

    private func loadFirmwareFile() {
        guard let firmware = firmware, let controller = UIViewController.currentActive() else { return }

        // 1. 获取固件后缀 (例如 "bin" 或 "rom")
        let fileExtension = (firmware.name as NSString).pathExtension

        // 2. 根据后缀创建 UTType
        let contentTypes: [UTType]
        if let customType = UTType(filenameExtension: fileExtension) {
            contentTypes = [customType]
        } else {
            contentTypes = [.data] // 兜底使用通用二进制类型
        }

        // 3. 初始化选择器
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false // 禁用多选

        // 4. (可选) 设置选择器的标题，提醒用户要找哪个文件
        documentPicker.title = "请选择: \(firmware.name)"

        controller.present(documentPicker, animated: true)
    }

    private func appendTag(to attributedString: NSMutableAttributedString, text: String, color: UIColor) {
        let fontSize: CGFloat = UIFont.labelFontSize - 4
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let hPadding: CGFloat = 4
        let vPadding: CGFloat = 2

        // 1. 精确计算文字高度 (CapHeight 更准确)
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: textAttributes)

        // 2. 容器尺寸
        let layerSize = CGSize(width: textSize.width + hPadding * 2, height: textSize.height + vPadding * 2)

        // 3. 创建容器 Layer (负责背景色和圆角)
        let containerLayer = CALayer()
        containerLayer.backgroundColor = color.cgColor
        containerLayer.cornerRadius = 6
        containerLayer.frame = CGRect(origin: .zero, size: layerSize)

        // 4. 创建文字 Layer (负责渲染文字)
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = font
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale

        // 关键点：手动计算 Y 轴偏移，实现垂直居中
        // 计算公式：(容器总高 - 文字实际高) / 2
        // 注意：某些字体由于有 descent，可能需要微调 -1 或 -0.5
        let yOffset = (layerSize.height - textSize.height) / 2
        textLayer.frame = CGRect(x: 0, y: yOffset, width: layerSize.width, height: textSize.height)

        containerLayer.addSublayer(textLayer)

        // 5. 转换为属性字符串
        // alignTo: 传入主行的字体，alignment: .center 会让附件中心对齐文字中心
        let tagAttachment = NSMutableAttributedString.attachmentString(
            withContent: containerLayer,
            contentMode: .center,
            attachmentSize: layerSize,
            alignTo: UIFont.systemFont(ofSize: UIFont.labelFontSize),
            alignment: .center
        )

        attributedString.append(NSAttributedString(string: "  "))
        attributedString.append(tagAttachment)
    }

    private func configViews() {
        nameTipLabel.numberOfLines = 1
        nameTipLabel.attributedText = NSAttributedString(string: Bundle.localizedString(forKey: "coreinfo_firmware_name"), attributes: tipAttributes)
        nameTipLabel.sizeToFit()
        contentView.addSubview(nameTipLabel)
        nameTipLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.equalToSuperview().offset(16)
            make.size.equalTo(nameTipLabel.size)
        }

        nameLabel.numberOfLines = 0
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.leading.equalTo(nameTipLabel.snp.trailing).offset(10)
            make.trailing.equalToSuperview().offset(-16)
            make.top.equalTo(nameTipLabel.snp.top)
        }

        pathTipLabel.numberOfLines = 1
        pathTipLabel.attributedText = NSAttributedString(string: Bundle.localizedString(forKey: "coreinfo_firmware_path"), attributes: tipAttributes)
        pathTipLabel.sizeToFit()
        contentView.addSubview(pathTipLabel)
        pathTipLabel.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(10)
            make.leading.equalTo(nameTipLabel)
            make.size.equalTo(pathTipLabel.size)
        }

        pathLabel.numberOfLines = 0
        contentView.addSubview(pathLabel)
        pathLabel.snp.makeConstraints { make in
            make.leading.equalTo(pathTipLabel.snp.trailing).offset(10)
            make.trailing.equalToSuperview().offset(-16)
            make.top.equalTo(nameLabel.snp.bottom).offset(10)
            make.bottom.equalToSuperview().offset(-12)
        }
    }
}

extension RetroRomCoreFrimwareViewCell: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let firmware = firmware, let url = urls.first else { return }

        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent
        if firmware.name == fileName {
            if firmware.copyFile(url) {
                // updateNameLabel()
                // updatePathLabel()

                // 直接调用 updateNameLabel 和 updatePathLabel，排版会发生错误
                // 从 data source 更新整个 cell。
                holder?.updateFirmware(firmware)
            }
        } else {
            let title = Bundle.localizedString(forKey: "warning")
            let format = Bundle.localizedString(forKey: "coreinfo_firmware_unmatched_file")
            let message = String(format: format, firmware.name)
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let action = UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default)
            alert.addAction(action)

            let controller = UIViewController.currentActive()
            controller?.present(alert, animated: true)
        }
    }
}
