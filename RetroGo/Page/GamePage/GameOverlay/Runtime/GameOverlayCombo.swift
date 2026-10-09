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

    /// The name is the PlayStation glyph itself, so the symbol alone says it.
    var symbolReplacesTitle: Bool {
        symbol != nil && title.count == 1
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
        parts.reduce(Double(max(parts.count - 1, 0)) * Self.gap) { total, part in
            switch part {
            case .text(let text): return total + Double(text.count)
            case .symbol: return total + 1.6
            }
        }
    }

    /// Space between buttons in the side-by-side form, in letter widths.
    static let gap = 0.35

    /// The title for labels and buttons; the symbols take the text color.
    /// `joined` puts "+" between the buttons; otherwise they sit side by side.
    /// Size of a symbol drawn among letters, from its trimmed image: a little taller than
    /// their capitals (shapes read smaller than letters of the same height), and no wider
    /// than 1.6 of that, so wide symbols like the menu lines stay in step with the letters.
    static func symbolSize(_ natural: CGSize, capHeight: CGFloat) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return .zero }
        let scale = min(capHeight * 1.08 / natural.height, capHeight * 1.6 / natural.width)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    private static let symbolCache = NSCache<NSString, UIImage>()

    /// A symbol drawn white and cropped to its ink. SF Symbol images carry padding around
    /// the shape, more for round shapes, so sizing the uncropped image left them smaller
    /// than the letters. Medium weight matches the labels' strokes. Template, so text
    /// attachments take the text color; SpriteKit tints the white.
    static func symbolImage(_ name: String) -> UIImage? {
        if let cached = symbolCache.object(forKey: name as NSString) { return cached }
        let configuration = UIImage.SymbolConfiguration(pointSize: 60, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let rendered = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        guard let cgImage = rendered.cgImage, let ink = inkBounds(cgImage),
              let cropped = cgImage.cropping(to: ink) else { return nil }
        let image = UIImage(cgImage: cropped, scale: format.scale, orientation: .up).withRenderingMode(.alwaysTemplate)
        symbolCache.setObject(image, forKey: name as NSString)
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

    func attributedString(font: UIFont, joined: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                if joined {
                    result.append(NSAttributedString(string: "+"))
                } else {
                    // A kerned space keeps the gap the same whatever the font's space width is.
                    result.append(NSAttributedString(string: " ", attributes: [.kern: font.pointSize * (Self.gap - 0.25)]))
                }
            }
            switch part {
            case .text(let text):
                result.append(NSAttributedString(string: text))
            case .symbol(let name, let text):
                if let image = Self.symbolImage(name) {
                    let attachment = NSTextAttachment(image: image)
                    let size = Self.symbolSize(image.size, capHeight: font.capHeight)
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

    /// "A+B": the buttons a combo presses, named as the overlay shows them.
    func comboTitle(binds: [GamePageOverlayAction]) -> GameOverlayComboTitle {
        let keys = comboKeys
        return GameOverlayComboTitle(parts: binds.map { bind in
            keys.first { $0.bind == bind }?.titlePart ?? .text(bind.rawValue)
        })
    }

    /// The config with the built-in combos titled and sized, and the user's
    /// combos from `layoutData` added after the JSON elements.
    func withCombos(from layoutData: GameOverlayLayoutData?) -> Self {
        let turboOverrides = layoutData?.presetComboTurbo ?? [:]
        var result = elements.map { element -> GamePageOverlayElement in
            guard element.type == .combo else { return element }
            guard let turbo = turboOverrides[element.id] else { return resolvedCombo(element) }
            var meta = element.meta ?? [:]
            meta["is_turbo"] = .bool(turbo)
            return resolvedCombo(GamePageOverlayElement(id: element.id, type: .combo, geometry: element.geometry, meta: meta))
        }
        let ids = Set(result.map(\.id))
        for combo in layoutData?.combos ?? [] where !ids.contains(combo.id) && !combo.binds.isEmpty {
            let meta: [String: JSONValue] = [
                "binds": .array(combo.binds.map { .string($0) }),
                "is_turbo": .bool(combo.turbo)
            ]
            result.append(resolvedCombo(GamePageOverlayElement(id: combo.id, type: .combo,
                                                               geometry: .comboPlaceholder, meta: meta)))
        }
        return GamePageOverlayConfig(
            platformId: platformId,
            version: version,
            portraitRefSize: portraitRefSize,
            landscapeRefSize: landscapeRefSize,
            portraitPolarAnchor: portraitPolarAnchor,
            landscapePolarAnchor: landscapePolarAnchor,
            fourButtonPortraitPolarAnchor: fourButtonPortraitPolarAnchor,
            fourButtonLandscapePolarAnchor: fourButtonLandscapePolarAnchor,
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
