//
//  GameShaderPreset.swift
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
import ObjcHelper

func shaderText(_ key: String) -> String { Bundle.localizedString(forKey: "shader_" + key) }

struct GameShaderPreset: Codable, Equatable {
    let id: String
    var name: String
    /// Bundle-relative or imports-relative, never an absolute sandbox path.
    let path: String
    let imported: Bool
    var parameters: [String: Double]

    var title: String { id.hasPrefix("builtin.") ? shaderText(id) : name }
    var isLibrary: Bool { !imported && id.hasPrefix("library.") }
}

/// nil selection means inherit; an explicit selection with no preset means off.
struct GameShaderSelection: Codable, Equatable {
    var preset: GameShaderPreset?
    static let off = GameShaderSelection(preset: nil)
}

enum GameShaderError: LocalizedError {
    case resource, incompatible, prepare, apply, restore, storage, unsafeImport
    var errorDescription: String? {
        switch self {
        case .resource: return shaderText("error_resource")
        case .incompatible: return shaderText("error_driver")
        case .prepare: return shaderText("error_prepare")
        case .apply: return shaderText("error_apply")
        case .restore: return shaderText("error_restore")
        case .storage: return shaderText("error_storage")
        case .unsafeImport: return shaderText("error_import")
        }
    }
}
