//
//  GameShaderParameter.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/19.
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

struct GameShaderParameter {
    let id: String
    let title: String
    let initial: Double
    let minimum: Double
    let maximum: Double
    let step: Double

    func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return initial }
        let value = min(maximum, max(minimum, value))
        guard step > 0 else { return value }
        return min(maximum, max(minimum, minimum + ((value - minimum) / step).rounded() * step))
    }

    var valueFormat: String { step >= 1 ? "%.0f" : step >= 0.1 ? "%.1f" : step >= 0.01 ? "%.2f" : "%.3f" }
}

extension GameShaderParameter {
    /// Imported presets always keep their own parameter names, even if IDs happen to match.
    func displayTitle(for preset: GameShaderPreset?) -> String {
        guard let preset, !preset.imported,
              Self.localizedParameters[preset.path]?.contains(id) == true else { return title }
        let key = "parameter." + id
        let localized = shaderText(key)
        return localized == "shader_" + key || localized == key ? title : localized
    }

    private static let localizedParameters: [String: Set<String>] = [
        "scanlines/scanline.slangp": ["SCANLINE_SINE_COMP_A", "SCANLINE_SINE_COMP_B"],
        "crt/zfast-crt.slangp": ["BLURSCALEX", "LOWLUMSCAN", "HILUMSCAN", "BRIGHTBOOST", "MASK_DARK", "MASK_FADE"],
        "crt/crt-easymode.slangp": ["SHARPNESS_H", "SHARPNESS_V", "MASK_STRENGTH", "MASK_DOT_WIDTH", "MASK_DOT_HEIGHT", "MASK_STAGGER", "MASK_SIZE", "SCANLINE_STRENGTH", "SCANLINE_BEAM_WIDTH_MIN", "SCANLINE_BEAM_WIDTH_MAX", "SCANLINE_BRIGHT_MIN", "SCANLINE_BRIGHT_MAX", "SCANLINE_CUTOFF", "GAMMA_INPUT", "GAMMA_OUTPUT", "BRIGHT_BOOST", "DILATION"],
        "crt/crt-geom.slangp": ["CRTgamma", "monitorgamma", "d", "CURVATURE", "invert_aspect", "R", "cornersize", "cornersmooth", "x_tilt", "y_tilt", "overscan_x", "overscan_y", "mask_type", "DOTMASK", "DOTMASK_brightboost", "SHARPER", "scanline_weight", "vertical_scanlines", "lum", "interlace_detect", "xsize", "ysize"],
        "handheld/lcd-grid-v2.slangp": ["RSUBPIX_R", "RSUBPIX_G", "RSUBPIX_B", "GSUBPIX_R", "GSUBPIX_G", "GSUBPIX_B", "BSUBPIX_R", "BSUBPIX_G", "BSUBPIX_B", "gain", "gamma", "blacklevel", "ambient", "BGR"],
        "edge-smoothing/xbrz/xbrz-freescale.slangp": ["blend_none", "blend_normal", "blend_dominant"],
        "sharpen/rca_sharpen.slangp": ["RCAS_STRENGTH", "RCAS_DENOISE"],
        "edge-smoothing/fsr/retrogo-fsr.slangp": ["FSR_SHARPENING", "FSR_FILMGRAIN", "FSR_GRAINCOLOR", "FSR_GRAINPDF"],
        "handheld/gameboy.slangp": ["color_toggle", "baseline_alpha", "grey_balance", "response_time", "video_scale", "blending_mode", "adjacent_texel_alpha_blending", "contrast", "screen_light", "pixel_opacity", "bg_smoothing", "shadow_opacity", "shadow_offset_x", "shadow_offset_y", "screen_offset_x", "screen_offset_y"],
    ]
}
