//
//  InGameInfoView.swift
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
import RACoordinator

final class InGameInfoView: UIView {
    private let attributes = InGameInfoView.makeTextAttributes(color: .white)
    private let messageLabel  = YYLabel(frame: .zero)
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)

        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false

        messageLabel.textAlignment = .left
        messageLabel.textVerticalAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byCharWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = max(0, bounds.width - 25)
        messageLabel.preferredMaxLayoutWidth = contentWidth
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width
        if width <= 0 {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        let contentWidth = max(0, width - 25)
        let labelHeight = messageLabel.sizeThatFits(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)).height
        let contentHeight = max(20, ceil(labelHeight)) + 8
        return CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    func showMessage(_ msg: EmuInGameMessage) {
        let icon: UIImage?
        switch msg.type {
            case .info:
                icon = Self.infoIcon
            case .warning:
                icon = Self.warningIcon
            case .error:
                icon = Self.errorIcon
            case .success:
                icon = Self.successIcon
            default:
                icon = nil
        }

        let attributedString = Self.makeMessageAttributedString(message: msg.message, icon: icon, attributes: attributes)
        messageLabel.attributedText = attributedString
        messageLabel.preferredMaxLayoutWidth = max(0, bounds.width)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()

        isHidden = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 3.5, target: self, selector: #selector(timerEventHandler), userInfo: nil, repeats: false)
    }

    @objc
    private func timerEventHandler() {
        isHidden = true
        messageLabel.attributedText = nil

        timer?.invalidate()
        timer = nil
    }
}

extension InGameInfoView {
    private static let infoIcon = UIImage(systemName: "info.circle.fill", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue]))
    private static let warningIcon = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.white, .systemOrange]))
    private static let errorIcon = UIImage(systemName: "xmark.octagon.fill", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
    private static let successIcon = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.white, .systemGreen]))

    private static func makeTextAttributes(color: UIColor) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.lineBreakMode = .byCharWrapping
        return [
            .font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize + 3),
            .paragraphStyle: style,
            .foregroundColor: color
        ]
    }

    private static func makeMessageAttributedString(message: String, icon: UIImage?, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let full = NSMutableAttributedString()
        let font = (attributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: UIFont.smallSystemFontSize + 3)

        if let icon = icon {
            let iconSize = CGSize(width: 16, height: 16)
            let iconView = UIImageView(image: icon)
            iconView.frame = CGRect(origin: .zero, size: iconSize)
            iconView.contentMode = .scaleAspectFit

            let attachment = NSMutableAttributedString.attachmentString(withContent: iconView, contentMode: .center, attachmentSize: iconSize, alignTo: font, alignment: .center)
            full.append(attachment)
            full.append(NSAttributedString(string: " "))
        }

        full.append(NSAttributedString(string: message, attributes: attributes))
        return full
    }
}
