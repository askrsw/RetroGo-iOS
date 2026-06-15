//
//  UIColor+Extension.swift
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

extension UIColor {
    static let mainColor = UIColor.accent

    /// Brand color for the cheats feature — a warm amber-gold (金手指 = "golden
    /// finger"). Used for the cheat icon's filled background (toolbar layout
    /// editor + the cheat page titles). Distinct from the rest of the toolbar
    /// palette (blue/teal/cyan/gray/orange/red).
    static let cheatIconColor = UIColor(red: 0.78, green: 0.54, blue: 0.05, alpha: 1.0)

    static var isDarkMode: Bool {
        UIScreen.main.traitCollection.userInterfaceStyle == .dark
    }

    /// Return a copy of this color whose HSB brightness is at least
    /// `minBrightness`. Useful for keeping small UI elements (tags, chips,
    /// thin strokes) readable on dark backgrounds when the underlying
    /// brand/platform color happens to be very dark.
    ///
    /// Brightness in HSB is a better measure than luminance here because
    /// saturated colors (e.g. NES red) read as "bright" to the eye even
    /// when their relative luminance is low — only desaturated dark
    /// colors (PSP's near-black) need lifting.
    func ensuringMinimumBrightness(_ minBrightness: CGFloat) -> UIColor {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return self
        }
        if b >= minBrightness { return self }
        return UIColor(hue: h, saturation: s, brightness: minBrightness, alpha: a)
    }
}
