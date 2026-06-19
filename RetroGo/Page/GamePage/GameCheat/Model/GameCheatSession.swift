//
//  GameCheatSession.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/6.
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
import RACoordinator

enum GameCheatTemplateBindingOrigin: Int {
    case automatic = 0
    case manual = 1
}

struct GameCheatTemplateBinding {
    let romKey: String
    let coreId: String
    let status: Int
    let origin: GameCheatTemplateBindingOrigin
    let catalogGameId: Int?
    let catalogPlatformId: Int?
    let catalogGroupName: String?
    let catalogGameName: String?
    let cheatDBUserVersion: Int

    var isBound: Bool { status == 1 }

    func matches(catalogGame: RAGameEntry) -> Bool {
        catalogGameId == catalogGame.gameId &&
            catalogPlatformId == catalogGame.platformId &&
            catalogGroupName == catalogGame.groupName
    }
}

/// Owns one game's cheat runtime session. User-created cheats live in `romcheat`;
/// system template binding/state live in separate template tables. Swift/SQLite
/// is the source of truth and the engine receives only an execution snapshot.
final class GameCheatSession {
    let game: RetroRomFileItem
    let core: EmuCoreInfoItem
    let autoEnableCheatsOnLaunch: Bool

    private(set) var items: [GameCheatItem]
    private(set) var templateBinding: GameCheatTemplateBinding?
    private(set) var templateItems: [RACheatItem]

    /// Netplay is lockstep-deterministic and cannot sync cheats, so every cheat
    /// must read as OFF for the duration of a session. We mirror that into the
    /// in-memory snapshot (NOT the romcheat / template SQLite, which stay the
    /// source of truth) so the UI — toolbar green dot and the list switches —
    /// truthfully shows cheats as off instead of a stale "on" that does nothing.
    /// On session end we restore exactly what was enabled before it began.
    private var netplaySuspended = false
    private var suspendedUserIDs: Set<String> = []
    private var suspendedTemplateIDs: Set<Int> = []

    /// Runtime paths may run outside the purchase UI flow, so use the cached
    /// entitlement snapshot here. The UI gate still presents the paywall.
    private static var canEnableCheats: Bool {
        AppStorePurchaseManager.hasLocallyValidCachedProEntitlement
    }

    init(game: RetroRomFileItem, core: EmuCoreInfoItem, autoEnableCheatsOnLaunch: Bool = true) {
        self.game = game
        self.core = core
        self.autoEnableCheatsOnLaunch = autoEnableCheatsOnLaunch
        var items = Self.loadItems(romKey: game.key)
        if !autoEnableCheatsOnLaunch {
            // Safety fuse: do not restore persisted enabled user cheats into a
            // fresh game session. Keep SQLite untouched so turning the setting
            // back on can restore the user's previous choices.
            for index in items.indices {
                items[index].enabled = false
            }
        }
        self.items = items
        self.templateBinding = Self.loadTemplateBinding(romKey: game.key, coreId: core.coreId)
        self.templateItems = []

        // A netplay session may already be running when this session is built
        // (e.g. re-entering the game page); reflect it immediately, then keep in
        // sync with start/end.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(netplayStateDidChange),
            name: .netplayStateChanged,
            object: nil
        )
        if RANetplayCoordinator.shared.isNetplayEnabled {
            netplaySuspended = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Whether the running core can take emulator-handled cheats at all.
    var cheatSupported: Bool {
        RetroArchX.shared().cheatSupported
    }

    /// Whether at least one cheat is currently enabled (drives the toolbar badge).
    var hasActiveCheat: Bool {
        templateItems.contains { $0.enabled } || items.contains { $0.enabled }
    }

    // MARK: - Mutations (persist → update memory → re-push engine)

    @discardableResult
    func addCheat(_ draft: GameCheatItem) -> GameCheatItem? {
        guard let id = Self.makeUniqueCheatID() else { return nil }
        var item = draft.replacingID(id)
        item.sortIndex = items.count
        guard Self.insert(item) else { return nil }
        items.append(item)
        pushToEngine()
        return item
    }

    @discardableResult
    func updateCheat(_ item: GameCheatItem) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return false }
        var updated = item
        updated.updateAt = Date()
        guard Self.update(updated) else { return false }
        items[idx] = updated
        pushToEngine()
        return true
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, for item: GameCheatItem) -> Bool {
        // Cheats can't be enabled during a netplay session (would desync peers).
        // This is a non-destructive refusal — unlike the Pro-expiry path, it never
        // wipes the user's saved enabled flags.
        if enabled, RANetplayCoordinator.shared.isNetplayEnabled { return false }
        guard !enabled || Self.canEnableCheats else { return false }
        guard var found = items.first(where: { $0.id == item.id }) else { return false }
        found.enabled = enabled
        return updateCheat(found)
    }

    @discardableResult
    func setTemplateEnabled(_ enabled: Bool, for item: RACheatItem) -> Bool {
        if enabled, RANetplayCoordinator.shared.isNetplayEnabled { return false }
        guard !enabled || Self.canEnableCheats else { return false }
        guard let idx = templateItems.firstIndex(where: { $0.catalogId == item.catalogId }) else { return false }
        templateItems[idx].enabled = enabled
        guard Self.upsertTemplateState(
            romKey: game.key,
            coreId: core.coreId,
            catalogCheatId: item.catalogId,
            enabled: enabled
        ) else { return false }
        pushToEngine()
        return true
    }

    @discardableResult
    func deleteCheat(_ item: GameCheatItem) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return false }
        guard Self.delete(id: item.id) else { return false }
        items.remove(at: idx)
        reindexAndPersist()
        pushToEngine()
        return true
    }

    /// Reorders the list to match `idOrder` (the new order of cheat ids after a
    /// drag), renumbers `sortIndex`, persists, and re-pushes. Order only matters
    /// functionally for `RUN_NEXT_IF_*` chains, but the engine list mirrors it
    /// regardless. Ids not present are ignored; the count must still match.
    @discardableResult
    func reorder(idOrder: [String]) -> Bool {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let reordered = idOrder.compactMap { byId[$0] }
        guard reordered.count == items.count else { return false }
        items = reordered
        reindexAndPersist()
        pushToEngine()
        return true
    }

    /// Pushes the current list to the engine and applies the enabled ones.
    func applyToEngine() {
        pushToEngine()
    }

    func reloadTemplateBinding() {
        templateBinding = Self.loadTemplateBinding(romKey: game.key, coreId: core.coreId)
    }

    func reloadTemplateItems(completion: @escaping () -> Void) {
        disableEnabledCheatsIfNeeded()
        reloadTemplateBinding()
        guard let binding = templateBinding,
              binding.isBound,
              let gameId = binding.catalogGameId else {
            templateItems = []
            pushToEngine()
            completion()
            return
        }

        initializeCheatCatalog { [weak self] ready in
            guard let self else { return }
            guard ready else {
                self.templateItems = []
                self.pushToEngine()
                completion()
                return
            }
            RACheatCatalogManager.shared().fetchCheats(forGameId: gameId) { [weak self] cheats, _ in
                guard let self else { return }
                let states: [Int: Bool]
                if !Self.canEnableCheats {
                    states = [:]
                } else if self.autoEnableCheatsOnLaunch {
                    states = Self.loadTemplateStates(romKey: self.game.key, coreId: self.core.coreId)
                } else {
                    // Same safety fuse for system templates. Preserve switches
                    // toggled manually during this running session, but do not
                    // resurrect persisted enabled states just by opening a game.
                    states = Dictionary(
                        self.templateItems.map { ($0.catalogId, $0.enabled) },
                        uniquingKeysWith: { current, _ in current }
                    )
                }
                for cheat in cheats {
                    // System templates are opt-in: missing state means disabled.
                    cheat.enabled = states[cheat.catalogId] ?? false
                }
                self.templateItems = cheats
                self.pushToEngine()
                completion()
            }
        }
    }

    /// Pro is checked again at runtime because subscriptions can expire after a
    /// cheat was previously enabled. Non-Pro users may still browse/edit cheats,
    /// but no enabled state is allowed to survive into the engine snapshot.
    private func disableEnabledCheatsIfNeeded() {
        guard !Self.canEnableCheats else { return }

        var changed = false
        for index in items.indices where items[index].enabled {
            var item = items[index]
            item.enabled = false
            item.updateAt = Date()
            if Self.update(item) {
                items[index] = item
                changed = true
            }
        }

        if Self.deleteEnabledTemplateStates(romKey: game.key, coreId: core.coreId) {
            changed = true
        }

        for cheat in templateItems where cheat.enabled {
            cheat.enabled = false
            changed = true
        }

        if changed {
            pushToEngine()
        }
    }

    @discardableResult
    func bindTemplate(_ catalogGame: RAGameEntry,
                      origin: GameCheatTemplateBindingOrigin = .manual) -> Bool {
        guard let groupName = catalogGame.groupName, !groupName.isEmpty else {
            return false
        }
        guard catalogGame.gameId > 0 else {
            return false
        }
        let version = RACheatCatalogManager.shared().currentDBUserVersion
        guard Self.upsertTemplateBinding(
            romKey: game.key,
            coreId: core.coreId,
            origin: origin,
            catalogGameId: catalogGame.gameId,
            catalogPlatformId: catalogGame.platformId,
            catalogGroupName: groupName,
            catalogGameName: catalogGame.name,
            cheatDBVersion: version
        ) else {
            return false
        }
        _ = Self.deleteTemplateStates(romKey: game.key, coreId: core.coreId)
        reloadTemplateBinding()
        // Replacing a built-in template must stop the previously enabled
        // template cheats immediately. User-created cheats stay in `items` and
        // are re-pushed below, so this does not clear the user's own cheats.
        templateItems = []
        pushToEngine()
        return true
    }

    /// Explicitly unbinds the current system template. Recorded as a manual
    /// no-match so the launch-time auto-binder won't re-attach the same (wrong)
    /// template at this catalog version; a future cheat.sqlite version still gets
    /// a fresh lookup. User-created cheats are untouched.
    @discardableResult
    func unbindTemplate() -> Bool {
        let version = RACheatCatalogManager.shared().currentDBUserVersion
        guard Self.upsertTemplateUnbind(
            romKey: game.key,
            coreId: core.coreId,
            cheatDBVersion: version
        ) else {
            return false
        }
        _ = Self.deleteTemplateStates(romKey: game.key, coreId: core.coreId)
        reloadTemplateBinding()
        templateItems = []
        pushToEngine()
        return true
    }

    // MARK: - Netplay cheat suppression

    /// Mirrors the live netplay state into the in-memory cheat snapshot. Posted
    /// on session start/end (and peer changes) by `RANetplayCoordinator`.
    @objc private func netplayStateDidChange() {
        if RANetplayCoordinator.shared.isNetplayEnabled {
            suspendCheatsForNetplay()
        } else {
            restoreCheatsAfterNetplay()
        }
    }

    /// Records which cheats were enabled and forces them off in memory so the UI
    /// reads them as off. SQLite is never touched, so the user's saved choices
    /// survive the session and can be restored verbatim afterwards.
    private func suspendCheatsForNetplay() {
        guard !netplaySuspended else { return }
        netplaySuspended = true
        // `pushToEngine` → `normalizeNetplaySuppression` captures the currently
        // enabled cheats into the suspended sets and clears their in-memory flags.
        pushToEngine()
    }

    /// Re-applies the enabled state captured at session start. Reads only the
    /// in-memory snapshot we saved; romcheat / `rom_cheat_template_state` are the
    /// durable source and were never modified, so they already agree.
    private func restoreCheatsAfterNetplay() {
        guard netplaySuspended else { return }
        netplaySuspended = false
        let userIDs = suspendedUserIDs
        let templateIDs = suspendedTemplateIDs
        suspendedUserIDs = []
        suspendedTemplateIDs = []
        // Pro can lapse during a session; never resurrect enabled cheats without
        // it. The list's own Pro-expiry path wipes the persisted flags later.
        if Self.canEnableCheats {
            for index in items.indices where userIDs.contains(items[index].id) {
                items[index].enabled = true
            }
            for cheat in templateItems where templateIDs.contains(cheat.catalogId) {
                cheat.enabled = true
            }
        }
        pushToEngine()
    }

    /// While a netplay session is active, no cheat may read as enabled. This runs
    /// at the single engine boundary so any path that turns one on (template
    /// reload from SQLite, add) is folded into the suspended sets and cleared,
    /// keeping the in-memory snapshot — and the UI — honestly off.
    private func normalizeNetplaySuppression() {
        guard netplaySuspended else { return }
        for index in items.indices where items[index].enabled {
            suspendedUserIDs.insert(items[index].id)
            items[index].enabled = false
        }
        for cheat in templateItems where cheat.enabled {
            suspendedTemplateIDs.insert(cheat.catalogId)
            cheat.enabled = false
        }
    }

    // MARK: - Engine bridge

    /// Rebuilds the engine cheat list from the immutable system template rows
    /// followed by the user-created rows. System rows are not editable/reorderable,
    /// but their enabled flags are persisted separately.
    private func pushToEngine() {
        normalizeNetplaySuppression()
        let bridged = templateItems + items.map(Self.makeRACheatItem(from:))
        RetroArchX.shared().setCheats(bridged, apply: true)
        // Every mutation funnels through here, so this is the one place to signal
        // the toolbar that the "cheat active" state may have changed.
        NotificationCenter.default.post(name: .gameCheatStateChanged, object: nil)
    }

    static func makeRACheatItem(from item: GameCheatItem) -> RACheatItem {
        let ra = RACheatItem()
        ra.handler            = item.handler == .retro ? .RETRO : .EMU
        ra.desc               = item.desc
        ra.code               = item.code
        ra.enabled            = item.enabled
        ra.cheatType          = UInt(item.cheatType.rawValue)
        ra.memorySearchSize   = UInt(item.memorySize.rawValue)
        ra.address            = UInt(bitPattern: item.address)
        ra.value              = UInt(bitPattern: item.value)
        ra.addressMask        = UInt(bitPattern: item.addressMask)
        ra.bigEndian          = item.bigEndian
        ra.repeatCount        = UInt(bitPattern: item.repeatCount)
        ra.repeatAddToValue   = UInt(bitPattern: item.repeatAddToValue)
        ra.repeatAddToAddress = UInt(bitPattern: item.repeatAddToAddress)
        ra.rumbleType              = UInt(bitPattern: item.rumble.type)
        ra.rumbleValue             = UInt(bitPattern: item.rumble.value)
        ra.rumblePort              = UInt(bitPattern: item.rumble.port)
        ra.rumblePrimaryStrength   = UInt(bitPattern: item.rumble.primaryStrength)
        ra.rumblePrimaryDuration   = UInt(bitPattern: item.rumble.primaryDuration)
        ra.rumbleSecondaryStrength = UInt(bitPattern: item.rumble.secondaryStrength)
        ra.rumbleSecondaryDuration = UInt(bitPattern: item.rumble.secondaryDuration)
        return ra
    }

    /// Renumbers `sortIndex` to be contiguous after a removal and persists any row
    /// whose position changed.
    private func reindexAndPersist() {
        for (position, item) in items.enumerated() where item.sortIndex != position {
            var fixed = item
            fixed.sortIndex = position
            fixed.updateAt = Date()
            _ = Self.update(fixed)
            items[position] = fixed
        }
    }

    private func initializeCheatCatalog(completion: @escaping (Bool) -> Void) {
        guard let cheat = OnDemandResourceLoader.resource(id: "cheat") else {
            completion(false)
            return
        }
        guard case .ready = OnDemandResourceLoader.shared.state(for: cheat) else {
            completion(false)
            return
        }
        let loader = OnDemandResourceLoader.shared
        let locPath = OnDemandResourceLoader.resource(id: "gameloc").map { loader.targetPath($0) }
        RACheatCatalogManager.shared().initialize(
            withCheatPath: loader.targetPath(cheat),
            localizationPath: locPath
        ) {
            completion(RACheatCatalogManager.shared().isDatabaseReady)
        }
    }
}

// MARK: - Schema (table created in RetroRomPersistence+v6)

extension GameCheatSession {
    static let romCheatTable = SQLite.Table("romcheat")
    static let templateBindingTable = SQLite.Table("rom_cheat_template_binding")
    static let templateStateTable = SQLite.Table("rom_cheat_template_state")

    static let cheatId    = SQLite.Expression<String>("id")
    static let romKey     = SQLite.Expression<String>("rom_key")
    static let coreId     = SQLite.Expression<String>("core_id")
    static let kind       = SQLite.Expression<Int>("kind")
    static let desc       = SQLite.Expression<String>("desc")
    static let code       = SQLite.Expression<String>("code")
    static let enabled    = SQLite.Expression<Bool>("enabled")
    static let sortIndex  = SQLite.Expression<Int>("sort_index")
    // RETRO structured fields
    static let cheatType          = SQLite.Expression<Int>("cheat_type")
    static let memorySearchSize   = SQLite.Expression<Int>("memory_search_size")
    static let address            = SQLite.Expression<Int>("address")
    static let value              = SQLite.Expression<Int>("value")
    static let addressMask        = SQLite.Expression<Int>("address_mask")
    static let bigEndian          = SQLite.Expression<Bool>("big_endian")
    static let repeatCount        = SQLite.Expression<Int>("repeat_count")
    static let repeatAddToValue   = SQLite.Expression<Int>("repeat_add_to_value")
    static let repeatAddToAddress = SQLite.Expression<Int>("repeat_add_to_address")
    // Reserved
    static let rumbleConfigBlob   = SQLite.Expression<Data?>("rumble_config_blob")
    static let createAt   = SQLite.Expression<Date>("create_at")
    static let updateAt   = SQLite.Expression<Date>("update_at")

    // Built-in template binding. `status` is the whole state machine:
    // 0 = checked current cheat DB and found no template, 1 = bound.
    static let templateStatus = SQLite.Expression<Int>("status")
    static let templateBindingOrigin = SQLite.Expression<Int>("binding_origin")
    static let catalogGameId = SQLite.Expression<Int?>("catalog_game_id")
    static let catalogPlatformId = SQLite.Expression<Int?>("catalog_platform_id")
    static let catalogGroupName = SQLite.Expression<String?>("catalog_group_name")
    static let catalogGameName = SQLite.Expression<String?>("catalog_game_name")
    static let cheatDBUserVersion = SQLite.Expression<Int>("cheat_db_user_version")
    static let catalogCheatId = SQLite.Expression<Int>("catalog_cheat_id")
}

// MARK: - Persistence

extension GameCheatSession {
    static func loadItems(romKey: String) -> [GameCheatItem] {
        let db = RetroRomPersistence.sqlite
        let query = romCheatTable
            .filter(self.romKey == romKey)
            .order(sortIndex.asc, createAt.asc)
        do {
            return try db.prepare(query).map(makeItem(from:))
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return []
        #endif
        }
    }

    static func makeUniqueCheatID() -> String? {
        let db = RetroRomPersistence.sqlite
        do {
            while true {
                let id = GameCheatItem.makeID()
                let query = romCheatTable.filter(cheatId == id).limit(1)
                if (try db.pluck(query)) == nil {
                    return id
                }
            }
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return nil
        #endif
        }
    }

    static func loadTemplateBinding(romKey: String, coreId: String) -> GameCheatTemplateBinding? {
        let db = RetroRomPersistence.sqlite
        let query = templateBindingTable
            .filter(self.romKey == romKey && self.coreId == coreId)
            .limit(1)
        do {
            guard let row = try db.pluck(query) else { return nil }
            return GameCheatTemplateBinding(
                romKey: row[self.romKey],
                coreId: row[self.coreId],
                status: row[templateStatus],
                origin: GameCheatTemplateBindingOrigin(rawValue: row[templateBindingOrigin]) ?? .automatic,
                catalogGameId: row[catalogGameId],
                catalogPlatformId: row[catalogPlatformId],
                catalogGroupName: row[catalogGroupName],
                catalogGameName: row[catalogGameName],
                cheatDBUserVersion: row[cheatDBUserVersion]
            )
        } catch {
            return nil
        }
    }

    static func loadTemplateStates(romKey: String, coreId: String) -> [Int: Bool] {
        let db = RetroRomPersistence.sqlite
        let query = templateStateTable
            .filter(self.romKey == romKey && self.coreId == coreId)
        do {
            var values: [Int: Bool] = [:]
            for row in try db.prepare(query) {
                values[row[catalogCheatId]] = row[enabled]
            }
            return values
        } catch {
            return [:]
        }
    }

    @discardableResult
    static func upsertTemplateState(romKey: String,
                                    coreId: String,
                                    catalogCheatId: Int,
                                    enabled: Bool) -> Bool {
        let now = Date()
        do {
            try RetroRomPersistence.sqlite.run(templateStateTable.insert(or: .replace,
                self.romKey <- romKey,
                self.coreId <- coreId,
                self.catalogCheatId <- catalogCheatId,
                self.enabled <- enabled,
                self.createAt <- now,
                self.updateAt <- now
            ))
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func upsertTemplateBinding(romKey: String,
                                      coreId: String,
                                      origin: GameCheatTemplateBindingOrigin,
                                      catalogGameId: Int,
                                      catalogPlatformId: Int,
                                      catalogGroupName: String,
                                      catalogGameName: String,
                                      cheatDBVersion: Int) -> Bool {
        let now = Date()
        do {
            try RetroRomPersistence.sqlite.run(templateBindingTable.insert(or: .replace,
                self.romKey <- romKey,
                self.coreId <- coreId,
                templateStatus <- 1,
                templateBindingOrigin <- origin.rawValue,
                self.catalogGameId <- catalogGameId,
                self.catalogPlatformId <- catalogPlatformId,
                self.catalogGroupName <- catalogGroupName,
                self.catalogGameName <- catalogGameName,
                cheatDBUserVersion <- cheatDBVersion,
                createAt <- now,
                updateAt <- now
            ))
            return true
        } catch {
            return false
        }
    }

    /// Persists a manual no-match (status 0, origin manual) for the current
    /// catalog version. Mirrors the auto-binder's no-match row but flags it as
    /// user-driven, which keeps the auto-binder from re-binding until the
    /// cheat.sqlite version changes.
    @discardableResult
    static func upsertTemplateUnbind(romKey: String,
                                     coreId: String,
                                     cheatDBVersion: Int) -> Bool {
        let now = Date()
        do {
            try RetroRomPersistence.sqlite.run(templateBindingTable.insert(or: .replace,
                self.romKey <- romKey,
                self.coreId <- coreId,
                templateStatus <- 0,
                templateBindingOrigin <- GameCheatTemplateBindingOrigin.manual.rawValue,
                catalogGameId <- nil,
                catalogPlatformId <- nil,
                catalogGroupName <- nil,
                catalogGameName <- nil,
                cheatDBUserVersion <- cheatDBVersion,
                createAt <- now,
                updateAt <- now
            ))
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func deleteTemplateStates(romKey: String, coreId: String) -> Bool {
        let states = templateStateTable
            .filter(self.romKey == romKey && self.coreId == coreId)
        do {
            try RetroRomPersistence.sqlite.run(states.delete())
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func deleteEnabledTemplateStates(romKey: String, coreId: String) -> Bool {
        let states = templateStateTable
            .filter(self.romKey == romKey && self.coreId == coreId && enabled == true)
        do {
            try RetroRomPersistence.sqlite.run(states.delete())
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func deleteTemplateBindingAndStates(romKey: String, coreId: String) -> Bool {
        let binding = templateBindingTable
            .filter(self.romKey == romKey && self.coreId == coreId)
        let states = templateStateTable
            .filter(self.romKey == romKey && self.coreId == coreId)
        do {
            try RetroRomPersistence.sqlite.transaction {
                try RetroRomPersistence.sqlite.run(states.delete())
                try RetroRomPersistence.sqlite.run(binding.delete())
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func deleteAllTemplateBindingsAndStates(romKey: String) -> Bool {
        let bindings = templateBindingTable
            .filter(self.romKey == romKey)
        let states = templateStateTable
            .filter(self.romKey == romKey)
        do {
            try RetroRomPersistence.sqlite.transaction {
                try RetroRomPersistence.sqlite.run(states.delete())
                try RetroRomPersistence.sqlite.run(bindings.delete())
            }
            return true
        } catch {
            return false
        }
    }

    private static func makeItem(from row: Row) -> GameCheatItem {
        let rumble: GameCheatRumbleConfig
        if let data = row[rumbleConfigBlob],
           let decoded = try? JSONDecoder().decode(GameCheatRumbleConfig.self, from: data) {
            rumble = decoded
        } else {
            rumble = .none
        }

        return GameCheatItem(
            id: row[cheatId],
            romKey: row[self.romKey],
            coreId: row[coreId],
            kind: GameCheatKind(rawValue: row[kind]) ?? .numeric,
            desc: row[desc],
            enabled: row[enabled],
            sortIndex: row[sortIndex],
            code: row[code],
            cheatType: GameCheatType(rawValue: row[cheatType]) ?? .setToValue,
            memorySize: GameCheatMemorySize(rawValue: row[memorySearchSize]) ?? .byte1,
            address: row[address],
            value: row[value],
            addressMask: row[addressMask],
            bigEndian: row[bigEndian],
            repeatCount: row[repeatCount],
            repeatAddToValue: row[repeatAddToValue],
            repeatAddToAddress: row[repeatAddToAddress],
            rumble: rumble,
            createAt: row[createAt],
            updateAt: row[updateAt]
        )
    }

    private static func rumbleBlob(_ config: GameCheatRumbleConfig) -> Data? {
        config.isDefault ? nil : try? JSONEncoder().encode(config)
    }

    @discardableResult
    static func insert(_ item: GameCheatItem) -> Bool {
        let db = RetroRomPersistence.sqlite
        do {
            try db.run(romCheatTable.insert(
                cheatId            <- item.id,
                romKey             <- item.romKey,
                coreId             <- item.coreId,
                kind               <- item.kind.rawValue,
                desc               <- item.desc,
                code               <- item.code,
                enabled            <- item.enabled,
                sortIndex          <- item.sortIndex,
                cheatType          <- item.cheatType.rawValue,
                memorySearchSize   <- item.memorySize.rawValue,
                address            <- item.address,
                value              <- item.value,
                addressMask        <- item.addressMask,
                bigEndian          <- item.bigEndian,
                repeatCount        <- item.repeatCount,
                repeatAddToValue   <- item.repeatAddToValue,
                repeatAddToAddress <- item.repeatAddToAddress,
                rumbleConfigBlob   <- rumbleBlob(item.rumble),
                createAt           <- item.createAt,
                updateAt           <- item.updateAt
            ))
            return true
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return false
        #endif
        }
    }

    @discardableResult
    static func update(_ item: GameCheatItem) -> Bool {
        let db = RetroRomPersistence.sqlite
        let row = romCheatTable.filter(cheatId == item.id)
        do {
            try db.run(row.update(
                kind               <- item.kind.rawValue,
                desc               <- item.desc,
                code               <- item.code,
                enabled            <- item.enabled,
                sortIndex          <- item.sortIndex,
                cheatType          <- item.cheatType.rawValue,
                memorySearchSize   <- item.memorySize.rawValue,
                address            <- item.address,
                value              <- item.value,
                addressMask        <- item.addressMask,
                bigEndian          <- item.bigEndian,
                repeatCount        <- item.repeatCount,
                repeatAddToValue   <- item.repeatAddToValue,
                repeatAddToAddress <- item.repeatAddToAddress,
                rumbleConfigBlob   <- rumbleBlob(item.rumble),
                updateAt           <- item.updateAt
            ))
            return true
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return false
        #endif
        }
    }

    @discardableResult
    static func delete(id: String) -> Bool {
        let db = RetroRomPersistence.sqlite
        do {
            try db.run(romCheatTable.filter(cheatId == id).delete())
            return true
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return false
        #endif
        }
    }

    /// Removes every user cheat and template binding/state belonging to a game.
    /// For the ROM-deletion cleanup path.
    @discardableResult
    static func deleteAll(romKey: String) -> Bool {
        let db = RetroRomPersistence.sqlite
        let userCheats = romCheatTable.filter(self.romKey == romKey)
        let templateBindings = templateBindingTable.filter(self.romKey == romKey)
        let templateStates = templateStateTable.filter(self.romKey == romKey)
        do {
            try db.transaction {
                try db.run(templateStates.delete())
                try db.run(templateBindings.delete())
                try db.run(userCheats.delete())
            }
            return true
        } catch {
            return false
        }
    }
}
