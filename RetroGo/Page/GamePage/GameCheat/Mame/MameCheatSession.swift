//
//  MameCheatSession.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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

import SQLite
import Foundation
import RACoordinator

/// Cheats of one MAME game run, executed by MAME's own cheat engine.
///
/// The XML was written before launch (`MameCheatLibrary.prepareSession`); MAME loads it
/// when the machine starts, with every entry off. Like standalone MAME, cheats also stay off
/// until the player turns them on: most write memory every frame, and doing that from the
/// first frame breaks boot self-tests (NeoGeo stops at "WORK RAM ERROR" when a weapon cheat
/// writes into the RAM it is testing). MAME has no "boot finished" signal, and even a loaded
/// auto-save may have been taken during the self-test, so cheats that were on last time are
/// never switched on by themselves: the toolbar shows a restore dot and the player restores
/// them from the list once the game runs. A reset reboots the machine, so it turns the
/// cheats off and offers them for restore again.
/// Once the engine reports its entries, each index is checked against the XML description
/// (an entry the engine rejects is skipped, which would shift the ones after it). Changes
/// made while the game is paused are queued in the core and take effect on the next frame.
final class MameCheatSession {
    struct Entry {
        let definition: MameCheatDefinition
        var enabled: Bool
        /// 0-based parameter position; -1 when not chosen or not a parameter.
        var position: Int
        /// False when the engine has no matching entry at this index.
        var available: Bool

        var index: Int { definition.index }
        var kind: RAMameCheatKind { definition.kind }
    }

    let game: RetroRomFileItem
    let core: EmuCoreInfoItem
    /// Name of the cheat file in use (the set's own or its parent's); nil without cheats.
    let fileName: String?
    private(set) var entries: [Entry]

    private var engine: RAMameCheatEngine?
    private var pollTimer: Timer?
    private var pollAttempts = 0

    /// Netplay is lockstep-deterministic and cannot sync cheats: while a session runs every
    /// cheat is off in memory and in the engine. SQLite keeps the user's choices, and the
    /// ones that were on come back when the session ends.
    private var netplaySuspended = false
    private var suspendedIndices: Set<Int> = []
    /// Cheats that were on last time (or before a reset) and are waiting to be restored.
    private var restorableIndices: [Int] = []

    /// Runtime paths may run outside the purchase UI flow, so use the cached
    /// entitlement snapshot here. The UI gate still presents the paywall.
    private static var canEnableCheats: Bool {
        AppStorePurchaseManager.hasLocallyValidCachedProEntitlement
    }

    init(game: RetroRomFileItem, core: EmuCoreInfoItem) {
        self.game = game
        self.core = core

        let file = MameCheatLibrary.shared.takeSessionFile(romKey: game.key)
        let definitions = file.flatMap { MameCheatDefinition.parse($0.xml) } ?? []
        fileName = definitions.isEmpty ? nil : file?.fileName

        if !Self.canEnableCheats {
            Self.deleteEnabledStates(romKey: game.key)
        }
        let states = Self.loadStates(romKey: game.key)
        entries = definitions.map { definition in
            var entry = Entry(definition: definition, enabled: false, position: -1, available: true)
            if let state = states[definition.index], state.desc == definition.desc {
                entry.position = state.position
            }
            return entry
        }
        restorableIndices = entries.compactMap { entry in
            guard let state = states[entry.index], state.enabled, state.desc == entry.definition.desc else { return nil }
            switch entry.kind {
            case .onOff: return entry.index
            case .parameter: return entry.position >= 0 ? entry.index : nil
            default: return nil
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(netplayStateDidChange),
                                               name: .netplayStateChanged, object: nil)
        if RANetplayCoordinator.shared.isNetplayEnabled {
            suspendForNetplay()
        }
    }

    deinit {
        pollTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - State

    /// Whether the library has cheats for this game at all.
    var hasCheatFile: Bool { fileName != nil }

    /// Entries that can be switched or run (not headings/notes).
    var usableCount: Int { entries.filter { $0.kind != .text }.count }

    var hasActiveCheat: Bool {
        entries.contains { $0.enabled && ($0.kind == .onOff || $0.kind == .parameter) }
    }

    // MARK: - Engine

    /// Cheats from last time that the list can offer to restore; 0 until the machine runs.
    var restorableCount: Int {
        guard engine != nil, Self.canEnableCheats, !netplaySuspended else { return 0 }
        return restorableIndices.filter { index in entries.contains { $0.index == index && !$0.enabled && $0.available } }.count
    }

    /// Call once the core started (after the auto-save state was loaded). Waits for the
    /// machine to run, then checks the engine's entries against the XML.
    func gameDidStart() {
        guard hasCheatFile else { return }
        pollTimer?.invalidate()
        pollAttempts = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.pollAttempts += 1
            if self.attachEngine() || self.pollAttempts >= 240 {
                timer.invalidate()
                self.pollTimer = nil
            }
        }
    }

    private func attachEngine() -> Bool {
        guard let engine = RAMameCheatEngine.forLoadedCore(), engine.count >= 0 else { return false }
        let running = engine.entries()
        if running.count != entries.count {
            NSLog("[MameCheat] Engine has %d entries, %@.xml has %d", running.count, fileName ?? "-", entries.count)
        }
        for index in entries.indices {
            let desc = index < running.count ? running[index].desc.trimmingCharacters(in: .whitespaces) : nil
            entries[index].available = desc == entries[index].definition.desc
            if !entries[index].available {
                NSLog("[MameCheat] Entry %d (%@) does not match the engine; disabled", index, entries[index].definition.desc)
            }
        }
        self.engine = engine
        for entry in entries where entry.enabled && entry.available {
            push(entry)
        }
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
        return true
    }

    /// Switches on the cheats that were on last time (or before a reset).
    @discardableResult
    func restoreLastCheats() -> Int {
        guard canChange(enabling: true) else { return 0 }
        var restored = 0
        for index in restorableIndices {
            guard let i = entries.firstIndex(where: { $0.index == index }), !entries[i].enabled, entries[i].available else { continue }
            entries[i].enabled = true
            if Self.upsertState(romKey: game.key, entry: entries[i]) {
                push(entries[i])
                restored += 1
            }
        }
        restorableIndices = []
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
        return restored
    }

    /// Call right before the core resets: the machine boots again, so every cheat goes off
    /// (the queued requests run before the first frame after the reset) and is offered for
    /// restore. Saved choices stay as they are.
    func prepareForReset() {
        let active = entries.filter { $0.enabled && ($0.kind == .onOff || $0.kind == .parameter) }.map(\.index)
        guard !active.isEmpty else { return }
        for i in entries.indices where active.contains(entries[i].index) {
            entries[i].enabled = false
            push(entries[i])
        }
        restorableIndices = Array(Set(restorableIndices).union(active)).sorted()
        NSLog("[MameCheat] Reset; %d cheats turned off until restored", active.count)
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
    }

    // MARK: - Netplay

    @objc private func netplayStateDidChange() {
        if RANetplayCoordinator.shared.isNetplayEnabled {
            suspendForNetplay()
        } else {
            restoreAfterNetplay()
        }
    }

    private func suspendForNetplay() {
        guard !netplaySuspended else { return }
        netplaySuspended = true
        for i in entries.indices where entries[i].enabled {
            suspendedIndices.insert(entries[i].index)
            entries[i].enabled = false
            push(entries[i])
        }
        if !suspendedIndices.isEmpty {
            NSLog("[MameCheat] Netplay started; %d cheats turned off for the session", suspendedIndices.count)
        }
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
    }

    private func restoreAfterNetplay() {
        guard netplaySuspended else { return }
        netplaySuspended = false
        let indices = suspendedIndices
        suspendedIndices = []
        // Pro can lapse during a session; never resurrect enabled cheats without it.
        if Self.canEnableCheats {
            for i in entries.indices where indices.contains(entries[i].index) {
                entries[i].enabled = true
                push(entries[i])
            }
        }
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
    }

    private func push(_ entry: Entry) {
        guard let engine, entry.available else { return }
        switch entry.kind {
        case .onOff:
            engine.setEnabled(entry.enabled, at: entry.index)
        case .parameter:
            if entry.enabled, entry.position >= 0 {
                engine.setParameterPosition(entry.position, at: entry.index)
            } else {
                engine.setEnabled(false, at: entry.index)
            }
        default:
            break
        }
    }

    // MARK: - Mutations

    /// On/off entries, and turning a parameter entry off.
    @discardableResult
    func setEnabled(_ enabled: Bool, index: Int) -> Bool {
        guard canChange(enabling: enabled), let i = entries.firstIndex(where: { $0.index == index }),
              entries[i].kind == .onOff || (entries[i].kind == .parameter && !enabled) else { return false }
        entries[i].enabled = enabled
        return commit(i)
    }

    /// Switches a parameter entry on at `position`.
    @discardableResult
    func setPosition(_ position: Int, index: Int) -> Bool {
        guard canChange(enabling: true), let i = entries.firstIndex(where: { $0.index == index }),
              entries[i].kind == .parameter else { return false }
        entries[i].enabled = true
        entries[i].position = position
        return commit(i)
    }

    /// Runs a one-shot entry; one-shot parameters run at `position`, which is remembered.
    @discardableResult
    func activate(index: Int, position: Int? = nil) -> Bool {
        guard canChange(enabling: true), let i = entries.firstIndex(where: { $0.index == index }),
              entries[i].available else { return false }
        switch entries[i].kind {
        case .oneShot:
            engine?.activate(at: index)
        case .oneShotParameter:
            guard let position else { return false }
            entries[i].position = position
            _ = Self.upsertState(romKey: game.key, entry: entries[i])
            engine?.setParameterPosition(position, at: index)
            engine?.activate(at: index)
        default:
            return false
        }
        NSLog("[MameCheat] Activated %d (%@)%@", index, entries[i].definition.desc, engine == nil ? " before the engine was ready" : "")
        return engine != nil
    }

    private func canChange(enabling: Bool) -> Bool {
        guard enabling else { return true }
        // Cheats would desync netplay peers.
        if RANetplayCoordinator.shared.isNetplayEnabled { return false }
        return Self.canEnableCheats
    }

    private func commit(_ i: Int) -> Bool {
        guard Self.upsertState(romKey: game.key, entry: entries[i]) else { return false }
        push(entries[i])
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
        return true
    }

    // MARK: - Persistence

    static let stateTable = SQLite.Table("rom_mame_cheat_state")
    static let romKey     = SQLite.Expression<String>("rom_key")
    static let cheatIndex = SQLite.Expression<Int>("cheat_index")
    /// Checked on restore so a changed cheat file never switches on a different entry.
    static let cheatDesc  = SQLite.Expression<String>("cheat_desc")
    static let enabled    = SQLite.Expression<Bool>("enabled")
    static let position   = SQLite.Expression<Int>("position")
    static let createAt   = SQLite.Expression<Date>("create_at")
    static let updateAt   = SQLite.Expression<Date>("update_at")

    private static func loadStates(romKey: String) -> [Int: (desc: String, enabled: Bool, position: Int)] {
        do {
            var states: [Int: (String, Bool, Int)] = [:]
            for row in try RetroRomPersistence.sqlite.prepare(stateTable.filter(self.romKey == romKey)) {
                states[row[cheatIndex]] = (row[cheatDesc], row[enabled], row[position])
            }
            return states
        } catch {
            NSLog("[MameCheat] Failed to load states: %@", "\(error)")
            return [:]
        }
    }

    private static func upsertState(romKey: String, entry: Entry) -> Bool {
        let now = Date()
        do {
            try RetroRomPersistence.sqlite.run(stateTable.insert(or: .replace,
                self.romKey <- romKey,
                cheatIndex <- entry.index,
                cheatDesc <- entry.definition.desc,
                enabled <- entry.enabled,
                position <- entry.position,
                createAt <- now,
                updateAt <- now
            ))
            return true
        } catch {
            NSLog("[MameCheat] Failed to save state: %@", "\(error)")
            return false
        }
    }

    /// Pro lapsed: no enabled state may survive into a game.
    private static func deleteEnabledStates(romKey: String) {
        do {
            try RetroRomPersistence.sqlite.run(stateTable.filter(self.romKey == romKey && enabled == true).delete())
        } catch {
            NSLog("[MameCheat] Failed to clear enabled states: %@", "\(error)")
        }
    }
}
