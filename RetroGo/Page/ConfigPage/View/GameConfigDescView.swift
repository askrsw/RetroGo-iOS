//
//  GameConfigDescView.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/19.
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

final class GameConfigDescView: UIView {
    let cornerRadius: CGFloat = 12
    let deltaHeight: CGFloat  = 20
    let sharpWidth: CGFloat   = 15
    let sharpRadius: CGFloat  = 4

    let label = UILabel(frame: .zero)
    let shapeLayer = CAShapeLayer()

    private var maskedView: OCMaskView?

    private var prevOrientation: UIDeviceOrientation = .unknown

    let desc: String

    init(desc: String) {
        self.desc = desc
        super.init(frame: .zero)

        shapeLayer.fillColor = UIColor.systemBackground.cgColor
        shapeLayer.shadowColor = UIColor.label.cgColor
        shapeLayer.shadowRadius = 4.0
        shapeLayer.shadowOffset = .zero
        shapeLayer.shadowOpacity = 0.1
        layer.addSublayer(shapeLayer)

        backgroundColor = .clear
        addSubview(label)

        // Start observing device orientation changes
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        // Add the device orientation change notification
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Stop observing device orientation changes
        UIDevice.current.endGeneratingDeviceOrientationNotifications()

        // Remove the device orientation change notification
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    func install(source: UIView) {
        guard let window = UIWindow.currentKey(), let viewController = UIViewController.currentActive() else {
            return
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 10
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: UIFont.labelFontSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]

        // The bubble lives in the window, so it must be placed in window
        // coordinates. Wrapping still follows the presenting view, which on iPad
        // is a form sheet much narrower than the window.
        let leftLimit = 20 + window.safeAreaInsets.left
        let rightLimit = window.bounds.width - 20 - window.safeAreaInsets.right
        // Never wider than the span the bubble may occupy, otherwise a long text
        // in landscape would run past the safe area and clip its last words.
        let bubbleWidth = min(viewController.view.width - 40, rightLimit - leftLimit)

        var size = CGSize(width: bubbleWidth - cornerRadius * 2, height: 0)
        size = (desc as NSString).boundingRect(with: size, options: .usesLineFragmentOrigin, attributes: attributes, context: nil).size
        label.size = size
        label.numberOfLines = 0
        label.attributedText = NSAttributedString(string: desc, attributes: attributes)

        size.width += cornerRadius * 2
        size.height += cornerRadius * 2 + deltaHeight

        shapeLayer.frame = CGRect(origin: .zero, size: size)

        let sourceRect = window.convert(source.frame, from: source.superview)

        self.size = size
        var x = sourceRect.minX - 20
        if x < leftLimit {
            x = leftLimit
        } else if x + size.width > rightLimit {
            x = max(leftLimit, rightLimit - size.width)
        }
        self.left = x

        // Keep the arrow inside the rounded body even when the bubble had to be
        // pushed away from the source view.
        let anchorInset = cornerRadius + sharpWidth / 2
        let anchorX = min(max(sourceRect.midX - x, anchorInset), size.width - anchorInset)
        let anchorY: CGFloat
        let y: CGFloat
        if sourceRect.minY - deltaHeight - size.height - window.safeAreaInsets.top - 20 > 0 {
            y = sourceRect.minY - size.height
            anchorY = size.height
            label.origin = CGPoint(x: cornerRadius, y: cornerRadius)
        } else {
            y = sourceRect.maxY
            anchorY = 0
            label.origin = CGPoint(x: cornerRadius, y: cornerRadius + deltaHeight)
        }
        self.top = y

        let anchor = CGPoint(x: anchorX, y: anchorY)
        let path = CGPath.makeContextShape(anchor: anchor, bounds: bounds, cornerRadius: cornerRadius, deltaHeight: deltaHeight, sharpWidth: sharpWidth, sharpRadius: sharpRadius)
        shapeLayer.path = path

        let maskView = OCMaskView {
            self.removeFromSuperview()
            return true
        }

        maskView.bkColor = UIColor.white.withAlphaComponent(0.1)
        maskView.frame = window.bounds
        window.addSubview(maskView)
        self.maskedView = maskView

        window.addSubview(self)
    }

    @objc
    private func orientationChanged(notification: Notification) {
        let orientation = UIDevice.current.orientation
        if prevOrientation != orientation {
            prevOrientation = orientation

            removeFromSuperview()
            maskedView?.removeFromSuperview()
        }
    }
}
