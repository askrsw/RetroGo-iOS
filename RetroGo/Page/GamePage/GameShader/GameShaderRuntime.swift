//
//  GameShaderRuntime.swift
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
import RACoordinator
import os

/// Renderer ownership is bounded by the game's pause session identity.
@MainActor
final class GameShaderRuntime {
    static let shared = GameShaderRuntime()
    private(set) var sessionID: UUID?
    private(set) var settings: GameConfigSession?
    private(set) var applied: GameShaderSelection = .off
    private(set) var launchError: Error?
    private var parameterCache: (id: String, path: String, imported: Bool, definitions: [GameShaderParameter])?

    var driver: String { sessionID == nil ? "" : RetroArchX.shared().shaderVideoDriver() }
    var supportsSlang: Bool { ["vulkan", "metal"].contains(driver.lowercased()) }

    func begin(settings: GameConfigSession, id: UUID) {
        self.sessionID = id
        self.settings = settings
        applied = .off
        launchError = nil
        parameterCache = nil
        do { try apply(GameShaderStore.resolved(settings), force: true) }
        catch {
            launchError = error
            RetroGoLogger.game.error("Failed to apply launch shader: \(String(describing: error))")
        }
    }

    func end(id: UUID) {
        guard sessionID == id else { return }
        sessionID = nil
        settings = nil
        applied = .off
        launchError = nil
        parameterCache = nil
    }

    func contains(_ target: GameConfigSession) -> Bool {
        guard sessionID != nil, let settings else { return false }
        switch target.scope {
        case .global: return true
        case .core: return settings.core?.coreId == target.core?.coreId
        case .game: return settings.game?.key == target.game?.key
        }
    }

    func preview(_ draft: GameShaderSelection?, settings target: GameConfigSession, preparedDefinitions: [GameShaderParameter]? = nil) throws {
        guard contains(target), let settings else { return }
        // Keep Slang preferences when the current GL game cannot preview them.
        // A newly selected compatible video driver only starts on the next launch.
        guard supportsSlang else { return }
        try apply(GameShaderStore.resolved(settings, replacing: .some(draft), at: target), preparedDefinitions: preparedDefinitions)
    }

    func apply(_ selection: GameShaderSelection, force: Bool = false, preparedDefinitions: [GameShaderParameter]? = nil) throws {
        guard sessionID != nil else { return }
        if selection == applied, !force { return }
        guard supportsSlang else {
            if selection.preset != nil { throw GameShaderError.incompatible }
            applied = .off
            return
        }
        let previous = applied
        let previousDefinitions = parameterCache?.definitions
        do {
            if !force, let old = applied.preset, let preset = selection.preset,
               old.id == preset.id, old.path == preset.path, old.imported == preset.imported {
                let definitions = try definitions(for: preset)
                for parameter in definitions {
                    let value = parameter.normalized(preset.parameters[parameter.id] ?? parameter.initial)
                    let oldValue = parameter.normalized(old.parameters[parameter.id] ?? parameter.initial)
                    if value != oldValue, !RetroArchX.shared().setShaderValue(value, parameter: parameter.id) {
                        throw GameShaderError.apply
                    }
                }
            } else {
                try load(selection, preparedDefinitions: preparedDefinitions)
            }
            applied = selection
            launchError = nil
        } catch {
            // Drivers release the previous pipeline before compiling a replacement.
            // A failed load must therefore explicitly rebuild the old pipeline.
            do { try load(previous, preparedDefinitions: previousDefinitions) }
            catch {
                _ = RetroArchX.shared().applyShader(path: nil, values: [:])
                applied = .off
                RetroGoLogger.game.error("Failed to restore shader after apply failure: \(String(describing: error))")
                throw GameShaderError.restore
            }
            throw error
        }
    }

    private func load(_ selection: GameShaderSelection, preparedDefinitions: [GameShaderParameter]? = nil) throws {
        parameterCache = nil
        // Read definitions when loading, never on the first drag of the newly selected shader.
        let definitions: [GameShaderParameter]?
        if let preparedDefinitions { definitions = preparedDefinitions }
        else { definitions = try selection.preset.map { try GameShaderCatalog.parameters(for: $0) } }
        let path = try selection.preset.map { try GameShaderCatalog.url(for: $0).path }
        let values = selection.preset?.parameters.mapValues { NSNumber(value: $0) } ?? [:]
        let start = ProcessInfo.processInfo.systemUptime
        let applied = RetroArchX.shared().applyShader(path: path, values: values)
        RetroGoLogger.game.debug("Shader render-thread apply completed in \((ProcessInfo.processInfo.systemUptime - start) * 1000, privacy: .public) ms")
        guard applied else { throw GameShaderError.apply }
        if let preset = selection.preset, let definitions {
            parameterCache = (preset.id, preset.path, preset.imported, definitions)
        }
    }

    private func definitions(for preset: GameShaderPreset) throws -> [GameShaderParameter] {
        if let cache = parameterCache, cache.id == preset.id, cache.path == preset.path, cache.imported == preset.imported {
            return cache.definitions
        }
        let definitions = try GameShaderCatalog.parameters(for: preset)
        parameterCache = (preset.id, preset.path, preset.imported, definitions)
        return definitions
    }
}
