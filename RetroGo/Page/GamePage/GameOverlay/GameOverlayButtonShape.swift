//
//  GameOverlayButtonShape.swift
//  RetroGo
//
//  Created by haharsw on 2026/3/30.
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

enum GameOverlayButtonShape: Equatable {
    case circle(radius: CGFloat)
    case capsule(width: CGFloat, height: CGFloat)
    case rect(width: CGFloat, height: CGFloat)
    case rounded(width: CGFloat, height: CGFloat)

    static func makeShape(from shape: GamePageOverlayShape, rect: CGRect) -> Self {
        switch shape {
            case .circle:
                let radius = min(rect.width, rect.height) * 0.5
                return .circle(radius: radius)
            case .capsule:
                return .capsule(width: rect.width, height: rect.height)
            case .rect:
                return .rect(width: rect.width, height: rect.height)
            case .rounded:
                return .rounded(width: rect.width, height: rect.height)
        }
    }
}

extension GameOverlayButtonShape {
    var path: CGPath {
        switch self {
            case .circle(let radius):
                let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
                return CGPath(ellipseIn: rect, transform: nil)
            case .capsule(let width, let height):
                let rect = CGRect(x: -width * 0.5, y: -height * 0.5, width: width, height: height)
                let cornerRaidus = height * 0.5
                return CGPath(roundedRect: rect, cornerWidth: cornerRaidus, cornerHeight: cornerRaidus, transform: nil)
            case .rect(let width, let height):
                let rect = CGRect(x: -width * 0.5, y: -height * 0.5, width: width, height: height)
                return CGPath(rect: rect, transform: nil)
            case .rounded(let width, let height):
                let rect = CGRect(x: -width * 0.5, y: -height * 0.5, width: width, height: height)
                let cornerRaidus = width * 0.15
                return CGPath(roundedRect: rect, cornerWidth: cornerRaidus, cornerHeight: cornerRaidus, transform: nil)
        }
    }

    var size: CGSize {
        switch self {
            case .circle(let radius):
                return CGSize(width: radius * 2, height: radius * 2)
            case .capsule(let width, let height):
                return CGSize(width: width, height: height)
            case .rect(let width, let height):
                return CGSize(width: width, height: height)
            case .rounded(let width, let height):
                return CGSize(width: width, height: height)
        }
    }

    var fontSize: CGFloat {
        switch self {
            case .circle(let r):
                return r * 2 * 0.7
            case .capsule(_, let h):
                return h * 0.6
            case .rect(let w, let h):
                return min(w, h) * 0.6
            case .rounded(let w, let h):
                return min(w, h) * 0.6
        }
    }

    func fixLabelPosition(_ label: SKLabelNode) {
        switch self {
            case .circle(_):
                label.position = .zero
            case .capsule(_, _):
                label.position = .zero
            case .rect(_, _):
                label.position = .zero
            case .rounded(_, _):
                label.position = .zero
        }
    }
}
