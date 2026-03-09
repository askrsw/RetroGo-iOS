//
//  RetroRomActivityView.swift
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
import ObjcHelper

final class RetroRomActivityView: UIView {
    private let activityView = UIActivityIndicatorView(style: .medium)
    private let activityBkColorView = UIImageView(frame: .zero)
    private let activityHostView = UIView(frame: .zero)
    private let titleLabel = UILabel(frame: .zero)
    private let messageLabel = UILabel(frame: .zero)

    private var canDismiss: Bool = false
    private lazy var maskedView: OCMaskView? = OCMaskView { [weak self] in
        if let v = self?.canDismiss, v {
            self?.removeFromSuperview()
            self?.maskedView = nil
        }
        return self?.canDismiss ?? false
    }

    init(mainTitle: String) {
        let w: CGFloat = min(360, DeviceConfig.screenWidth) - 40
        let h: CGFloat = 240
        let x: CGFloat = (DeviceConfig.screenWidth - w) * 0.5
        let y: CGFloat = DeviceConfig.screenHeight * 0.3
        super.init(frame: CGRect(x: x, y: y, width: w, height: h))

        maskedView?.bkColor = UIColor(named: "Color_defaultMaskBackground")
        backgroundColor = UIColor(named: "Color_importViewBackground")
        layer.cornerRadius = 12

        titleLabel.text = mainTitle
        messageLabel.text = mainTitle

        configUI()
        layoutUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let radius: CGFloat = activityHostView.width * 0.5 + 20
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0)) // Start at the top left corner
        path.addLine(to: CGPoint(x: bounds.midX - radius, y: 0)) // Go to the start of the arc
        path.addArc(withCenter: CGPoint(x: bounds.midX, y: 0), radius: radius, startAngle: .pi, endAngle: 0, clockwise: true) // Add the arc
        path.addLine(to: CGPoint(x: bounds.maxX, y: 0)) // Go to the top right corner
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY)) // Go to the bottom right corner
        path.addLine(to: CGPoint(x: 0, y: bounds.maxY)) // Go to the bottom left corner
        path.close() // Close the path

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        layer.mask = mask
    }

    func install() {
        if let maskedView = maskedView {
            let x = self.minX
            let y = self.minY
            let w = self.width
            let frame = CGRect(x: x, y: y, width: w, height: messageLabel.frame.maxY + 20)
            self.frame = frame
            maskedView.install()
            maskedView.addSubview(self)
        }
    }

    func activeMessage(_ message: String, title: String) {
        func function() {
            if self.activityView.isHidden {
                self.activityBkColorView.image = nil
                self.activityBkColorView.backgroundColor = .mainColor
                self.activityView.isHidden = false
            }
            if !self.activityView.isAnimating {
                self.activityView.startAnimating()
            }
            self.titleLabel.text = title
            self.messageLabel.text = message

            self.updateMessageLabelHeight()
        }

        if Thread.isMainThread {
            function()
        } else {
            DispatchQueue.main.async(execute: {
                function()
            })
        }
    }

    func infoMessage(_ message: String, title: String?, canDismiss: Bool) {
        showMessage(message, title: title, icon: Self.infoIcon, canDismiss: canDismiss)
    }

    func errorMessage(_ message: String, title: String?, canDismiss: Bool) {
        showMessage(message, title: title, icon: Self.errorIcon, canDismiss: canDismiss)
    }

    func successMessage(_ message: String, title: String?, canDismiss: Bool) {
        showMessage(message, title: title, icon: Self.successIcon, canDismiss: canDismiss)
    }
}

extension RetroRomActivityView {
    private static let infoIcon = UIImage(systemName: "info.circle.fill", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue]))
    private static let errorIcon = UIImage(systemName: "xmark.octagon.fill", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
    private static let successIcon = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(paletteColors: [.white, .systemGreen]))

    private func showMessage(_ message: String, title: String?, icon: UIImage?,  canDismiss: Bool) {

        func function() {
            if self.activityView.isAnimating {
                self.activityView.stopAnimating()
            }
            if self.activityView.isHidden == false {
                self.activityView.isHidden = true
            }

            self.activityBkColorView.backgroundColor = .clear
            self.activityBkColorView.image = icon
            self.canDismiss = canDismiss
            self.titleLabel.text = title
            self.messageLabel.text = message

            self.updateMessageLabelHeight()
        }

        if Thread.isMainThread {
            function()
        } else {
            DispatchQueue.main.async(execute: {
                function()
            })
        }
    }

    private func updateMessageLabelHeight() {
        guard let messsage = self.messageLabel.text, let font = self.messageLabel.font else {
            return
        }

        let constrainedSize = CGSize(width: width - 20 - 20, height: 0)
        let size = (messsage as NSString).renderedSize(with: font, constrainedTo: constrainedSize)
        if self.messageLabel.height != size.height {
            let oldFrame = self.messageLabel.frame
            self.messageLabel.frame = CGRect(origin: oldFrame.origin, size: CGSize(width: constrainedSize.width, height: size.height))
            self.height = self.messageLabel.frame.maxY + 20
        }
    }

    private func configUI() {
        activityHostView.backgroundColor = backgroundColor
        addSubview(activityHostView)

        activityBkColorView.backgroundColor = .mainColor
        activityBkColorView.clipsToBounds = true
        activityHostView.addSubview(activityBkColorView)

        activityView.color = .systemBackground
        activityBkColorView.addSubview(activityView)

        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        titleLabel.numberOfLines = 1
        addSubview(titleLabel)

        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byTruncatingHead
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: UIFont.labelFontSize - 2)
        addSubview(messageLabel)
    }

    private func layoutUI() {
        activityView.sizeToFit()
        let activitySize = activityView.size

        do {
            let w: CGFloat = activitySize.width + 30
            let h: CGFloat = activitySize.height + 30
            let x: CGFloat = (width - w) * 0.5
            let y: CGFloat = 0 - h * 0.5
            activityHostView.layer.cornerRadius = w / 2
            activityHostView.frame = CGRect(x: x, y: y, width: w, height: h)
        }

        do {
            let w: CGFloat = activitySize.width + 20
            let h: CGFloat = activitySize.height + 20
            let x: CGFloat = (activityHostView.width - w) * 0.5
            let y: CGFloat = (activityHostView.height - h) * 0.5
            activityBkColorView.layer.cornerRadius = w / 2
            activityBkColorView.frame = CGRect(x: x, y: y, width: w, height: h)
        }

        do {
            let w: CGFloat = activitySize.width
            let h: CGFloat = activitySize.height
            let x: CGFloat = (activityBkColorView.width - w) * 0.5
            let y: CGFloat = (activityBkColorView.height - h) * 0.5
            activityView.frame = CGRect(x: x, y: y, width: w, height: h)
        }

        do {
            titleLabel.sizeToFit()
            let w: CGFloat = width - 20 - 20
            let h: CGFloat = titleLabel.height
            let x: CGFloat = 20
            let y: CGFloat = activityHostView.frame.maxY + 5
            titleLabel.frame = CGRect(x: x, y: y, width: w, height: h)
        }

        do {
            messageLabel.sizeToFit()
            let w: CGFloat = width - 20 - 20
            let h: CGFloat = messageLabel.height
            let x: CGFloat = 20
            let y: CGFloat = titleLabel.frame.maxY + 12
            messageLabel.frame = CGRect(x: x, y: y, width: w, height: h)
        }
    }
}
