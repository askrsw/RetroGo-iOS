//
//  GameOverlayLayoutResolver.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/29.
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

struct GameOverlayLayoutResolver {
    enum Mode {
        case portrait
        case landscape
    }

    let config: GamePageOverlayConfig
    /// User layout applied on top of the JSON; nil keeps the built-in layout.
    var layoutData: GameOverlayLayoutData?

    private(set) var size: CGSize = .zero
    private(set) var mode: Mode = .portrait
    private(set) var scaleFactor: CGFloat = 1.0
    private(set) var contentOffset: CGPoint = .zero
    private(set) var polarAnchor: CGPoint = .zero

    init(config: GamePageOverlayConfig) {
        self.config = config
    }

    /// Freeze retired non-polar group transforms into independent button geometry.
    static func migrateIndependentGroups(_ source: GameOverlayLayoutData, config: GamePageOverlayConfig) -> GameOverlayLayoutData {
        var data = source
        for portrait in [true, false] {
            guard var orientation = data.orientation(portrait: portrait) else { continue }
            var resolver = Self(config: config)
            let reference = portrait ? config.portraitRefSize : config.landscapeRefSize
            resolver.update(size: CGSize(width: reference.width, height: reference.height))
            resolver.layoutData = data
            let fanNames = Set(resolver.fanSlotElements.compactMap(\.group))
            for (name, group) in orientation.groups where !fanNames.contains(name) {
                let pivot = resolver.groupPivot(name, usePolarLayout: false)
                let scale = group.scale ?? 1
                for element in config.elements where element.group == name && orientation.elements[element.id]?.layout == nil && !group.isEmpty {
                    let rect = resolver.resolveRect(element, usePolarLayout: false)
                    let center = CGPoint(x: pivot.x + (rect.midX - pivot.x) * scale + group.offsetX,
                                         y: pivot.y + (rect.midY - pivot.y) * scale + group.offsetY)
                    var custom = orientation.elements[element.id] ?? .init()
                    custom.layout = resolver.plainInsets(for: Self.rect(center: center, size: CGSize(width: rect.width * scale, height: rect.height * scale)))
                    custom.scale = (custom.scale ?? 1) * scale
                    orientation.elements[element.id] = custom
                }
                orientation.groups.removeValue(forKey: name)
            }
            data.setOrientation(orientation, portrait: portrait)
        }
        return data
    }
    var fanSlotElements: [GamePageOverlayElement] {
        config.elements.filter { $0.group != nil && !$0.isHidden && basePolarLayout(for: $0) != nil }
    }
    func occupant(of slotId: String) -> GamePageOverlayElement? {
        let slots = fanSlotElements
        guard let index = slots.firstIndex(where: { $0.id == slotId }) else { return nil }
        func assignedId(_ slot: GamePageOverlayElement) -> String {
            customOrientation()?.slots?[slot.id] ?? (customElement(for: slot)?.layout == nil ? slot.id : "")
        }
        let id = assignedId(slots[index])
        guard !id.isEmpty else { return nil }
        // Deterministic protection against duplicate references in imported data.
        guard !slots.prefix(index).contains(where: { assignedId($0) == id }) else { return nil }
        return config.elements.first { $0.id == id && Self.canEnterFan($0) && !$0.isHidden }
    }
    func slot(for element: GamePageOverlayElement) -> GamePageOverlayElement? {
        fanSlotElements.first { occupant(of: $0.id)?.id == element.id }
    }
    func fanGroup(for element: GamePageOverlayElement) -> String? { slot(for: element)?.group }

    /// The shell belongs to the bundle slots, not to their current occupants.
    /// Screen adaptation and the user's group scale apply exactly once.
    func fanDiameter(in group: String) -> CGFloat? {
        guard let reference = fanReferenceDiameter(in: group) else { return nil }
        return reference * scaleFactor * CGFloat(customOrientation()?.groups[group]?.scale ?? 1)
    }

    private func fanReferenceDiameter(in group: String) -> CGFloat? {
        fanSlotElements.filter { $0.group == group }
            .map { CGFloat(min($0.geometry.size.width, $0.geometry.size.height)) }.max()
    }
    static func canEnterFan(_ element: GamePageOverlayElement) -> Bool {
        switch element.type {
        case .combo, .macro: return true
        case .button:
            return !element.binds.isEmpty && element.binds.allSatisfy { !["UP", "DOWN", "LEFT", "RIGHT", "START", "SELECT"].contains($0.rawValue) }
        default: return false
        }
    }
    /// The placeholder uses bundle geometry even when no button occupies it.
    func slotRect(_ id: String) -> CGRect? {
        guard let element = fanSlotElements.first(where: { $0.id == id }) else { return nil }
        var copy = self
        var data = layoutData ?? .init()
        var orientation = customOrientation() ?? .init()
        orientation.slots = Dictionary(uniqueKeysWithValues: fanSlotElements.map { ($0.id, $0.id) })
        orientation.elements[element.id]?.layout = nil
        orientation.elements[element.id]?.scale = nil
        data.setOrientation(orientation, portrait: mode == .portrait)
        copy.layoutData = data
        return copy.resolveRect(element, usePolarLayout: true)
    }

    mutating func update(size: CGSize, contentOffset: CGPoint = .zero) {
        self.size = size
        self.contentOffset = contentOffset
        self.mode = size.width < size.height ? .portrait : .landscape
        self.scaleFactor = resolveScaleFactor()
        self.polarAnchor = resolvePolarAnchor(mode == .portrait ? config.portraitPolarAnchor : config.landscapePolarAnchor)
    }

    /// Frame of an element: the JSON layout, then the custom layout's group
    /// transform, then the element's own position and size.
    func resolveRect(_ element: GamePageOverlayElement, usePolarLayout: Bool) -> CGRect {
        let custom = customElement(for: element)
        let memberGroup = fanGroup(for: element)
        let elementScale = memberGroup == nil ? CGFloat(custom?.scale ?? 1) : 1

        // An element given its own position leaves the arc and its group.
        if slot(for: element) == nil, let insets = custom?.layout {
            return resolvePlainRect(size: scaledSize(element, multiplier: elementScale), insets: insets)
        }

        var rect = resolveBuiltInRect(element, usePolarLayout: usePolarLayout)

        if let groupName = memberGroup,
           let group = customOrientation()?.groups[groupName], !group.isEmpty {
            let pivot = groupPivot(groupName, usePolarLayout: usePolarLayout)
            let groupScale = CGFloat(group.scale ?? 1)
            // Offsets are in reference units, +y up like the scene.
            let center = CGPoint(
                x: pivot.x + (rect.midX - pivot.x) * groupScale + CGFloat(group.offsetX) * scaleFactor,
                y: pivot.y + (rect.midY - pivot.y) * groupScale + CGFloat(group.offsetY) * scaleFactor
            )
            rect = Self.rect(center: center, size: CGSize(width: rect.width * groupScale, height: rect.height * groupScale))
        }

        if elementScale != 1 {
            rect = Self.rect(center: CGPoint(x: rect.midX, y: rect.midY),
                             size: CGSize(width: rect.width * elementScale, height: rect.height * elementScale))
        }
        if let memberGroup, let diameter = fanDiameter(in: memberGroup) {
            rect = Self.rect(center: CGPoint(x: rect.midX, y: rect.midY),
                             size: CGSize(width: diameter, height: diameter))
        }
        return rect
    }

    /// Whether the custom layout hides the element; only extension buttons can be hidden.
    /// Combos are hidden unless the layout shows them, the built-in layout included.
    func isHiddenByCustomLayout(_ element: GamePageOverlayElement) -> Bool {
        guard element.isHideableInCustomLayout else { return false }
        return customElement(for: element)?.hidden ?? element.isHiddenByDefaultInCustomLayout
    }


    /// Whether the custom layout gives the element its own position, outside the arc and its group.
    func hasCustomPosition(_ element: GamePageOverlayElement) -> Bool {
        slot(for: element) == nil && customElement(for: element)?.layout != nil
    }

    /// Plain-layout insets that place an element at `rect`, measured in reference
    /// units from the nearest horizontal and vertical edges so the position
    /// follows the closest screen edge on other screen sizes.
    func plainInsets(for rect: CGRect) -> GamePageOverlayInsets {
        let scale = max(scaleFactor, 0.001)
        let frame = rect.offsetBy(dx: -contentOffset.x, dy: -contentOffset.y)
        let left = frame.midX <= size.width * 0.5 ? Double(frame.minX / scale) : nil
        let right = left == nil ? Double((size.width - frame.maxX) / scale) : nil
        let bottom = frame.midY <= size.height * 0.5 ? Double(frame.minY / scale) : nil
        let top = bottom == nil ? Double((size.height - frame.maxY) / scale) : nil
        return GamePageOverlayInsets(top: top, left: left, bottom: bottom, right: right, centerX: nil, centerY: nil)
    }

    func resolveRotation(_ element: GamePageOverlayElement, usePolarLayout: Bool, rotatesWithPolarLayout: Bool) -> CGFloat {
        if slot(for: element) == nil, let rotation = customElement(for: element)?.rotation { return CGFloat(rotation * .pi / 180) }
        guard usePolarLayout,
              rotatesWithPolarLayout,
              !hasCustomPosition(element),
              let polar = polarLayout(for: element) else {
            return 0
        }

        // Note: theta is stored in degrees in overlay JSON.
        let thetaRadians = polar.theta * Double.pi / 180.0

        // SKLabelNode text runs along local +X, so local +Y should point to the radius.
        return CGFloat(thetaRadians - Double.pi / 2.0)
    }
}

private extension GameOverlayLayoutResolver {
    /// The custom layout for the current orientation.
    func customOrientation() -> GameOverlayLayoutData.Orientation? {
        layoutData?.orientation(portrait: mode == .portrait)
    }

    func customElement(for element: GamePageOverlayElement) -> GameOverlayLayoutData.Element? {
        customOrientation()?.elements[element.id]
    }

    func scaledSize(_ element: GamePageOverlayElement, multiplier: CGFloat = 1) -> CGSize {
        if let group = fanGroup(for: element), let reference = fanReferenceDiameter(in: group) {
            let diameter = reference * scaleFactor * multiplier
            return CGSize(width: diameter, height: diameter)
        }
        let elementSize = element.geometry.size
        return CGSize(
            width: CGFloat(elementSize.width) * scaleFactor * multiplier,
            height: CGFloat(elementSize.height) * scaleFactor * multiplier
        )
    }

    func resolveBuiltInRect(_ element: GamePageOverlayElement, usePolarLayout: Bool) -> CGRect {
        let size = scaledSize(element)
        if usePolarLayout, let polar = polarLayout(for: element) {
            return resolvePolarRect(size: size, polar: polar,
                                    anchor: polarAnchor)
        }
        return resolvePlainRect(size: size, insets: plainLayout(for: slot(for: element) ?? element))
    }

    /// Center of the group's built-in bounds; scaling about it keeps the group in place.
    func groupPivot(_ groupName: String, usePolarLayout: Bool) -> CGPoint {
        let bounds = config.elements
            .filter { $0.group == groupName }
            .map { element in
                let size = CGSize(width: element.geometry.size.width * scaleFactor, height: element.geometry.size.height * scaleFactor)
                if usePolarLayout, let polar = basePolarLayout(for: element) {
                    return resolvePolarRect(size: size, polar: polar, anchor: polarAnchor)
                }
                return resolvePlainRect(size: size, insets: plainLayout(for: element))
            }
            .reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else { return .zero }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    static func rect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: center.x - size.width * 0.5, y: center.y - size.height * 0.5, width: size.width, height: size.height)
    }

    func resolvePolarRect(size: CGSize, polar: GamePageOverlayPolar, anchor: CGPoint) -> CGRect {
        let theta = polar.theta * Double.pi / 180.0
        let radius = polar.radius * Double(scaleFactor)

        let center = CGPoint(
            x: anchor.x + cos(theta) * radius,
            y: anchor.y + sin(theta) * radius
        )

        let origin = CGPoint(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5
        )

        return CGRect(origin: origin, size: size)
    }

    func resolvePlainRect(size: CGSize, insets: GamePageOverlayInsets) -> CGRect {
        let scaledInsets = scale(insets)

        let x: CGFloat
        if let centerXInset = scaledInsets.centerX {
            let centerX = self.size.width * 0.5
            x = centerX + centerXInset
        } else if let left = scaledInsets.left {
            x = left
        } else if let right = scaledInsets.right {
            x = self.size.width - right - size.width
        } else {
            let centerX = self.size.width * 0.5
            x = centerX - size.width * 0.5
        }

        let y: CGFloat
        if let centerYInset = scaledInsets.centerY {
            let centerY = self.size.height * 0.5
            y = centerY + centerYInset
        } else if let bottom = scaledInsets.bottom {
            y = bottom
        } else if let top = scaledInsets.top {
            y = self.size.height - top - size.height
        } else {
            let centerY = self.size.height * 0.5
            y = centerY - size.height * 0.5
        }

        let scaledOrigin = CGPoint(x: x + contentOffset.x, y: y + contentOffset.y)

        return CGRect(origin: scaledOrigin, size: size)
    }

    func resolvePolarAnchor(_ insets: GamePageOverlayInsets) -> CGPoint {
        let scaledInsets = scale(insets)

        let x: CGFloat
        if let centerXInset = scaledInsets.centerX {
            let centerX = size.width * 0.5
            x = centerX + centerXInset
        } else if let left = scaledInsets.left {
            x = left
        } else if let right = scaledInsets.right {
            x = size.width - right
        } else {
            x = size.width * 0.5
        }

        let y: CGFloat
        if let centerYInset = scaledInsets.centerY {
            let centerY = size.height * 0.5
            y = centerY + centerYInset
        } else if let bottom = scaledInsets.bottom {
            y = bottom
        } else if let top = scaledInsets.top {
            y = size.height - top
        } else {
            y = size.height * 0.5
        }

        return CGPoint(x: x + contentOffset.x, y: y + contentOffset.y)
    }

    func resolveScaleFactor() -> CGFloat {
        let reference = mode == .portrait ? config.portraitRefSize : config.landscapeRefSize
        let refWidth = CGFloat(reference.width)
        let refHeight = CGFloat(reference.height)
        let scaleX = size.width / refWidth
        let scaleY = size.height / refHeight
        return min(1, scaleX, scaleY)
    }

    func scale(_ insets: GamePageOverlayInsets) -> GamePageOverlayInsets {
        GamePageOverlayInsets(
            top: insets.top.map { $0 * scaleFactor },
            left: insets.left.map { $0 * scaleFactor },
            bottom: insets.bottom.map { $0 * scaleFactor },
            right: insets.right.map { $0 * scaleFactor },
            centerX: insets.centerX.map { $0 * scaleFactor },
            centerY: insets.centerY.map { $0 * scaleFactor }
        )
    }

    func plainLayout(for element: GamePageOverlayElement) -> GamePageOverlayInsets {
        mode == .portrait ? element.geometry.plainPortraitLayout : element.geometry.plainLandscapeLayout
    }

    func polarLayout(for element: GamePageOverlayElement) -> GamePageOverlayPolar? {
        guard let slot = slot(for: element), let base = basePolarLayout(for: slot), let name = slot.group else { return nil }
        guard let fan = customOrientation()?.groups[name]?.fan else { return base }
        let members = fanSlotElements.filter { $0.group == name }.compactMap(basePolarLayout)
        guard let inner = members.map(\.radius).min(), let first = members.map(\.theta).min(), let last = members.map(\.theta).max() else { return base }
        return fan.adjusted(base, centerTheta: (first + last) / 2, innerRadius: inner)
    }

    func basePolarLayout(for element: GamePageOverlayElement) -> GamePageOverlayPolar? {
        mode == .portrait ? element.geometry.polarPortraitLayout : element.geometry.polarLandscapeLayout
    }
}


protocol GameOverlaySceneLayouting: AnyObject {
    var overlayLayoutResolver: GameOverlayLayoutResolver { get set }
    var usePolarLayout: Bool { get }
}

extension GameOverlaySceneLayouting where Self: SKScene {
    func updateOverlayLayout(for size: CGSize, contentOffset: CGPoint = .zero) {
        self.size = size
        var resolver = overlayLayoutResolver
        resolver.update(size: size, contentOffset: contentOffset)
        overlayLayoutResolver = resolver
    }

    func resolveOverlayRect(_ element: GamePageOverlayElement) -> CGRect {
        overlayLayoutResolver.resolveRect(element, usePolarLayout: usePolarLayout)
    }

    func resolveOverlayRotation(_ element: GamePageOverlayElement, rotatesWithPolarLayout: Bool) -> CGFloat {
        overlayLayoutResolver.resolveRotation(
            element,
            usePolarLayout: usePolarLayout,
            rotatesWithPolarLayout: rotatesWithPolarLayout
        )
    }
}
