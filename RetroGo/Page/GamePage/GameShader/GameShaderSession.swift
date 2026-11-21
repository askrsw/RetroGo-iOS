//
//  GameShaderSession.swift
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

import UIKit
import RACoordinator

@MainActor
final class GameShaderSession {
    let settings: GameConfigSession
    private(set) var draft: GameShaderSelection?
    private(set) var definitions: [GameShaderParameter] = []
    private let runtimeID: UUID?
    private let originalRuntime: GameShaderSelection
    private var finished = false
    private var preparation = UUID()
    private var lease: GamePauseCoordinator.Lease?

    var isLive: Bool {
        runtimeID != nil && GameShaderRuntime.shared.sessionID == runtimeID
            && GameShaderRuntime.shared.contains(settings)
    }
    var selected: GameShaderSelection {
        get throws { try GameShaderStore.resolved(settings, replacing: .some(draft)) }
    }
    var title: String { (try? selected.preset?.title) ?? shaderText("off") }

    init(settings: GameConfigSession) throws {
        self.settings = settings
        draft = try GameShaderStore.own(settings)
        let runtime = GameShaderRuntime.shared
        runtimeID = runtime.contains(settings) ? runtime.sessionID : nil
        originalRuntime = runtime.applied
        if isLive { lease = GamePauseCoordinator.shared.acquire(reason: "shader-editor") }
    }

    deinit { lease?.release() }

    func choosePrepared(_ selection: GameShaderSelection?) async throws {
        try Task.checkCancellation()
        let generation = UUID()
        preparation = generation
        let resolved = try GameShaderStore.resolved(settings, replacing: .some(selection))
        let parameters: [GameShaderParameter]
        if let preset = resolved.preset {
            parameters = try await GameShaderCompiler.shared.prepare(preset, compile: isLive && GameShaderRuntime.shared.supportsSlang)
        } else { parameters = [] }
        try Task.checkCancellation()
        guard generation == preparation, !finished, runtimeID == nil || isLive else { throw CancellationError() }
        if isLive { try GameShaderRuntime.shared.preview(selection, settings: settings, preparedDefinitions: parameters) }
        draft = selection
        definitions = parameters
    }

    func value(for parameter: GameShaderParameter) -> Double {
        parameter.normalized((try? selected.preset?.parameters[parameter.id]) ?? parameter.initial)
    }

    func setValue(_ value: Double, parameter: GameShaderParameter) throws {
        var selection = try selected
        guard selection.preset != nil else { return }
        selection.preset?.parameters[parameter.id] = parameter.normalized(value)
        // Editing inherited parameters creates a complete override in this scope.
        let previous = draft
        draft = selection
        do {
            if isLive { try GameShaderRuntime.shared.preview(draft, settings: settings) }
        } catch { draft = previous; throw error }
    }

    func resetParameters() throws {
        var selection = try selected
        selection.preset?.parameters = [:]
        preparation = UUID()
        let old = draft
        draft = selection
        do {
            if isLive { try GameShaderRuntime.shared.preview(draft, settings: settings, preparedDefinitions: definitions) }
        } catch { draft = old; throw error }
    }

    func commit() throws {
        preparation = UUID()
        // Write only after a successful preview; persistence failure leaves the draft open.
        if isLive { try GameShaderRuntime.shared.preview(draft, settings: settings) }
        try GameShaderStore.save(draft, settings: settings)
        finished = true
        lease?.release()
        lease = nil
    }

    func importsDidChange() throws {
        preparation = UUID()
        if GameShaderStore.available(draft) != draft {
            draft = nil
            definitions = []
        }
        let runtime = GameShaderRuntime.shared
        if isLive, GameShaderStore.available(runtime.applied) == nil {
            try runtime.preview(draft, settings: settings)
        }
    }

    func cancel() throws {
        preparation = UUID()
        guard !finished else { return }
        let runtime = GameShaderRuntime.shared
        if isLive {
            if GameShaderStore.available(originalRuntime) != nil {
                try runtime.apply(originalRuntime)
            } else if let currentSettings = runtime.settings {
                try runtime.apply(GameShaderStore.resolved(currentSettings))
            }
        }
        finished = true
        lease?.release()
        lease = nil
    }
}
