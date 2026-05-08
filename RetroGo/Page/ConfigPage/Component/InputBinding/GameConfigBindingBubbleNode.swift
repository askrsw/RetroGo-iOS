//
//  GameConfigBindingBubbleNode.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/30.
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

import SpriteKit
import UIKit

final class GameConfigBindingBubbleNode: SKNode {
    enum PreferredPosition {
        case above
        case below
    }

    private let cornerRadius: CGFloat = 7
    private let arrowHeight: CGFloat = 8
    private let arrowWidth: CGFloat = 8
    private let arrowRadius: CGFloat = 3
    private let horizontalPadding: CGFloat = 9
    private let minimumHorizontalPadding: CGFloat = 5
    private let contentHeight: CGFloat = 24
    private let iconSize: CGFloat = 16
    private let contentSpacing: CGFloat = 4
    private let preferredFontSize: CGFloat = 13
    private let shortTextPreferredFontSize: CGFloat = 15
    private let minimumFontSize: CGFloat = 10

    private let shapeNode = SKShapeNode()
    private let labelNode = SKLabelNode()
    private var iconNode: SKSpriteNode?
    private var trackingTouch: ObjectIdentifier?
    private var contentOffset: CGPoint = .zero
    private var currentPreferredPosition: PreferredPosition = .above
    private var currentMaxWidth: CGFloat?

    private(set) var text: String = ""
    private(set) var systemImageName: String?
    var touchChanged: ((Bool) -> Void)?

    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            if !isActive {
                resetInteraction(shouldNotify: true)
            }
            updateAppearance()
        }
    }

    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            updatePressedScale()
        }
    }

    override init() {
        super.init()
        zPosition = 1000
        isUserInteractionEnabled = true

        shapeNode.lineWidth = 1.2
        addChild(shapeNode)

        labelNode.fontName = "Helvetica-Bold"
        labelNode.fontSize = preferredFontSize
        labelNode.verticalAlignmentMode = .center
        labelNode.horizontalAlignmentMode = .center
        addChild(labelNode)

        update(text: "Default", systemImageName: nil)
        updateAppearance()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, systemImageName: String? = nil) {
        self.text = text
        self.systemImageName = systemImageName
        labelNode.text = text
        updateIcon(systemImageName, color: labelTextColor)
        updateContentLayout(preferredPosition: currentPreferredPosition, maxWidth: currentMaxWidth)
    }

    func resetInteraction(shouldNotify: Bool = false) {
        let wasTouching = trackingTouch != nil || isPressed
        trackingTouch = nil
        isPressed = false
        if shouldNotify, wasTouching {
            touchChanged?(false)
        }
    }

    func updateLayout(anchor: CGPoint, preferredPosition: PreferredPosition = .above, maxWidth: CGFloat? = nil) {
        currentPreferredPosition = preferredPosition
        currentMaxWidth = maxWidth

        let size = preferredSize(maxWidth: maxWidth)
        let localAnchor: CGPoint

        switch preferredPosition {
        case .above:
            position = anchor
            localAnchor = CGPoint(x: size.width * 0.5, y: 0)
        case .below:
            position = anchor
            localAnchor = CGPoint(x: size.width * 0.5, y: size.height)
        }

        contentOffset = CGPoint(x: -localAnchor.x, y: -localAnchor.y)
        shapeNode.position = contentOffset

        let bounds = CGRect(origin: .zero, size: size)
        shapeNode.path = CGPath.makeContextShape(
            anchor: localAnchor,
            bounds: bounds,
            cornerRadius: cornerRadius,
            deltaHeight: arrowHeight,
            sharpWidth: arrowWidth,
            sharpRadius: arrowRadius
        )

        updateContentLayout(preferredPosition: preferredPosition, maxWidth: maxWidth)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingTouch == nil, let touch = touches.first else { return }
        trackingTouch = ObjectIdentifier(touch)
        isPressed = true
        touchChanged?(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let trackingTouch,
              let touch = touches.first(where: { ObjectIdentifier($0) == trackingTouch }) else {
            return
        }

        isPressed = contains(touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTracking(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTracking(touches)
    }
}

private extension GameConfigBindingBubbleNode {
    struct LayoutMetrics {
        let size: CGSize
        let fontSize: CGFloat
        let textWidth: CGFloat
        let iconWidth: CGFloat
    }

    func preferredSize(maxWidth: CGFloat? = nil) -> CGSize {
        layoutMetrics(maxWidth: maxWidth).size
    }

    func updateIcon(_ systemImageName: String?, color: UIColor) {
        iconNode?.removeFromParent()
        iconNode = nil

        guard let systemImageName,
              let image = tintedSystemImage(named: systemImageName, color: color) else {
            return
        }

        let node = SKSpriteNode(texture: SKTexture(image: image))
        node.size = CGSize(width: iconSize, height: iconSize)
        addChild(node)
        iconNode = node
    }

    func tintedSystemImage(named systemImageName: String, color: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .bold)
        guard let image = UIImage(systemName: systemImageName, withConfiguration: configuration) else {
            return nil
        }

        let bounds = CGRect(origin: .zero, size: image.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            color.setFill()
            UIRectFill(bounds)
            image.withRenderingMode(.alwaysTemplate).draw(in: bounds, blendMode: .destinationIn, alpha: 1.0)
        }
    }

    func updateContentLayout(preferredPosition: PreferredPosition = .above, maxWidth: CGFloat? = nil) {
        labelNode.xScale = 1
        let metrics = layoutMetrics(maxWidth: maxWidth)
        labelNode.fontSize = metrics.fontSize

        let contentCenterY: CGFloat
        switch preferredPosition {
        case .above:
            contentCenterY = arrowHeight + contentHeight * 0.5
        case .below:
            contentCenterY = contentHeight * 0.5
        }

        let totalWidth = metrics.textWidth + metrics.iconWidth
        var x = (metrics.size.width - totalWidth) * 0.5

        labelNode.position = CGPoint(
            x: contentOffset.x + x + metrics.textWidth * 0.5,
            y: contentOffset.y + contentCenterY
        )

        x += metrics.textWidth

        if let iconNode {
            if !text.isEmpty {
                x += contentSpacing
            }
            iconNode.position = CGPoint(
                x: contentOffset.x + x + iconSize * 0.5,
                y: contentOffset.y + contentCenterY
            )
        }
    }

    func layoutMetrics(maxWidth: CGFloat?) -> LayoutMetrics {
        let iconWidth = iconNode == nil ? 0 : iconSize + (text.isEmpty ? 0 : contentSpacing)
        let preferredFontSize = preferredFontSizeForCurrentText()
        let preferredTextWidth = textWidth(fontSize: preferredFontSize)
        let naturalWidth = ceil(preferredTextWidth + iconWidth + horizontalPadding * 2)
        let width = max(42, maxWidth.map { min(naturalWidth, max(42, $0)) } ?? naturalWidth)
        let contentPadding = max(
            minimumHorizontalPadding,
            min(horizontalPadding, floor((width - preferredTextWidth - iconWidth) * 0.5))
        )
        let availableTextWidth = max(18, width - contentPadding * 2 - iconWidth)

        var fontSize = preferredFontSize
        while fontSize > minimumFontSize && textWidth(fontSize: fontSize) > availableTextWidth {
            fontSize -= 1
        }

        return LayoutMetrics(
            size: CGSize(width: width, height: contentHeight + arrowHeight),
            fontSize: fontSize,
            textWidth: min(textWidth(fontSize: fontSize), availableTextWidth),
            iconWidth: iconWidth
        )
    }

    func textWidth(fontSize: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = UIFont(name: "Helvetica-Bold", size: fontSize) ?? UIFont.boldSystemFont(ofSize: fontSize)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return max(18, ceil(width))
    }

    func updateAppearance() {
        let textColor = labelTextColor
        if isActive {
            shapeNode.fillColor = UIColor(red: 0.72, green: 0.32, blue: 0.08, alpha: 1.0)
            shapeNode.strokeColor = UIColor.white
        } else {
            shapeNode.fillColor = UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1.0)
            shapeNode.strokeColor = UIColor(red: 0.78, green: 0.78, blue: 0.84, alpha: 1.0)
        }
        labelNode.fontColor = textColor
        updateIcon(systemImageName, color: textColor)
        updateContentLayout(preferredPosition: currentPreferredPosition, maxWidth: currentMaxWidth)
    }

    var labelTextColor: UIColor {
        .white
    }

    func preferredFontSizeForCurrentText() -> CGFloat {
        guard systemImageName == nil,
              text.count <= 2 else {
            return preferredFontSize
        }

        return shortTextPreferredFontSize
    }

    func updatePressedScale() {
        removeAction(forKey: "binding-bubble-press")
        let scale = isPressed ? 1.08 : 1.0
        let action = SKAction.scale(to: scale, duration: 0.08)
        action.timingMode = .easeOut
        run(action, withKey: "binding-bubble-press")
    }

    func endTracking(_ touches: Set<UITouch>) {
        guard let trackingTouch,
              touches.contains(where: { ObjectIdentifier($0) == trackingTouch }) else {
            return
        }
        resetInteraction()
        touchChanged?(false)
    }
}
