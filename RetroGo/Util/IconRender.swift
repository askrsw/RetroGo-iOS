//
//  IconRender.swift
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

final class IconRender {
    static let shared = IconRender()
    private init() { }

    func dotImage(size: CGSize, color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, DeviceConfig.screenScale)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        context.setFillColor(color.cgColor)

        let radius = min(size.width, size.height) / 5
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
        context.fillPath()

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // MARK: - Platform Icons

    /// Logical key for a console/computer platform. Drives both the squircle
    /// background color and the silhouette drawn on top.
    ///
    /// Icons are entirely original abstract artwork — no console logos, no
    /// trademarked symbols (PS face buttons, Nintendo wordmarks, etc.).
    ///
    /// Callers are expected to resolve a key through explicit per-type
    /// mappings (see `EmuCoreInfoItem+Extension.swift` and
    /// `RAPlatformItem+Extension.swift`), not by guessing from a display
    /// name string.
    enum PlatformIconKey: String {
        case nes
        case fds
        case snes
        case n64
        case gb
        case gbc
        case gba
        case ds
        case md
        case sms
        case psx
        case psp
        case saturn
        case mame
        case dos
    }

    private let platformIconCache = NSCache<NSString, UIImage>()

    /// The accent color associated with a platform — same color used as
    /// the squircle background in `platformIcon(key:size:)`. Exposed so
    /// other UI elements (e.g. format-extension tags) can stay visually
    /// tied to the platform identity.
    func platformColor(for key: PlatformIconKey) -> UIColor {
        backgroundColor(for: key)
    }

    /// Display-safe variant of `platformColor(for:)`: identical for most
    /// platforms, but auto-lightened when the platform's true color is
    /// too dark to read against a dark `systemBackground`.
    ///
    /// Used for both the squircle icon background (`drawPlatformIcon`)
    /// and the format-extension chips in the core info page. The two
    /// share one rule so colors stay consistent across icon ↔ chip
    /// transitions in the UI.
    ///
    /// Example: PSP's true color is near-black `(0.18, 0.18, 0.20)`.
    /// Both the icon squircle AND the format chips use this lifted
    /// variant — without it, PSP rows visually dim out next to other
    /// brighter platforms in the same list.
    func platformTagColor(for key: PlatformIconKey) -> UIColor {
        backgroundColor(for: key).ensuringMinimumBrightness(Self.tagMinBrightness)
    }

    /// HSB brightness floor for `platformTagColor`. 0.45 was chosen
    /// empirically — it keeps PSP (originally V=0.20) clearly visible
    /// without changing any other platform color.
    private static let tagMinBrightness: CGFloat = 0.45

    /// Render a settings-row icon: an SF Symbol drawn in white on top of a
    /// colored squircle, matching the geometry of the platform icons (22%
    /// corner radius, ~50% inner glyph). This is the shared visual for
    /// AppSetting rows so they read as the same "icon family" as the core
    /// list cells.
    ///
    /// - Parameters:
    ///   - symbol: SF Symbol name, e.g. `"house.fill"`.
    ///   - background: squircle fill color (semantic; see
    ///     `12_ui_design_system.md` for the AppSetting color convention).
    ///   - size: total icon size (typically 30×30 in cells).
    func settingsIcon(symbol: String, background: UIColor, size: CGSize) -> UIImage {
        let bgHex = background.cgColor.components?
            .map { String(format: "%.2f", $0) }
            .joined(separator: ",") ?? "x"
        let keyString = "settings.\(symbol).\(bgHex).\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = platformIconCache.object(forKey: keyString) {
            return cached
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            drawSettingsIcon(symbol: symbol, background: background, in: rect)
        }.withRenderingMode(.alwaysOriginal)

        platformIconCache.setObject(image, forKey: keyString)
        return image
    }

    /// Render a platform icon at the given size. The result is `.alwaysOriginal`
    /// so `UIButton(type: .system)` won't tint it.
    func platformIcon(key: PlatformIconKey, size: CGSize) -> UIImage {
        let cacheKey = "platform.\(key.rawValue).\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = platformIconCache.object(forKey: cacheKey) {
            return cached
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererCtx in
            let ctx = rendererCtx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            drawPlatformIcon(key: key, in: rect, context: ctx)
        }.withRenderingMode(.alwaysOriginal)

        platformIconCache.setObject(image, forKey: cacheKey)
        return image
    }
}

// MARK: - Drawing

private extension IconRender {
    /// Foreground color used for the silhouette on top of every squircle.
    /// Kept slightly off-pure-white so it integrates with iOS Dark Mode
    /// without looking harsh.
    static let iconFG: UIColor = UIColor.white

    /// Inset of the silhouette inside the squircle, as a fraction of the
    /// icon's side length. 0.18 leaves a comfortable visual margin.
    static let contentInset: CGFloat = 0.18

    /// Shared squircle background helper — used by both platform icons
    /// and settings icons so the corner ratio (and the corner *shape*)
    /// stays in one place.
    ///
    /// Uses `continuousRoundedRectPath` rather than UIKit's simple
    /// `UIBezierPath(roundedRect:cornerRadius:)`, because the latter
    /// produces a circular arc that's visibly less smooth than the
    /// superellipse used by `CALayer.cornerCurve = .continuous` and by
    /// iOS home-screen icons. Matters most at the AppIcon's 80pt size,
    /// but applying it here keeps every squircle in the app consistent.
    func drawSquircleBackground(in rect: CGRect, color: UIColor) {
        let corner = rect.width * 0.22
        let path = Self.continuousRoundedRectPath(in: rect, cornerRadius: corner)
        color.setFill()
        path.fill()
    }

    /// Approximation of iOS's "continuous" rounded rectangle (the same
    /// shape produced by `CALayer.cornerCurve = .continuous`), expressed
    /// as a drawable `UIBezierPath`.
    ///
    /// Each corner uses a single cubic Bézier whose curve region extends
    /// `(1 + smoothing) * r` along both axes, with control points pulled
    /// in by `controlFactor * r` from the curve endpoints. The constants
    /// (smoothing = 0.6, controlFactor = 0.45) match Apple's iOS icon
    /// curvature to within a fraction of a pixel at the sizes we render
    /// at (28–80pt).
    ///
    /// Clamps `cornerRadius` so the corner curves never overlap, even
    /// for extreme values.
    static func continuousRoundedRectPath(
        in rect: CGRect,
        cornerRadius: CGFloat
    ) -> UIBezierPath {
        let smoothing: CGFloat = 0.6
        let cornerExtension = 1 + smoothing
        // Maximum radius before opposite corner curves would overlap.
        let maxR = min(rect.width, rect.height) / (2 * cornerExtension)
        let r = max(0, min(cornerRadius, maxR))
        let arc = r * cornerExtension
        let cp = r * cornerExtension * 0.45

        let path = UIBezierPath()
        let l = rect.minX
        let t = rect.minY
        let R = rect.maxX
        let b = rect.maxY

        path.move(to: CGPoint(x: l + arc, y: t))
        path.addLine(to: CGPoint(x: R - arc, y: t))
        path.addCurve(
            to: CGPoint(x: R, y: t + arc),
            controlPoint1: CGPoint(x: R - cp, y: t),
            controlPoint2: CGPoint(x: R, y: t + cp)
        )
        path.addLine(to: CGPoint(x: R, y: b - arc))
        path.addCurve(
            to: CGPoint(x: R - arc, y: b),
            controlPoint1: CGPoint(x: R, y: b - cp),
            controlPoint2: CGPoint(x: R - cp, y: b)
        )
        path.addLine(to: CGPoint(x: l + arc, y: b))
        path.addCurve(
            to: CGPoint(x: l, y: b - arc),
            controlPoint1: CGPoint(x: l + cp, y: b),
            controlPoint2: CGPoint(x: l, y: b - cp)
        )
        path.addLine(to: CGPoint(x: l, y: t + arc))
        path.addCurve(
            to: CGPoint(x: l + arc, y: t),
            controlPoint1: CGPoint(x: l, y: t + cp),
            controlPoint2: CGPoint(x: l + cp, y: t)
        )
        path.close()
        return path
    }

    func drawSettingsIcon(symbol: String, background: UIColor, in rect: CGRect) {
        drawSquircleBackground(in: rect, color: background)

        // SF Symbol drawn in white, centered. Pointsize at ~55% of the
        // squircle keeps the glyph readable without crowding the corners.
        let pointSize = rect.width * 0.55
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbolImage = UIImage(systemName: symbol, withConfiguration: config)?
            .withTintColor(Self.iconFG, renderingMode: .alwaysOriginal) else {
            return
        }

        // Letterbox-fit the symbol into 70% of the squircle so glyphs with
        // tall ascenders (e.g. clock) and wide glyphs (e.g. info.circle)
        // get similar optical weight.
        let maxSide = rect.width * 0.70
        let scale = min(maxSide / symbolImage.size.width,
                        maxSide / symbolImage.size.height)
        let drawSize = CGSize(
            width: symbolImage.size.width * scale,
            height: symbolImage.size.height * scale
        )
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        symbolImage.draw(in: drawRect)
    }

    func drawPlatformIcon(
        key: PlatformIconKey,
        in rect: CGRect,
        context: CGContext
    ) {
        // Use the brightness-lifted variant so platforms whose canonical
        // color is near-black (PSP) don't dim out against the dark
        // `systemBackground`. For every other platform this is a no-op —
        // their brightness already exceeds the floor.
        drawSquircleBackground(in: rect, color: platformTagColor(for: key))

        let inset = rect.width * Self.contentInset
        let inner = rect.insetBy(dx: inset, dy: inset)

        switch key {
        case .nes:    drawCartridgeNES(in: inner)
        case .fds:    drawFloppyDisk(in: inner)
        case .snes:   drawCartridgeSNES(in: inner)
        case .n64:    drawCartridgeN64(in: inner)
        case .gb:     drawHandheldGameBoy(in: inner)
        case .gbc:    drawHandheldGameBoy(in: inner)
        case .gba:    drawHandheldGBA(in: inner)
        case .ds:     drawDualScreen(in: inner)
        case .md:     drawCartridgeMD(in: inner)
        case .sms:    drawCartridgeMD(in: inner)
        case .psx:    drawDisc(in: inner, context: context)
        case .psp:    drawHandheldPSP(in: inner)
        case .saturn: drawDisc(in: inner, context: context)
        case .mame:   drawArcadeStick(in: inner)
        case .dos:    drawCRT(in: inner)
        }
    }

    func backgroundColor(for key: PlatformIconKey) -> UIColor {
        switch key {
        case .nes:    return UIColor(red: 0.78, green: 0.10, blue: 0.20, alpha: 1.0)
        case .fds:    return UIColor(red: 0.83, green: 0.59, blue: 0.04, alpha: 1.0)
        case .snes:   return UIColor(red: 0.35, green: 0.31, blue: 0.81, alpha: 1.0)
        case .n64:    return UIColor(red: 0.91, green: 0.29, blue: 0.15, alpha: 1.0)
        case .gb:     return UIColor(red: 0.48, green: 0.62, blue: 0.21, alpha: 1.0)
        case .gbc:    return UIColor(red: 0.63, green: 0.32, blue: 0.64, alpha: 1.0)
        case .gba:    return UIColor(red: 0.36, green: 0.37, blue: 0.84, alpha: 1.0)
        case .ds:     return UIColor(red: 0.36, green: 0.55, blue: 0.69, alpha: 1.0)
        case .md:     return UIColor(red: 0.11, green: 0.42, blue: 0.69, alpha: 1.0)
        case .sms:    return UIColor(red: 0.12, green: 0.40, blue: 0.50, alpha: 1.0)
        case .psx:    return UIColor(red: 0.23, green: 0.37, blue: 0.49, alpha: 1.0)
        case .psp:    return UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1.0)
        case .saturn: return UIColor(red: 0.06, green: 0.30, blue: 0.46, alpha: 1.0)
        case .mame:   return UIColor(red: 0.85, green: 0.22, blue: 0.27, alpha: 1.0)
        case .dos:    return UIColor(red: 0.55, green: 0.40, blue: 0.06, alpha: 1.0)
        }
    }
}

// MARK: - Individual shape drawers
//
// Conventions for every drawer:
//   * Input `rect` is the already-inset content area.
//   * Foreground fill is `iconFG` (white).
//   * Darker accents use black-with-alpha — this reads as a shadow on top of
//     any background color without needing per-platform tuning.

private extension IconRender {
    // MARK: Cartridges

    func drawCartridgeNES(in rect: CGRect) {
        Self.iconFG.setFill()

        let bodyH = rect.height * 0.78
        let bodyY = rect.midY - bodyH / 2
        let body = UIBezierPath(
            roundedRect: CGRect(x: rect.minX, y: bodyY,
                                width: rect.width, height: bodyH),
            cornerRadius: rect.width * 0.08
        )
        body.fill()

        // Upper label window — classic NES horizontal stripe.
        UIColor.black.withAlphaComponent(0.32).setFill()
        UIBezierPath(rect: CGRect(
            x: rect.minX + rect.width * 0.12,
            y: bodyY + bodyH * 0.20,
            width: rect.width * 0.76,
            height: bodyH * 0.18
        )).fill()

        // Connector slots — three small notches at bottom.
        let slotY = bodyY + bodyH * 0.78
        let slotH = bodyH * 0.12
        let slotW = rect.width * 0.10
        let gap   = rect.width * 0.06
        let totalW = slotW * 3 + gap * 2
        var x = rect.midX - totalW / 2
        for _ in 0..<3 {
            UIBezierPath(rect: CGRect(x: x, y: slotY, width: slotW, height: slotH)).fill()
            x += slotW + gap
        }
    }

    func drawCartridgeSNES(in rect: CGRect) {
        Self.iconFG.setFill()

        // Distinctive notched top shoulders.
        let w = rect.width
        let h = rect.height
        let notchW = w * 0.16
        let notchH = h * 0.18
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + notchW, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - notchW, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - notchW, y: rect.minY + notchH))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notchH))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + notchH))
        path.addLine(to: CGPoint(x: rect.minX + notchW, y: rect.minY + notchH))
        path.close()
        path.fill()

        // Center label.
        UIColor.black.withAlphaComponent(0.32).setFill()
        UIBezierPath(rect: CGRect(
            x: rect.minX + w * 0.18,
            y: rect.minY + h * 0.42,
            width: w * 0.64,
            height: h * 0.20
        )).fill()
    }

    func drawCartridgeN64(in rect: CGRect) {
        Self.iconFG.setFill()

        let body = UIBezierPath(
            roundedRect: rect.insetBy(dx: rect.width * 0.05, dy: 0),
            cornerRadius: rect.width * 0.08
        )
        body.fill()

        // Top finger-hold lip (N64 cart has a distinctive front "shelf").
        let lipW = rect.width * 0.55
        UIBezierPath(roundedRect: CGRect(
            x: rect.midX - lipW / 2,
            y: rect.minY,
            width: lipW,
            height: rect.height * 0.14
        ), cornerRadius: rect.width * 0.05).fill()

        // Label.
        UIColor.black.withAlphaComponent(0.32).setFill()
        UIBezierPath(rect: CGRect(
            x: rect.minX + rect.width * 0.20,
            y: rect.midY - rect.height * 0.10,
            width: rect.width * 0.60,
            height: rect.height * 0.22
        )).fill()
    }

    func drawCartridgeMD(in rect: CGRect) {
        Self.iconFG.setFill()

        UIBezierPath(
            roundedRect: rect.insetBy(dx: 0, dy: rect.height * 0.04),
            cornerRadius: rect.width * 0.10
        ).fill()

        // Horizontal label band.
        UIColor.black.withAlphaComponent(0.32).setFill()
        UIBezierPath(rect: CGRect(
            x: rect.minX + rect.width * 0.12,
            y: rect.midY - rect.height * 0.12,
            width: rect.width * 0.76,
            height: rect.height * 0.24
        )).fill()
    }

    func drawFloppyDisk(in rect: CGRect) {
        Self.iconFG.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.06).fill()

        // Metal shutter at the top.
        UIColor.black.withAlphaComponent(0.40).setFill()
        UIBezierPath(rect: CGRect(
            x: rect.minX + rect.width * 0.18,
            y: rect.minY + rect.height * 0.08,
            width: rect.width * 0.64,
            height: rect.height * 0.34
        )).fill()

        // Shutter notch.
        Self.iconFG.setFill()
        UIBezierPath(rect: CGRect(
            x: rect.midX - rect.width * 0.04,
            y: rect.minY + rect.height * 0.14,
            width: rect.width * 0.08,
            height: rect.height * 0.20
        )).fill()

        // Label area.
        UIColor.black.withAlphaComponent(0.22).setFill()
        UIBezierPath(rect: CGRect(
            x: rect.minX + rect.width * 0.16,
            y: rect.minY + rect.height * 0.54,
            width: rect.width * 0.68,
            height: rect.height * 0.30
        )).fill()
    }

    // MARK: Handhelds

    func drawHandheldGameBoy(in rect: CGRect) {
        Self.iconFG.setFill()

        let bodyW = rect.width * 0.70
        let bodyX = rect.midX - bodyW / 2
        UIBezierPath(roundedRect: CGRect(
            x: bodyX, y: rect.minY,
            width: bodyW, height: rect.height
        ), cornerRadius: bodyW * 0.18).fill()

        // Screen.
        let screenW = bodyW * 0.74
        let screenH = rect.height * 0.42
        UIColor.black.withAlphaComponent(0.45).setFill()
        UIBezierPath(roundedRect: CGRect(
            x: rect.midX - screenW / 2,
            y: rect.minY + rect.height * 0.08,
            width: screenW, height: screenH
        ), cornerRadius: 1.5).fill()

        // D-pad (cross) — two thin rects.
        let dpadL = bodyW * 0.20
        let dpadT = bodyW * 0.07
        let dpadCx = rect.midX - bodyW * 0.16
        let dpadCy = rect.minY + rect.height * 0.74
        UIBezierPath(rect: CGRect(
            x: dpadCx - dpadL / 2,
            y: dpadCy - dpadT / 2,
            width: dpadL, height: dpadT
        )).fill()
        UIBezierPath(rect: CGRect(
            x: dpadCx - dpadT / 2,
            y: dpadCy - dpadL / 2,
            width: dpadT, height: dpadL
        )).fill()

        // Two action buttons (dots).
        let btnR = bodyW * 0.06
        let btnCy = rect.minY + rect.height * 0.74
        let btn1X = rect.midX + bodyW * 0.10
        let btn2X = rect.midX + bodyW * 0.24
        UIBezierPath(ovalIn: CGRect(
            x: btn1X - btnR, y: btnCy - btnR,
            width: btnR * 2, height: btnR * 2
        )).fill()
        UIBezierPath(ovalIn: CGRect(
            x: btn2X - btnR, y: btnCy - btnR,
            width: btnR * 2, height: btnR * 2
        )).fill()
    }

    func drawHandheldGBA(in rect: CGRect) {
        Self.iconFG.setFill()

        let bodyH = rect.height * 0.62
        let bodyY = rect.midY - bodyH / 2
        UIBezierPath(roundedRect: CGRect(
            x: rect.minX, y: bodyY,
            width: rect.width, height: bodyH
        ), cornerRadius: bodyH * 0.34).fill()

        // Landscape screen.
        let screenW = rect.width * 0.48
        let screenH = bodyH * 0.66
        UIColor.black.withAlphaComponent(0.45).setFill()
        UIBezierPath(roundedRect: CGRect(
            x: rect.midX - screenW / 2,
            y: bodyY + (bodyH - screenH) / 2,
            width: screenW, height: screenH
        ), cornerRadius: 1.5).fill()

        // D-pad (left side, small cross).
        Self.iconFG.setFill()
        let dpadL = rect.width * 0.10
        let dpadT = rect.width * 0.035
        let dpadCx = rect.minX + rect.width * 0.16
        let dpadCy = rect.midY
        UIBezierPath(rect: CGRect(
            x: dpadCx - dpadL / 2, y: dpadCy - dpadT / 2,
            width: dpadL, height: dpadT
        )).fill()
        UIBezierPath(rect: CGRect(
            x: dpadCx - dpadT / 2, y: dpadCy - dpadL / 2,
            width: dpadT, height: dpadL
        )).fill()

        // Two action buttons (right side).
        let btnR = rect.width * 0.035
        let btnCy = rect.midY
        let btn1 = CGPoint(x: rect.maxX - rect.width * 0.20, y: btnCy)
        let btn2 = CGPoint(x: rect.maxX - rect.width * 0.10, y: btnCy)
        UIBezierPath(ovalIn: CGRect(
            x: btn1.x - btnR, y: btn1.y - btnR,
            width: btnR * 2, height: btnR * 2
        )).fill()
        UIBezierPath(ovalIn: CGRect(
            x: btn2.x - btnR, y: btn2.y - btnR,
            width: btnR * 2, height: btnR * 2
        )).fill()
    }

    func drawHandheldPSP(in rect: CGRect) {
        Self.iconFG.setFill()

        let bodyH = rect.height * 0.56
        let bodyY = rect.midY - bodyH / 2
        UIBezierPath(roundedRect: CGRect(
            x: rect.minX, y: bodyY,
            width: rect.width, height: bodyH
        ), cornerRadius: bodyH * 0.30).fill()

        // Center screen, dominant.
        let screenW = rect.width * 0.52
        let screenH = bodyH * 0.72
        UIColor.black.withAlphaComponent(0.45).setFill()
        UIBezierPath(roundedRect: CGRect(
            x: rect.midX - screenW / 2,
            y: bodyY + (bodyH - screenH) / 2,
            width: screenW, height: screenH
        ), cornerRadius: 1.5).fill()
    }

    func drawDualScreen(in rect: CGRect) {
        Self.iconFG.setFill()

        let gap = rect.height * 0.08
        let halfH = (rect.height - gap) / 2

        let topRect = CGRect(x: rect.minX, y: rect.minY,
                             width: rect.width, height: halfH)
        let botRect = CGRect(x: rect.minX, y: rect.maxY - halfH,
                             width: rect.width, height: halfH)
        UIBezierPath(roundedRect: topRect, cornerRadius: rect.width * 0.10).fill()
        UIBezierPath(roundedRect: botRect, cornerRadius: rect.width * 0.10).fill()

        // Inset screens.
        UIColor.black.withAlphaComponent(0.45).setFill()
        let pad = rect.width * 0.12
        UIBezierPath(roundedRect:
            topRect.insetBy(dx: pad, dy: pad * 0.7),
            cornerRadius: 1.5).fill()
        UIBezierPath(roundedRect:
            botRect.insetBy(dx: pad, dy: pad * 0.7),
            cornerRadius: 1.5).fill()
    }

    // MARK: Discs

    func drawDisc(in rect: CGRect, context: CGContext) {
        let diameter = min(rect.width, rect.height)
        let disc = CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter, height: diameter
        )

        Self.iconFG.setFill()
        UIBezierPath(ovalIn: disc).fill()

        // Inner reflection ring (subtle).
        UIColor.black.withAlphaComponent(0.16).setStroke()
        let ring = UIBezierPath(ovalIn: disc.insetBy(
            dx: diameter * 0.18, dy: diameter * 0.18
        ))
        ring.lineWidth = max(1, diameter * 0.03)
        ring.stroke()

        // Punch out the spindle hole using .clear so the squircle BG shows.
        context.saveGState()
        context.setBlendMode(.clear)
        let holeD = diameter * 0.22
        UIBezierPath(ovalIn: CGRect(
            x: rect.midX - holeD / 2,
            y: rect.midY - holeD / 2,
            width: holeD, height: holeD
        )).fill()
        context.restoreGState()
    }

    // MARK: Arcade & CRT

    func drawArcadeStick(in rect: CGRect) {
        Self.iconFG.setFill()

        // Joystick ball — left.
        let ballR = rect.width * 0.20
        let ballC = CGPoint(x: rect.minX + rect.width * 0.30, y: rect.midY)
        UIBezierPath(ovalIn: CGRect(
            x: ballC.x - ballR, y: ballC.y - ballR,
            width: ballR * 2, height: ballR * 2
        )).fill()

        // Two action buttons — right, slightly offset.
        let btnR = rect.width * 0.14
        let btnA = CGPoint(x: rect.minX + rect.width * 0.70,
                           y: rect.minY + rect.height * 0.36)
        let btnB = CGPoint(x: rect.minX + rect.width * 0.78,
                           y: rect.minY + rect.height * 0.66)
        UIBezierPath(ovalIn: CGRect(
            x: btnA.x - btnR, y: btnA.y - btnR,
            width: btnR * 2, height: btnR * 2
        )).fill()
        UIBezierPath(ovalIn: CGRect(
            x: btnB.x - btnR, y: btnB.y - btnR,
            width: btnR * 2, height: btnR * 2
        )).fill()
    }

    func drawCRT(in rect: CGRect) {
        Self.iconFG.setFill()

        let bodyH = rect.height * 0.80
        UIBezierPath(roundedRect: CGRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: bodyH
        ), cornerRadius: rect.width * 0.10).fill()

        // Inset screen.
        UIColor.black.withAlphaComponent(0.55).setFill()
        UIBezierPath(roundedRect: CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.minY + bodyH * 0.14,
            width: rect.width * 0.80,
            height: bodyH * 0.68
        ), cornerRadius: 1.5).fill()

        // Two prompt-style lines (suggest text).
        Self.iconFG.setFill()
        let lineH = bodyH * 0.07
        UIBezierPath(rect: CGRect(
            x: rect.minX + rect.width * 0.18,
            y: rect.minY + bodyH * 0.32,
            width: rect.width * 0.32,
            height: lineH
        )).fill()
        UIBezierPath(rect: CGRect(
            x: rect.minX + rect.width * 0.18,
            y: rect.minY + bodyH * 0.52,
            width: rect.width * 0.46,
            height: lineH
        )).fill()

        // Stand — trapezoid.
        let standTopW = rect.width * 0.38
        let standBotW = rect.width * 0.62
        let standY = rect.minY + bodyH
        let stand = UIBezierPath()
        stand.move(to: CGPoint(x: rect.midX - standTopW / 2, y: standY))
        stand.addLine(to: CGPoint(x: rect.midX + standTopW / 2, y: standY))
        stand.addLine(to: CGPoint(x: rect.midX + standBotW / 2, y: rect.maxY))
        stand.addLine(to: CGPoint(x: rect.midX - standBotW / 2, y: rect.maxY))
        stand.close()
        stand.fill()
    }
}
