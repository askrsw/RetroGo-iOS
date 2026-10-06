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
import os

/// Cheats of one MAME game run, executed by MAME's own cheat engine.
///
/// The launch check records the running set (`MameCheatLibrary.prepareLaunch`). Once the
/// machine runs, the set's XML is handed to the core in memory and reloaded; MAME then has
/// every entry off. Like standalone MAME, cheats stay off until the player turns them on:
/// most write memory every frame, and doing that from the first frame breaks boot self-tests
/// (NeoGeo stops at "WORK RAM ERROR" when a weapon cheat writes into the RAM it is testing).
/// MAME has no "boot finished" signal, and even a loaded auto-save may have been taken during
/// the self-test, so cheats that were on last time are never switched on by themselves: the
/// toolbar shows a restore dot and the player restores them from the list once the game runs.
/// A reset reboots the machine, so it turns the cheats off and offers them for restore again.
/// After each load, every index is checked against the XML description (an entry the engine
/// rejects is skipped, which would shift the ones after it). Changes made while the game is
/// paused are queued in the core and take effect on the next frame.
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
    /// Recognized set of this run; nil when the launch did not go through the MAME check.
    let setName: String?
    /// Name of the cheat file in use (the set's own or its parent's); nil without cheats.
    private(set) var fileName: String?
    private(set) var entries: [Entry] = []
    private var xml: Data?

    private var engine: RAMameCheatEngine?
    private var pollTimer: Timer?

    /// Netplay is lockstep-deterministic and cannot sync cheats: while a session runs every
    /// cheat is off in memory and in the engine. SQLite keeps the user's choices, and the
    /// ones that were on come back when the session ends.
    private var netplaySuspended = false
    private var suspendedIndices: Set<Int> = []
    /// Cheats that were on last time (or before a reset/reload) and are waiting to be restored.
    private var restorableIndices: [Int] = []

    init(game: RetroRomFileItem, core: EmuCoreInfoItem) {
        self.game = game
        self.core = core
        setName = MameCheatLibrary.shared.takeLaunch(romKey: game.key)?.setName

        loadFromLibrary()

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

    /// Reads the set's XML from the library and rebuilds the entries, all off, with the saved
    /// parameter values; the ones that were on become restorable.
    private func loadFromLibrary() {
        let file = setName.flatMap { MameCheatLibrary.shared.cheatFile(forSet: $0) }
        let definitions = file.flatMap { MameCheatDefinition.parse($0.xml) } ?? []
        fileName = definitions.isEmpty ? nil : file?.fileName
        xml = definitions.isEmpty ? nil : file?.xml

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

    /// Cheats from last time that the list can offer to restore; 0 until the cheats are loaded.
    var restorableCount: Int {
        guard engine != nil, !netplaySuspended else { return 0 }
        return restorableIndices.filter { index in entries.contains { $0.index == index && !$0.enabled && $0.available } }.count
    }

    /// Call once the core started. Waits for the machine to run, then hands this game's XML
    /// to the core (or clears the previous game's) and loads it.
    func gameDidStart() {
        startLoading()
    }

    /// Call when the game closes, while the core is still loaded: the core keeps the XML for
    /// the whole process.
    func endSession() {
        pollTimer?.invalidate()
        pollTimer = nil
        (engine ?? RAMameCheatEngine.forLoadedCore())?.setCheatXML(nil)
        engine = nil
    }

    /// The library was imported or replaced while the game runs: load the set's cheats now.
    /// Cheats that were on go off (the engine reloads every entry) and become restorable.
    func reloadFromLibrary() {
        let active = entries.filter { $0.enabled && ($0.kind == .onOff || $0.kind == .parameter) }
        for entry in active {
            _ = Self.upsertState(romKey: game.key, entry: entry)
        }
        suspendedIndices = []
        loadFromLibrary()
        engine = nil
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
        startLoading()
    }

    private enum LoadPhase {
        case waitingForMachine
        /// The reload runs on the next frame, which may be long after this (the game is
        /// paused while the cheat list is open); the load generation tells when it ran.
        case waitingForCheats(RAMameCheatEngine, generation: UInt)
    }

    private func startLoading() {
        pollTimer?.invalidate()
        var phase = LoadPhase.waitingForMachine
        var attempts = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            attempts += 1
            switch phase {
            case .waitingForMachine:
                guard let engine = RAMameCheatEngine.forLoadedCore(), engine.count >= 0 else {
                    if attempts >= 240 { timer.invalidate(); self.pollTimer = nil }
                    return
                }
                engine.setCheatXML(self.xml)
                let generation = engine.loadGeneration
                guard self.xml != nil, engine.reload() else {
                    timer.invalidate()
                    self.pollTimer = nil
                    return
                }
                phase = .waitingForCheats(engine, generation: generation)
            case .waitingForCheats(let engine, let generation):
                guard engine.loadGeneration != generation else { return }
                timer.invalidate()
                self.pollTimer = nil
                self.attach(engine)
            }
        }
    }

    private func attach(_ engine: RAMameCheatEngine) {
        let running = engine.entries()
        if running.count != entries.count {
            RetroGoLogger.mame.notice("Cheat engine has \(running.count) entries, \(self.fileName ?? "-", privacy: .public).xml has \(self.entries.count)")
        }
        for index in entries.indices {
            let desc = index < running.count ? running[index].desc.trimmingCharacters(in: .whitespaces) : nil
            entries[index].available = desc == entries[index].definition.desc
            if !entries[index].available {
                RetroGoLogger.mame.notice("Cheat entry \(index) (\(self.entries[index].definition.desc, privacy: .public)) does not match the engine; disabled")
            }
        }
        self.engine = engine
        RetroGoLogger.mame.info("Loaded \(running.count) cheats of \(self.fileName ?? "-", privacy: .public).xml for \(self.setName ?? "-", privacy: .public)")
        for entry in entries where entry.enabled && entry.available {
            push(entry)
        }
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
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
        RetroGoLogger.mame.info("Cheat reset; \(active.count) cheats turned off until restored")
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
            RetroGoLogger.mame.info("Netplay started; \(self.suspendedIndices.count) cheats turned off for the session")
        }
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
    }

    private func restoreAfterNetplay() {
        guard netplaySuspended else { return }
        netplaySuspended = false
        let indices = suspendedIndices
        suspendedIndices = []
        for i in entries.indices where indices.contains(entries[i].index) {
            entries[i].enabled = true
            push(entries[i])
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
        if enabled { discardRestorable(except: index) }
        entries[i].enabled = enabled
        return commit(i)
    }

    /// Switches a parameter entry on at `position`.
    @discardableResult
    func setPosition(_ position: Int, index: Int) -> Bool {
        guard canChange(enabling: true), let i = entries.firstIndex(where: { $0.index == index }),
              entries[i].kind == .parameter else { return false }
        discardRestorable(except: index)
        entries[i].enabled = true
        entries[i].position = position
        return commit(i)
    }

    /// Runs a one-shot entry; one-shot parameters run at `position`, which is remembered.
    @discardableResult
    func activate(index: Int, position: Int? = nil) -> Bool {
        guard canChange(enabling: true), let i = entries.firstIndex(where: { $0.index == index }),
              entries[i].available else { return false }
        discardRestorable(except: index)
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
        RetroGoLogger.mame.info("Activated cheat \(index) (\(self.entries[i].definition.desc, privacy: .public))\(self.engine == nil ? " before the engine was ready" : "", privacy: .public)")
        return engine != nil
    }

    /// The player picked cheats by hand, so last time's are not offered any more; they are
    /// saved as off so the next launch offers what this run actually used.
    private func discardRestorable(except index: Int) {
        guard !restorableIndices.isEmpty else { return }
        for restorable in restorableIndices where restorable != index {
            if let entry = entries.first(where: { $0.index == restorable && !$0.enabled }) {
                _ = Self.upsertState(romKey: game.key, entry: entry)
            }
        }
        restorableIndices = []
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
    }

    private func canChange(enabling: Bool) -> Bool {
        guard enabling else { return true }
        // Cheats would desync netplay peers.
        return !RANetplayCoordinator.shared.isNetplayEnabled
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
            RetroGoLogger.mame.error("Failed to load cheat states: \(String(describing: error))")
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
            RetroGoLogger.mame.error("Failed to save cheat state: \(String(describing: error))")
            return false
        }
    }
}
