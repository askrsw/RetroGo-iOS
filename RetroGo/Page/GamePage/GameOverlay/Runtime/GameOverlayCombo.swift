//
//  GameOverlayCombo.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/9.
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
import RACoordinator

/// A native controller button a combo can press, named as the overlay shows it.
struct GameOverlayComboKey: Equatable {
    let bind: GamePageOverlayAction
    let title: String
    /// SF Symbol drawn instead of the name inside a combo: a short one for Start and
    /// Select, and the PlayStation shapes, whose text glyphs come out uneven in size.
    let symbol: String?

    /// Menu buttons and PlayStation shapes use their symbols without a text label.
    var symbolReplacesTitle: Bool {
        symbol != nil && (title.count == 1 || symbol == GameOverlayComboTitle.startSymbol || symbol == GameOverlayComboTitle.selectSymbol)
    }

    var titlePart: GameOverlayComboTitle.Part {
        symbol.map { .symbol($0, text: title) } ?? .text(Self.comboText(title))
    }

    /// Long names that have no fitting symbol shorten to their initial inside a combo,
    /// so A+MODE reads as A M like the other buttons (Genesis MODE).
    private static func comboText(_ title: String) -> String {
        title == "MODE" ? "M" : title
    }
}

/// What a combo shows: its buttons, with Start and Select drawn as the menu and
/// view symbols of today's controllers so the title stays short, and the
/// PlayStation shapes drawn as symbols of one size. On the button and the panel
/// chip the buttons sit side by side; text elsewhere joins them with "+".
struct GameOverlayComboTitle: Equatable {
    enum Part: Equatable {
        case text(String)
        /// A symbol, and the name it stands for where only text fits.
        case symbol(String, text: String)
    }

    static let startSymbol = "line.3.horizontal"
    static let selectSymbol = "rectangle.on.rectangle"

    let parts: [Part]

    var hasSymbols: Bool {
        parts.contains { if case .symbol = $0 { return true } else { return false } }
    }

    /// "A+B+SELECT+START", for places that can only show text.
    var plainText: String {
        parts.map { part in
            switch part {
            case .text(let text), .symbol(_, let text): return text
            }
        }.joined(separator: "+")
    }

    /// Rough width in characters of the side-by-side form; a symbol is about as wide as 1.6 letters.
    var width: Double {
        parts.enumerated().reduce(0) { total, entry in
            let (index, part) = entry
            let spacing = compactSpacing(before: index) / 0.55
            switch part {
            case .text(let text): return total + spacing + Double(text.count)
            case .symbol(let name, _): return total + spacing + (name == Self.startSymbol ? 1.1 : 1.6)
            }
        }
    }

    /// Compact spacing in font-size units; letters touch, menu symbols breathe,
    /// and turbo is separated more clearly from the input labels.
    static let menuGap = 0.18
    static let turboGap = 0.4

    func compactSpacing(before index: Int) -> Double {
        guard index > 0, index < parts.count else { return 0 }
        if case .symbol("bolt.fill", _) = parts[index] { return Self.turboGap }
        let hasDirection = [parts[index - 1], parts[index]].contains {
            if case .symbol(let name, _) = $0 { return name == "arrow.left" || name == "arrow.right" }
            return false
        }
        if hasDirection { return 0.3 }
        let hasMenuSymbol = [parts[index - 1], parts[index]].contains { part in
            guard case .symbol(let name, _) = part else { return false }
            return name == Self.startSymbol || name == Self.selectSymbol
        }
        return hasMenuSymbol ? Self.menuGap : 0
    }

    /// The title for labels and buttons; the symbols take the text color.
    /// `joined` puts "+" between the buttons; otherwise they are contiguous.
    /// Size of a symbol drawn among letters, from its trimmed image: a little taller than
    /// their capitals (shapes read smaller than letters of the same height), and no wider
    /// than 1.6 of that, so wide symbols like the menu lines stay in step with the letters.
    /// Compact facing markers and full-size directional inputs have separate sizing rules.
    static func symbolSize(_ natural: CGSize, capHeight: CGFloat, name: String, compactDirections: Bool = true) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return .zero }
        if compactDirections && (name == "arrow.left" || name == "arrow.right") {
            let height = capHeight * 0.45
            return CGSize(width: natural.width * height / natural.height, height: height)
        }
        if !compactDirections && ["arrow.up", "arrow.down", "arrow.left", "arrow.right"].contains(name) {
            let scale = capHeight * 1.08 / max(natural.width, natural.height)
            return CGSize(width: natural.width * scale, height: natural.height * scale)
        }
        if name == startSymbol {
            let height = capHeight * 1.08
            return CGSize(width: min(natural.width * height / natural.height, capHeight * 1.1), height: height)
        }
        if name == "bolt.fill" {
            return CGSize(width: natural.width * capHeight / natural.height, height: capHeight)
        }
        let scale = min(capHeight * 1.08 / natural.height, capHeight * 1.6 / natural.width)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    private static let symbolCache = NSCache<NSString, UIImage>()

    /// A symbol drawn white and cropped to its ink. SF Symbol images carry padding around
    /// the shape, more for round shapes, so sizing the uncropped image left them smaller
    /// than the letters. Medium weight matches the labels' strokes. Template, so text
    /// attachments take the text color; SpriteKit tints the white.
    static func symbolImage(_ name: String, pointSize: CGFloat = 60, compactDirections: Bool = true) -> UIImage? {
        let cacheKey = "\(name):\(pointSize):\(compactDirections)" as NSString
        if let cached = symbolCache.object(forKey: cacheKey) { return cached }
        let weight: UIImage.SymbolWeight = compactDirections && (name == "arrow.left" || name == "arrow.right") ? .heavy : .medium
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let rendered = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        guard let cgImage = rendered.cgImage, let ink = inkBounds(cgImage),
              let cropped = cgImage.cropping(to: ink) else { return nil }
        let image = UIImage(cgImage: cropped, scale: format.scale, orientation: .up).withRenderingMode(.alwaysTemplate)
        symbolCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// Pixel bounds of everything not transparent.
    private static func inkBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func attributedString(font: UIFont, joined: Bool = true, minimumSpacing: Double = 0, symbolScale: CGFloat = 1, directionScale: CGFloat = 1, compactDirections: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0, joined {
                result.append(NSAttributedString(string: "+"))
            } else if index > 0, max(compactSpacing(before: index), minimumSpacing) > 0 {
                let naturalSpace = (" " as NSString).size(withAttributes: [.font: font]).width
                let gap = font.pointSize * CGFloat(max(compactSpacing(before: index), minimumSpacing))
                result.append(NSAttributedString(string: " ", attributes: [.kern: gap - naturalSpace]))
            }
            switch part {
            case .text(let text):
                result.append(NSAttributedString(string: text))
            case .symbol(let name, let text):
                let isMarker = compactDirections && (name == "arrow.left" || name == "arrow.right")
                // Tiny UIKit markers need SF Symbols' optical weight at their display size.
                let pointSize = isMarker ? font.capHeight * 0.45 * directionScale : 60
                if let image = Self.symbolImage(name, pointSize: pointSize, compactDirections: compactDirections) {
                    // The image convenience initializer can discard custom attachment bounds.
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    let scale = isMarker ? directionScale : symbolScale
                    let size = Self.symbolSize(image.size, capHeight: font.capHeight * scale, name: name, compactDirections: compactDirections)
                    // Sits on the baseline, centered on the capitals.
                    attachment.bounds = CGRect(origin: CGPoint(x: 0, y: (font.capHeight - size.height) * 0.5), size: size)
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    result.append(NSAttributedString(string: text))
                }
            }
        }
        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Stored in the element meta as strings, a symbol as `{"symbol", "text"}`.
    var jsonValue: JSONValue {
        .array(parts.map { part in
            switch part {
            case .text(let text): return .string(text)
            case .symbol(let name, let text): return .object(["symbol": .string(name), "text": .string(text)])
            }
        })
    }

    init(parts: [Part]) {
        self.parts = parts
    }

    init?(jsonValue: JSONValue?) {
        guard case .array(let values) = jsonValue else { return nil }
        parts = values.compactMap { value in
            switch value {
            case .string(let text):
                return .text(text)
            case .object(let object):
                guard case .string(let name) = object["symbol"], case .string(let text) = object["text"] else { return nil }
                return .symbol(name, text: text)
            default:
                return nil
            }
        }
    }
}

extension GamePageOverlayGeometry {
    /// Geometry of a combo before it is sized and placed: centered, never shown as is,
    /// because the layout editor gives a combo its own position when it is shown.
    static let comboPlaceholder = combo(width: 50)

    static func combo(width: Double) -> Self {
        let height = 35.0
        let centered = GamePageOverlayInsets(top: nil, left: nil, bottom: nil, right: nil,
                                             centerX: -width * 0.5, centerY: -height * 0.5)
        return GamePageOverlayGeometry(shape: .capsule, size: GamePageOverlaySize(width: width, height: height),
                                       plainPortraitLayout: centered, plainLandscapeLayout: centered,
                                       polarPortraitLayout: nil, polarLandscapeLayout: nil)
    }

    /// Wide enough for the title; longer titles shrink their font to fit.
    static func combo(title: GameOverlayComboTitle) -> Self {
        combo(width: min(100, max(50, 18 + 11 * title.width)))
    }
}

extension GamePageOverlayElement {
    /// A combo's title with its Start and Select symbols; nil for other controls.
    var comboTitle: GameOverlayComboTitle? {
        GameOverlayComboTitle(jsonValue: meta?["title_parts"])
    }

    /// Label of a button as the overlay draws it: its title, or the PlayStation symbol.
    var buttonTitle: String {
        if let title { return title }
        switch psActionButtonIcon {
        case .triangle: return "△"
        case .circle: return "○"
        case .cross: return "×"
        case .square: return "□"
        case nil: return id.uppercased()
        }
    }
}

extension GamePageOverlayConfig {
    /// Native buttons a combo can press, in JSON order with Start and Select last.
    /// Directions are left out: the D-pad is under the other thumb anyway.
    var comboKeys: [GameOverlayComboKey] {
        var seen = Set<String>()
        var keys: [GameOverlayComboKey] = []
        var menuKeys: [GameOverlayComboKey] = []
        for element in elements where element.type == .button && element.isNative && element.binds.count == 1 {
            let bind = element.binds[0]
            guard bind.code != .none, seen.insert(bind.rawValue).inserted else { continue }
            let title = element.buttonTitle
            // Only the plain names become symbols; MODE (Genesis) and $ (arcade coin) say more than an icon.
            let symbol: String? = switch (bind.code, title, element.psActionButtonIcon) {
            case (_, _, .triangle?): "triangle"
            case (_, _, .circle?): "circle"
            case (_, _, .cross?): "xmark"
            case (_, _, .square?): "square"
            case (.start, "START", nil): GameOverlayComboTitle.startSymbol
            case (.select, "SELECT", nil): GameOverlayComboTitle.selectSymbol
            default: nil
            }
            let key = GameOverlayComboKey(bind: bind, title: title, symbol: symbol)
            if bind.code == .start || bind.code == .select {
                menuKeys.append(key)
            } else {
                keys.append(key)
            }
        }
        return keys + menuKeys
    }

    /// Resolve RetroPad inputs to visible native labels, preserving bind order.
    /// For example, Dreamcast binds [A, B] display [B, A], not the input names.
    func comboTitle(binds: [GamePageOverlayAction]) -> GameOverlayComboTitle {
        let keys = comboKeys
        return GameOverlayComboTitle(parts: binds.map { bind in
            keys.first { $0.bind == bind }?.titlePart ?? .text(bind.rawValue)
        })
    }

    /// Recommendations are creation templates only. Every runtime combo is
    /// defined by the user's data, including combos migrated from version 1.
    func withCombos(from layoutData: GameOverlayLayoutData?) -> Self {
        var result = elements.map { element -> GamePageOverlayElement in
            guard element.type == .button, element.isTurbo, element.binds.count == 1 else { return element }
            var meta = element.meta ?? [:]
            let title = comboTitle(binds: element.binds)
            meta["title"] = .string(title.plainText)
            meta["title_parts"] = title.jsonValue
            return GamePageOverlayElement(id: element.id, type: element.type, geometry: element.geometry, meta: meta)
        }
        let ids = Set(result.map(\.id))
        for combo in layoutData?.combos ?? [] where !ids.contains(combo.id) && !combo.binds.isEmpty {
            var meta: [String: JSONValue] = [:]
            meta["binds"] = .array(combo.binds.map { .string($0) })
            meta["is_turbo"] = .bool(combo.turbo)
            meta["title"] = nil
            result.append(resolvedCombo(GamePageOverlayElement(id: combo.id, type: .combo,
                                                               geometry: .comboPlaceholder, meta: meta)))
        }
        for macro in layoutData?.macros ?? [] where !macro.id.isEmpty && macro.isValid && !result.contains(where: { $0.id == macro.id }) {
            let title = macro.buttonTitle
            let meta: [String: JSONValue] = ["title": .string(macro.name), "macro_id": .string(macro.id), "title_parts": title.jsonValue,
                                           "title_font_scale": .double(1.4)]
            result.append(GamePageOverlayElement(id: macro.id, type: .macro, geometry: .combo(width: macro.direction == nil ? 50 : 68), meta: meta))
        }
        return GamePageOverlayConfig(
            platformId: platformId,
            version: version,
            portraitRefSize: portraitRefSize,
            landscapeRefSize: landscapeRefSize,
            portraitPolarAnchor: portraitPolarAnchor,
            landscapePolarAnchor: landscapePolarAnchor,
            recommendedCombo: recommendedCombo,
            elements: result
        )
    }

    /// A combo with its title from the native buttons and a size that fits it.
    private func resolvedCombo(_ element: GamePageOverlayElement) -> GamePageOverlayElement {
        var meta = element.meta ?? [:]
        let title = element.title.map { GameOverlayComboTitle(parts: [.text($0)]) } ?? comboTitle(binds: element.binds)
        meta["title"] = .string(title.plainText)
        meta["title_parts"] = title.jsonValue
        let geometry = element.geometry == .comboPlaceholder ? .combo(title: title) : element.geometry
        return GamePageOverlayElement(id: element.id, type: .combo, geometry: geometry, meta: meta)
    }
}

extension GameOverlayMacro {
    var buttonTitle: GameOverlayComboTitle {
        var parts: [GameOverlayComboTitle.Part] = [.symbol(resolvedSymbol, text: name)]
        if let direction {
            let marker = GameOverlayComboTitle.Part.symbol(direction.symbol, text: direction.marker)
            if direction == .left { parts.insert(marker, at: 0) } else { parts.append(marker) }
        }
        return GameOverlayComboTitle(parts: parts)
    }
}
