//
//  GameShaderFolder.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/24.
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

/// Presentation-only folders. Preset identities and dependency paths never change.
struct GameShaderFolder {
    let name: String
    let category: Bool
    let folders: [GameShaderFolder]
    let presets: [GameShaderPreset]
    let count: Int
    var packageID: String? = nil

    var title: String {
        guard category, Self.categories.contains(name) else { return name }
        return shaderText("category." + name)
    }

    private static let categories: Set<String> = [
        "bezel", "border", "crt", "scanlines", "handheld", "ntsc", "pal", "vhs", "presets",
        "edge-smoothing", "pixel-art-scaling", "interpolation", "downsample", "blurs", "dithering",
        "anti-aliasing", "sharpen", "deblur", "denoisers", "hdr", "motionblur", "motion-interpolation",
        "subframe-bfi", "stereoscopic-3d", "reshade", "film", "nes_raw_palette", "gpu", "cel",
        "anamorphic", "linear", "warp", "test", "misc"
    ]
    private static let first = ["bezel", "border", "crt", "scanlines", "handheld", "ntsc", "pal", "vhs", "presets"]

    static func packages(_ packages: [GameShaderCatalog.ImportPackage]) -> [GameShaderFolder] {
        packages.map { package in
            let tree = imported(package.presets)
            // Older imports have no display-name metadata; never expose a UUID as the title.
            let name = package.folderName ?? shaderText("imported_folder")
            return GameShaderFolder(name: name, category: false, folders: tree.folders, presets: tree.presets,
                                    count: tree.count, packageID: package.id)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func removing(_ preset: GameShaderPreset) -> GameShaderFolder {
        let children = folders.map { $0.removing(preset) }.filter { $0.count > 0 }
        let remaining = presets.filter { $0.id != preset.id }
        return GameShaderFolder(name: name, category: category, folders: children, presets: remaining,
                                count: remaining.count + children.reduce(0) { $0 + $1.count }, packageID: packageID)
    }

    static func imported(_ presets: [GameShaderPreset]) -> GameShaderFolder {
        final class Node {
            var children: [String: Node] = [:]
            var presets: [GameShaderPreset] = []
        }
        let root = Node()
        for preset in presets {
            var path = preset.path.split(separator: "/").map(String.init)
            // Imported packages have UUID roots, which are not useful browsing categories.
            if let first = path.first, UUID(uuidString: first) != nil { path.removeFirst() }
            if path.first == "shaders_slang" { path.removeFirst() }
            var node = root
            for name in path.dropLast() {
                let child = node.children[name] ?? Node()
                node.children[name] = child
                node = child
            }
            node.presets.append(preset)
        }
        func build(_ node: Node, name: String, depth: Int) -> GameShaderFolder {
            let children = node.children.map { build($0.value, name: $0.key, depth: depth + 1) }.sorted {
                if depth == 0 {
                    let a = first.firstIndex(of: $0.name) ?? first.count
                    let b = first.firstIndex(of: $1.name) ?? first.count
                    if a != b { return a < b }
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            let presets = node.presets.sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            }
            return GameShaderFolder(name: name, category: depth == 1, folders: children, presets: presets,
                                    count: presets.count + children.reduce(0) { $0 + $1.count })
        }
        return build(root, name: "", depth: 0)
    }
}
