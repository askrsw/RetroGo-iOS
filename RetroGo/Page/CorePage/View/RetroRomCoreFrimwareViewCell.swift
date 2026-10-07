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
        // Key (tip) uses secondary color, value uses primary — same
        // hierarchy convention as RetroRomCoreInfoViewCell.
        self.tipAttributes = [
            .font: UIFont.boldSystemFont(ofSize: UIFont.labelFontSize),
            .foregroundColor: UIColor.secondaryLabel,
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

        // 1. Set the max width (keep the existing logic)
        nameLabel.preferredMaxLayoutWidth = contentView.width - nameTipLabel.width - 16 - 10 - 16

        // 2. Create the base name string
        let fullString = NSMutableAttributedString(string: firmware.name, attributes: valueAttributes)

        if !firmware.fileExists {
            // 3. File missing: show a "Required/Optional" badge
            //    Required → red (warning), Optional → neutral gray (just informational, not a warning).
            //    The real status alerts "Missed"/"Invalid" keep their red/orange colors.
            let isRequired = !firmware.optional
            let tagText = isRequired ? Bundle.localizedString(forKey: "coreinfo_firmware_required") : Bundle.localizedString(forKey: "coreinfo_firmware_optional")
            let tagColor = isRequired ? UIColor.systemRed : UIColor.systemGray
            appendTag(to: fullString, text: tagText, color: tagColor)
        } else if let missing = holder?.mameMissingFiles(for: firmware), !missing.isEmpty {
            // MAME BIOS archive lacking required files: games using it can't start.
            appendTag(to: fullString, text: Bundle.localizedString(forKey: "coreinfo_mame_bios_incomplete"), color: .systemOrange)
        } else if !firmware.isValid {
            // 4. File present but MD5 invalid: show an "Invalid" badge
            let isRequired = !firmware.optional
            let tagText = Bundle.localizedString(forKey: "coreinfo_firmware_invalid")
            let tagColor = isRequired ? UIColor.systemRed : UIColor.systemOrange
            appendTag(to: fullString, text: tagText, color: tagColor)
        } else {
            // 5. File present and valid
            let iconSize: CGFloat = 20
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)

            // 1. Get the original icon
            if let symbolImage = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal) {
                // 2. Key: render the vector image into a bitmap
                let renderer = UIGraphicsImageRenderer(size: symbolImage.size)
                let bitmapImage = renderer.image { context in
                    symbolImage.draw(in: CGRect(origin: .zero, size: symbolImage.size))
                }

                // 3. Insert the YYText attachment
                let attachment = NSMutableAttributedString.attachmentString(withContent: bitmapImage, contentMode: .center, attachmentSize: bitmapImage.size, alignTo: UIFont.systemFont(ofSize: iconSize), alignment: .center)
                fullString.append(NSAttributedString(string: "  "))
                fullString.append(attachment)
            }
        }

        // 6. Assign
        nameLabel.attributedText = fullString
    }

    private func updatePathLabel() {
        guard let firmware = firmware else {
            return pathLabel.attributedText = nil
        }

        pathLabel.preferredMaxLayoutWidth = contentView.width - pathTipLabel.width - 16 - 10 - 16

        // The path is tappable — tapping opens a file picker for the user
        // to import the firmware. Render it as a real iOS link (blue text +
        // matching underline) so the affordance is consistent with other
        // tappable text on this page (Source Code / Licenses).
        let fullString = NSMutableAttributedString(string: firmware.path, attributes: valueAttributes)
        let allRange = fullString.rangeOfAll()
        fullString.addAttribute(.foregroundColor, value: UIColor.link, range: allRange)

        // 1. Underline for the normal state (link blue)
        let normalUnderline = YYTextDecoration(style: .single, width: 1, color: .link)
        fullString.setTextUnderline(normalUnderline, range: allRange)

        // 2. Configure the highlighted state
        let highlight = YYTextHighlight()

        // Underline color when highlighted (key: the highlighted underline style is set through attributes)
        let highlightUnderline = YYTextDecoration(style: .single, width: 1, color: .mainColor)
        highlight.attributes = [
            NSAttributedString.Key.foregroundColor.rawValue: UIColor.mainColor,
            YYTextUnderlineAttributeName: highlightUnderline,
        ]

        highlight.tapAction = { [weak self] container, text, range, rect in
            Vibration.selection.vibrate()
            self?.loadFirmwareFile()
        }

        // 3. Apply the highlight
        fullString.setTextHighlight(highlight, range: allRange)

        if !firmware.fileExists {
            // 4. File missing: show a "Missed" badge
            let isRequired = !firmware.optional
            let tagText = Bundle.localizedString(forKey: "coreinfo_firmware_missed")
            let tagColor = isRequired ? UIColor.systemRed : UIColor.systemOrange
            appendTag(to: fullString, text: tagText, color: tagColor)
        } else if let missing = holder?.mameMissingFiles(for: firmware), !missing.isEmpty {
            let tagText = String(format: Bundle.localizedString(forKey: "coreinfo_mame_bios_missing_count"), missing.count)
            appendTag(to: fullString, text: tagText, color: .systemOrange)
        } else if firmware.isValid {
            // 5. File present and valid
            let tagText = Bundle.localizedString(forKey: "coreinfo_firmware_ready")
            let tagColor = UIColor.systemGreen
            appendTag(to: fullString, text: tagText, color: tagColor)
        }

        pathLabel.attributedText = fullString
    }

    private func loadFirmwareFile() {
        guard let firmware = firmware, let controller = UIViewController.currentActive() else { return }

        // 1. Get the firmware extension (e.g. "bin" or "rom")
        let fileExtension = (firmware.name as NSString).pathExtension

        // 2. Create a UTType from the extension
        let contentTypes: [UTType]
        if let customType = UTType(filenameExtension: fileExtension) {
            contentTypes = [customType]
        } else {
            contentTypes = [.data] // Fall back to the generic binary type
        }

        // 3. Create the picker
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false // No multiple selection

        // 4. (Optional) Set the picker title to tell the user which file to look for
        documentPicker.title = "请选择: \(firmware.name)"

        controller.present(documentPicker, animated: true)
    }

    private func appendTag(to attributedString: NSMutableAttributedString, text: String, color: UIColor) {
        let fontSize: CGFloat = UIFont.labelFontSize - 4
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let hPadding: CGFloat = 4
        let vPadding: CGFloat = 2

        // 1. Compute the text height precisely (capHeight is more accurate)
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: textAttributes)

        // 2. Container size
        let layerSize = CGSize(width: textSize.width + hPadding * 2, height: textSize.height + vPadding * 2)

        // 3. Create the container layer (background color and corners)
        let containerLayer = CALayer()
        containerLayer.backgroundColor = color.cgColor
        containerLayer.cornerRadius = 6
        containerLayer.frame = CGRect(origin: .zero, size: layerSize)

        // 4. Create the text layer (renders the text)
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = font
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale

        // Key point: compute the Y offset by hand to center vertically
        // Formula: (container height - actual text height) / 2
        // Note: some fonts have a descent and may need a -1 or -0.5 nudge
        let yOffset = (layerSize.height - textSize.height) / 2
        textLayer.frame = CGRect(x: 0, y: yOffset, width: layerSize.width, height: textSize.height)

        containerLayer.addSublayer(textLayer)

        // 5. Convert to an attributed string
        // alignTo: pass the main line's font; alignment: .center centers the attachment on the text
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
        if holder?.coreInfoItem.coreId == MameImportScreener.mameCoreId {
            // Recognized by content, renamed to its set and merged; any file name works.
            holder?.importMameBios(url)
        } else if firmware.name == fileName {
            if firmware.copyFile(url) {
                // updateNameLabel()
                // updatePathLabel()

                // Calling updateNameLabel and updatePathLabel directly breaks the layout,
                // so update the whole cell from the data source.
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
