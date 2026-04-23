//
//  CGPath+Extension.swift
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

import Foundation
import CoreGraphics

extension CGPath {
    class func makeContextShape(anchor: CGPoint, bounds: CGRect, cornerRadius r: CGFloat, deltaHeight dh: CGFloat, sharpWidth d: CGFloat, sharpRadius sr: CGFloat) -> CGPath {
        let path =  CGMutablePath()
        let w = bounds.width
        if anchor.y > bounds.midY {
            let h = bounds.height - dh
            path.move(to: CGPoint(x: 0, y: r))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .pi * 1.5, endAngle: .pi * 2, clockwise: false)
            path.addLine(to: CGPoint(x: w, y: h - r))
            path.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi * 0.5, clockwise: false)

            path.addLine(to: CGPoint(x: anchor.x + d, y: h))
            path.addLine(to: CGPoint(x: anchor.x + sr, y: h + (dh - sr)))
            path.addQuadCurve(to: CGPoint(x: anchor.x - sr, y: h + (dh - sr)), control: anchor)
            path.addLine(to: CGPoint(x: anchor.x - d, y: h))

            path.addLine(to: CGPoint(x: r, y: h))
            path.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi * 0.5, endAngle: .pi, clockwise: false)
            path.closeSubpath()
        } else {
            let s: CGFloat = dh
            let h = bounds.height

            path.move(to: CGPoint(x: 0, y: s + r))
            path.addArc(center: CGPoint(x: r, y: s + r), radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)

            path.addLine(to: CGPoint(x: anchor.x - d, y: s))
            path.addLine(to: CGPoint(x: anchor.x - sr, y: sr))
            path.addQuadCurve(to: CGPoint(x: anchor.x + sr, y: sr), control: anchor)
            path.addLine(to: CGPoint(x: anchor.x + d, y: s))

            path.addLine(to: CGPoint(x: w - r, y: s))
            path.addArc(center: CGPoint(x: w - r, y: s + r), radius: r, startAngle: .pi * 1.5, endAngle: .pi * 2, clockwise: false)
            path.addLine(to: CGPoint(x: w, y: h - r))
            path.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: .pi * 0.5, clockwise: false)
            path.addLine(to: CGPoint(x: r, y: h))
            path.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .pi * 0.5, endAngle: .pi, clockwise: false)
            path.closeSubpath()
        }
        return path
    }

    class func makeShapeArrow(anchor: CGPoint, bounds: CGRect, cornerRadius r: CGFloat, deltaHeight dh: CGFloat, sharpWidth d: CGFloat, sharpRadius sr: CGFloat) -> CGPath {
        let path =  CGMutablePath()
        if anchor.y > bounds.midY {
            let h = bounds.height - dh
            path.move(to: CGPoint(x: anchor.x + d, y: h))
            path.addLine(to: CGPoint(x: anchor.x + sr, y: h + (dh - sr)))
            path.addQuadCurve(to: CGPoint(x: anchor.x - sr, y: h + (dh - sr)), control: anchor)
            path.addLine(to: CGPoint(x: anchor.x - d, y: h))
        } else {
            let s: CGFloat = dh
            path.move(to: CGPoint(x: anchor.x - d, y: s))
            path.addLine(to: CGPoint(x: anchor.x - sr, y: sr))
            path.addQuadCurve(to: CGPoint(x: anchor.x + sr, y: sr), control: anchor)
            path.addLine(to: CGPoint(x: anchor.x + d, y: s))
            path.closeSubpath()
        }
        return path
    }

    func transformed(_ t: CGAffineTransform) -> CGPath? {
        let path = CGMutablePath()
        applyWithBlock { point in
            let element = point.pointee
            switch element.type {
                case .moveToPoint:
                    path.move(to: element.points.pointee, transform: t)
                case .addLineToPoint:
                    path.addLine(to: element.points.pointee, transform: t)
                case .addQuadCurveToPoint:
                    let pt1 = element.points.pointee
                    let pt2 = (element.points + 1).pointee
                    path.addQuadCurve(to: pt2, control: pt1, transform: t)
                case .addCurveToPoint:
                    let pt1 = element.points.pointee
                    let pt2 = (element.points + 1).pointee
                    let pt3 = (element.points + 2).pointee
                    path.addCurve(to: pt3, control1: pt1, control2: pt2, transform: t)
                case .closeSubpath:
                    path.closeSubpath()
                @unknown default:
                    break
            }
        }
        return path.copy()
    }
}
