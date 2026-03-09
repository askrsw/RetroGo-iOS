//
//  RetroRomFileTag.swift
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

final class RetroRomFileTag: NSObject {
    static let untaged = RetroRomFileTag(id: 0, title: nil, color: nil, createAt: Date(), isHidden: false)

    static let kUserTagIdStart = 1000

    let id: Int
    private(set) var title: String?
    private(set) var color: Int?
    let createAt: Date
    private(set) var isHidden: Bool

    private(set) var stored: Bool

    var expanded: Bool = true

    @objc
    dynamic var itemCount = 0

    init(id: Int, title: String?, color: Int?, createAt: Date, isHidden: Bool, stored: Bool = true) {
        self.id       = id
        self.title    = title
        self.color    = color
        self.createAt = createAt
        self.stored   = stored
        self.isHidden = false
        super.init()
    }

    var isSystemTag: Bool {
        id < Self.kUserTagIdStart
    }

    var showTitle: String {
        switch id {
            case 0: return Bundle.localizedString(forKey: "homepage_no_tag")
            case 1: return Bundle.localizedString(forKey: "red")
            case 2: return Bundle.localizedString(forKey: "orange")
            case 3: return Bundle.localizedString(forKey: "yellow")
            case 4: return Bundle.localizedString(forKey: "green")
            case 5: return Bundle.localizedString(forKey: "blue")
            case 6: return Bundle.localizedString(forKey: "purple")
            case 7: return Bundle.localizedString(forKey: "gray")
            case Self.kUserTagIdStart...: return title ?? ""
            default: return ""
        }
    }

    var showColor: UIColor? {
        switch id {
            case 0: return .label
            case 1: return .red
            case 2: return .orange
            case 3: return .yellow
            case 4: return .green
            case 5: return .blue
            case 6: return .purple
            case 7: return .gray
            case Self.kUserTagIdStart...: return color != nil ? UIColor(hex: UInt32(color!)) : nil
            default: return nil
        }
    }

    var tagImage: UIImage? {
        if id != 0 {
            return UIImage(systemName: "tag.fill")
        } else {
            return UIImage(systemName: "tag.slash.fill")
        }
    }

    func store(title: String, colorValue: Int?) -> Bool {
        if let colorValue = colorValue {
            self.color = colorValue
        }
        self.title = title
        if RetroRomFileManager.shared.storeFileTag(self) {
            stored = true
            NotificationCenter.default.post(name: .fileTagAdded, object: self)
            return true
        } else {
            return false
        }
    }

    func update(title: String?, colorValue: Int?) -> Bool {
        let newTitle: String?
        if let title = title {
            self.title = title
            newTitle = title
        } else {
            newTitle = nil
        }

        let newColor: Int?
        if let colorValue = colorValue {
            self.color = colorValue
            newColor = colorValue
        } else {
            newColor = nil
        }

        if newTitle == nil && newColor == nil {
            return true
        }

        if RetroRomFileManager.shared.updateFiltTag(id: id, title: self.title, color: self.color) {
            if newColor != nil {
                NotificationCenter.default.post(name: .fileTagColorChanged, object: id)
            }
            if newTitle != nil {
                NotificationCenter.default.post(name: .fileTagTitleChanged, object: self)
            }
            return true
        } else {
            return false
        }
    }
}

extension RetroRomFileTag {
    static func makeAttributedTagText(_ tags: [RetroRomFileTag], attributes: [NSAttributedString.Key: Any], refFont: UIFont) -> NSAttributedString {
        let radius: CGFloat = 4
        let delta: CGFloat  = 3
        let height: CGFloat = radius * 2
        let layer = CALayer()

        let y: CGFloat = height * 0.5 - radius - refFont.descender * 0.75
        var x: CGFloat = height * 0.5 - radius
        var circles: [CALayer] = []
        for tag in tags {
            guard let color = tag.showColor else {
                continue
            }

            let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
            let circle = CAShapeLayer()
            let path = UIBezierPath(ovalIn: rect)
            circle.path = path.cgPath
            circle.fillColor = color.cgColor
            circle.strokeColor = nil
            circles.append(circle)

            if circles.count >= 4 {
                break
            }

            x += delta
        }

        circles.reversed().forEach({ layer.addSublayer($0) })

        let width: CGFloat = radius * 2 + delta * CGFloat(circles.count)
        layer.frame = CGRect(x: 0, y: 0, width: width, height: height - refFont.descender)

        let renderer = UIGraphicsImageRenderer(size: layer.bounds.size)
        let image = renderer.image { context in
            layer.render(in: context.cgContext)
        }
        let attatchment = NSTextAttachment(image: image)
        if #available(iOS 18.0, *) {
            return NSAttributedString(attachment: attatchment, attributes: attributes)
        } else {
            return NSAttributedString(attachment: attatchment)
        }
    }
}
