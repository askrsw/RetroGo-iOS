//
//  GameConfigSession.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/17.
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

enum GameConfigScope: String {
    case global, core, game
}

/// Turbo auto-fire speed presets. The stored value is the `rawValue` (stable —
/// never renumber), not the underlying frames. `period`/`duty` are in emulator
/// frames: a cycle lasts `period` frames with `duty` of them held down, so the
/// fire rate is `frameRate / period` and is intentionally frame-relative (stable
/// across NTSC/PAL). One preset drives BOTH the on-screen overlay X/Y turbo and
/// the physical-controller X/Y turbo. `duty ≈ period/2` (≈50%); occupancy barely
/// affects feel, so it is not exposed separately. Tune the numbers freely.
enum TurboSpeed: Int, CaseIterable {
    case verySlow = 0
    case slow     = 1
    case medium   = 2   // default — matches the historical 4/2 value
    case fast     = 3
    case veryFast = 4

    static let `default`: TurboSpeed = .medium

    var period: Int {
        switch self {
        case .verySlow: return 12
        case .slow:     return 8
        case .medium:   return 4
        case .fast:     return 3
        case .veryFast: return 2
        }
    }

    var duty: Int {
        switch self {
        case .verySlow: return 6
        case .slow:     return 4
        case .medium:   return 2
        case .fast:     return 1
        case .veryFast: return 1
        }
    }
}

final class GameConfigSession {
    let scope: GameConfigScope
    let core: EmuCoreInfoItem?
    let game: RetroRomFileItem?
    private(set) var config: RAConfig!

    init(scope: GameConfigScope, core: EmuCoreInfoItem?, game: RetroRomFileItem?) {
        self.scope  = scope
        self.core   = core
        self.game   = game
        self.config = getConfig()
    }

    func configRetroArch() {
        RetroArchX.shared().config(config)

        RAInputActionManager.shared().fastForwardMultiplierProvider = { [weak self] in
            guard let self = self else { return 2.0 }
            return AppStoreProFeatureGate.effectiveFastForwardMultiplierForRuntime(getFastForwardMultiplier())
        }

        applyTurboSpeedToEngine()
    }

    /// Pushes the resolved turbo speed to the engine-side (physical-controller)
    /// turbo ticker. The overlay's own X/Y turbo is driven separately by the
    /// overlay scene. Both read the same `TurboSpeed` preset.
    func applyTurboSpeedToEngine() {
        let speed = getOverlayTurboSpeed()
        let manager = RAInputActionManager.shared()
        manager.turboPeriodFrames = UInt(speed.period)
        manager.turboDutyFrames = UInt(speed.duty)
    }

    func makeConfigData() -> [(section: GameConfigSection, entries: [GameConfigEntry])] {
        var array: [(section: GameConfigSection, entries: [GameConfigEntry])] = []

        let titleEntries = makeTitleConfigEntries()
        if titleEntries.count > 0 {
            array.append((section: .title, entries: titleEntries))
        }

        let discEntries = makeDiscConfigEntries()
        if discEntries.count > 0 {
            array.append((section: .disc, entries: discEntries))
        }

        let restartRequiredEntries = makeRestartRequiredConfigEntries()
        if restartRequiredEntries.count > 0 {
            array.append((section: .restartRequired, entries: restartRequiredEntries))
        }

        let overlayEntries = makeOverlayConfigEntries()
        if overlayEntries.count > 0 {
            array.append((section: .overlay, entries: overlayEntries))
        }

        let controllerEntries = makeControllerConfigEntries()
        if controllerEntries.count > 0 {
            array.append((section: .controller, entries: controllerEntries))
        }

        return array
    }
}

extension GameConfigSession {
    func getLogicThreadEnabled() -> Bool {
        config.logicThread
    }

    @discardableResult
    func setLogicThreadEnabled(value: Bool) -> Bool {
        config.logicThread = value
        return setOptionalValue(column: Self.threadEnabled, value: value)
    }

    func getFastForwardMultiplier() -> Double {
        config.fastForwardMultiplier
    }

    @discardableResult
    func setFastForwardMultiplier(value: Double) -> Bool {
        config.fastForwardMultiplier = value
        return setOptionalValue(column: Self.fastForwardMultiplier, value: value)
    }

    func getVideoDriver() -> String {
        config.videoDriver
    }

    @discardableResult
    func setVideoDriver(value: String) -> Bool {
        config.videoDriver = value
        return setOptionalValue(column: Self.videoDriver, value: value)
    }

    func getAudioDriver() -> String {
        config.audioDriver
    }

    @discardableResult
    func setAudioDriver(value: String) -> Bool {
        config.audioDriver = value
        return setOptionalValue(column: Self.audioDriver, value: value)
    }

    func getMuteOnFastForward() -> Bool {
        config.muteOnFastForward
    }

    @discardableResult
    func setMuteOnFastForward(value: Bool) -> Bool {
        config.muteOnFastForward = value
        return setOptionalValue(column: Self.muteOnFastForward, value: value)
    }

    func getOverlayTouchPlayer() -> Int {
        Int(config.overlayTouchPlayer)
    }

    @discardableResult
    func setOverlayTouchPlayer(value: Int) -> Bool {
        config.overlayTouchPlayer = Int32(value)
        return setOptionalValue(column: Self.overlayTouchPlayer, value: value)
    }

    /// Whether overlay X/Y allow the 0.15s "tap to latch" turbo shortcut. When
    /// off, X/Y are pure hold-to-burst. Persisted per cascade scope; defaults off.
    func getOverlayTurboTapLatch() -> Bool {
        config.overlayTurboTapLatch
    }

    @discardableResult
    func setOverlayTurboTapLatch(value: Bool) -> Bool {
        config.overlayTurboTapLatch = value
        let ok = setOptionalValue(column: Self.overlayTurboTapLatch, value: value)
        if ok {
            NotificationCenter.default.post(name: .overlayTurboTapLatchChanged, object: nil)
        }
        return ok
    }

    /// Resolved turbo speed preset (drives both overlay and physical-controller
    /// X/Y turbo). Falls back to the default tier for unknown stored values.
    func getOverlayTurboSpeed() -> TurboSpeed {
        TurboSpeed(rawValue: Int(config.overlayTurboSpeedTier)) ?? .default
    }

    @discardableResult
    func setOverlayTurboSpeed(_ speed: TurboSpeed) -> Bool {
        config.overlayTurboSpeedTier = Int32(speed.rawValue)
        let ok = setOptionalValue(column: Self.overlayTurboSpeed, value: speed.rawValue)
        if ok {
            // Apply live to the engine ticker, then let the overlay rebuild its own
            // turbo timing via the notification.
            applyTurboSpeedToEngine()
            NotificationCenter.default.post(name: .overlayTurboSpeedChanged, object: nil)
        }
        return ok
    }

    @discardableResult
    func saveInputBindingProfile(_ profile: RAInputBindingProfile?) -> Bool {
        config.inputBindingProfile = profile

        let data: Data?
        if let profile {
            do {
                data = try profile.encodedData()
            } catch {
            #if DEBUG
                fatalError("Encode inputBindingProfile failed: \(error.localizedDescription)")
            #else
                return false
            #endif
            }
        } else {
            data = nil
        }

        return setOptionalValue(column: Self.inputBindingProfile, value: data)
    }
}

// MARK: - In-game toolbar layout (global scope only)

/// On-disk shape of the in-game toolbar layout — a single JSON blob so future toolbar
/// settings need no extra columns or migrations. Arrays hold `GameToolbarAction`
/// raw values.
private struct ToolbarLayout: Codable {
    // `pinned`/`overflow` are nil until the user actually reorders the menu in
    // the editor. nil means "never reordered" → the default rule (declaration
    // order) applies, so newly added actions land by declaration order. Once
    // set, the stored order wins and `reconcile`/priority governs new actions.
    // Toggling `hidden`/`lockLandscape` alone must NOT populate these.
    var pinned: [String]?
    var overflow: [String]?
    // Optional so blobs written before each field existed still decode (a
    // missing key reads as nil → treated as false). New toolbar settings should
    // follow the same pattern instead of adding columns/migrations.
    var hidden: Bool?
}

extension GameConfigSession {
    /// The in-game top toolbar layout is a single global preference — there is no
    /// per-core or per-game variant — persisted in the `global` scope row of
    /// `romconfig` as one JSON blob (`toolbar_layout`). (The cascade machinery still
    /// allows adding per-scope overrides later without a migration.) This is App
    /// UI chrome, not engine config, so it is read/written directly and
    /// intentionally never enters `RAConfig`.
    ///
    /// Reads the toolbar action split plus whether the user has reordered the menu.
    /// - Not reordered (`isCustomized == false`): the default split (declaration
    ///   order). New actions appear by declaration order; callers may apply
    ///   default-only layout rules (e.g. the iPad `setting` anchor).
    /// - Reordered (`isCustomized == true`): the stored order reconciled against
    ///   the current action set (`GameToolbarAction.reconcile` → priority governs
    ///   where new actions land). Default rules no longer apply.
    static func globalToolbarActions() -> (pinned: [GameToolbarAction], overflow: [GameToolbarAction], isCustomized: Bool) {
        guard
            let layout = readToolbarLayout(),
            let storedPinned = layout.pinned,
            let storedOverflow = layout.overflow
        else {
            let split = GameToolbarAction.defaultSplit()
            return (split.pinned, split.overflow, false)
        }
        let pinned = storedPinned.compactMap(GameToolbarAction.init(rawValue:))
        let overflow = storedOverflow.compactMap(GameToolbarAction.init(rawValue:))
        let split = GameToolbarAction.reconcile(pinned: pinned, overflow: overflow)
        return (split.pinned, split.overflow, true)
    }

    /// Whether the in-game top bar is collapsed to just the close + more
    /// buttons. Persisted globally; defaults to shown.
    static var globalToolbarHidden: Bool {
        readToolbarLayout()?.hidden ?? false
    }

    /// Persists the pinned set (capped at `GameToolbarAction.maxPinned`; any excess
    /// is pushed to the front of the overflow) and the ordered overflow,
    /// preserving the other flags, then posts `.gameToolbarLayoutChanged`.
    @discardableResult
    static func setGlobalToolbar(pinned: [GameToolbarAction], overflow: [GameToolbarAction]) -> Bool {
        // pinned + overflow must be a duplicate-free partition of the action set.
        // A duplicate means a caller bug (e.g. a broken drag handler); trap it in
        // DEBUG rather than letting `reconcile` silently drop it on the next read.
        let combined = pinned + overflow
        assert(Set(combined).count == combined.count,
               "setGlobalToolbar: pinned/overflow contain a duplicate action — caller bug")

        let cappedPinned = Array(pinned.prefix(GameToolbarAction.maxPinned))
        let fullOverflow = Array(pinned.dropFirst(GameToolbarAction.maxPinned)) + overflow
        let ok = mutateToolbarLayout {
            $0.pinned = cappedPinned.map(\.rawValue)
            $0.overflow = fullOverflow.map(\.rawValue)
        }
        if ok {
            NotificationCenter.default.post(name: .gameToolbarLayoutChanged, object: nil)
        }
        return ok
    }

    /// Clears the stored menu order (back to nil), so the layout reverts to the
    /// default rule (declaration order). Preserves hidden/lockLandscape. Posts
    /// `.gameToolbarLayoutChanged` so the live toolbar rebuilds.
    @discardableResult
    static func resetGlobalToolbarOrder() -> Bool {
        let ok = mutateToolbarLayout {
            $0.pinned = nil
            $0.overflow = nil
        }
        if ok {
            NotificationCenter.default.post(name: .gameToolbarLayoutChanged, object: nil)
        }
        return ok
    }

    /// Persists the hidden flag, preserving everything else. Does not post
    /// `.gameToolbarLayoutChanged` — the toolbar toggles this itself and animates the
    /// transition in place.
    @discardableResult
    static func setGlobalToolbarHidden(_ hidden: Bool) -> Bool {
        mutateToolbarLayout { $0.hidden = hidden }
    }

    /// Read-modify-write of the global toolbar layout blob: starts from the stored
    /// blob (or the default split when nothing is customized), applies `mutate`,
    /// and writes it back. Keeps every setter from having to re-specify all the
    /// other fields.
    @discardableResult
    private static func mutateToolbarLayout(_ mutate: (inout ToolbarLayout) -> Void) -> Bool {
        var layout = readToolbarLayout() ?? defaultToolbarLayout()
        mutate(&layout)
        return writeToolbarLayout(layout)
    }

    /// A blank layout for first-time mutation of a non-order setting: pinned /
    /// overflow stay nil so toggling hidden/lock alone never counts as a menu
    /// reorder (which would otherwise flip `isCustomized` and change how future
    /// actions are placed).
    private static func defaultToolbarLayout() -> ToolbarLayout {
        ToolbarLayout(pinned: nil, overflow: nil, hidden: false)
    }

    // The global toolbar row is read/written directly rather than through a
    // `GameConfigSession(scope:.global)` instance — constructing one runs the
    // full `getConfig()` cascade (several plucks to build an `RAConfig`), which
    // is pure waste when we only touch one column on every toolbar interaction.
    private static var globalToolbarQuery: SQLite.Table {
        romConfigTable.filter(configScope == GameConfigScope.global.rawValue && key == "global")
    }

    private static func readToolbarLayout() -> ToolbarLayout? {
        do {
            guard
                let row = try RetroRomPersistence.sqlite.pluck(globalToolbarQuery),
                let data = row[toolbarLayout]
            else { return nil }
            return try? JSONDecoder().decode(ToolbarLayout.self, from: data)
        } catch {
            return nil
        }
    }

    @discardableResult
    private static func writeToolbarLayout(_ layout: ToolbarLayout) -> Bool {
        guard let data = try? JSONEncoder().encode(layout) else { return false }
        let db = RetroRomPersistence.sqlite
        do {
            if try db.pluck(globalToolbarQuery) != nil {
                try db.run(globalToolbarQuery.update(updateAt <- Date(), toolbarLayout <- data))
            } else {
                try db.run(romConfigTable.insert(
                    key <- "global",
                    configScope <- GameConfigScope.global.rawValue,
                    updateAt <- Date(),
                    toolbarLayout <- data
                ))
            }
            return true
        } catch {
            return false
        }
    }
}

private extension GameConfigSession {
    func getConfig() -> RAConfig {
        let pairs = makeConfigScopeKeyPairs()
        var cfg   = makeDefaultConfig()

        do {
            let db = RetroRomPersistence.sqlite
            for pair in pairs {
                let alice = Self.romConfigTable.filter(Self.configScope == pair.scope && Self.key == pair.key)
                if let row = try db.pluck(alice) {
                    apply(row: row, to: &cfg)
                }
            }
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return cfg
        #endif
        }

        if let core {
            if core.supportsLogicThread == false {
                cfg.logicThread = false
            }
            if core.isHWRender {
                cfg.videoDriver = RetroArchX.shared().defaultVideoDriver()
            }
        }

        return cfg
    }

    func makeConfigScopeKeyPairs() -> [(scope: String, key: String)] {
        var pairs: [(scope: String, key: String)] = [
            (scope: GameConfigScope.global.rawValue, key: "global"),
        ]
        if let core = core {
            pairs.append((scope: GameConfigScope.core.rawValue, key: core.coreId))
        }
        if let game = game {
            pairs.append((scope: GameConfigScope.game.rawValue, key: game.key))
        }
        return pairs
    }

    func makeDefaultConfig() -> RAConfig {
        let cfg = RAConfig()

        cfg.logicThread = core?.supportsLogicThread ?? false
        cfg.videoDriver = RetroArchX.shared().defaultVideoDriver()
        cfg.audioDriver = RetroArchX.shared().defaultAudioDriver()

        cfg.fastForwardMultiplier = 2.0
        cfg.muteOnFastForward     = false
        cfg.overlayTouchPlayer    = 0
        cfg.overlayTurboTapLatch  = false
        cfg.overlayTurboSpeedTier = Int32(TurboSpeed.default.rawValue)

        if let core {
            let coreCap = RAInputCoreCapabilities()
            coreCap.supportsAnalog = core.supportsAnalog
            coreCap.allowsDefaultTurboXYHijack = core.allowsDefaultTurboXYHijack
            cfg.coreCaps = coreCap
        }
        return cfg
    }

    func apply(row: Row, to config: inout RAConfig) {
        if let v = row[Self.threadEnabled] {
            config.logicThread = v
        }
        if let v = row[Self.fastForwardMultiplier] {
            config.fastForwardMultiplier = v
        }
        if let v = row[Self.videoDriver] {
            config.videoDriver = v
        }
        if let v = row[Self.audioDriver] {
            config.audioDriver = v
        }
        if let v = row[Self.muteOnFastForward] {
            config.muteOnFastForward = v
        }
        if let v = row[Self.overlayTouchPlayer] {
            config.overlayTouchPlayer = Int32(v)
        }
        if let v = row[Self.overlayTurboTapLatch] {
            config.overlayTurboTapLatch = v
        }
        if let v = row[Self.overlayTurboSpeed] {
            config.overlayTurboSpeedTier = Int32(v)
        }
        if let v = row[Self.inputBindingProfile] {
            do {
               let profile = try RAInputBindingProfile.decode(from: v)
                config.inputBindingProfile = profile
            #if DEBUG
                print(profile)
            #endif
            } catch {
            #if DEBUG
                fatalError("Decode inputBindingProfile failed: \(error.localizedDescription)")
            #else
                print("Decode inputBindingProfile failed: \(error.localizedDescription)")
            #endif
            }
        }
    }
}

private extension GameConfigSession {
    func resolveKey() -> String? {
        switch scope {
        case .global: return "global"
        case .core: return core?.coreId
        case .game: return game?.key
        }
    }

    func query(scope: GameConfigScope, key: String) -> SQLite.Table {
        Self.romConfigTable.filter(Self.configScope == scope.rawValue && Self.key == key)
    }

    func getOptionalValue<T: Value>(column: SQLite.Expression<T?>) -> T? {
        guard let key = resolveKey() else {
            return nil
        }

        let db = RetroRomPersistence.sqlite
        let alice = query(scope: scope, key: key)
        do {
            return try db.pluck(alice)?[column]
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return nil
        #endif
        }
    }

    @discardableResult
    func setOptionalValue<T: Value>(column: SQLite.Expression<T?>, value: T?) -> Bool {
        guard let key = resolveKey() else {
            return false
        }

        let db = RetroRomPersistence.sqlite
        let alice = query(scope: scope, key: key)
        do {
            if try db.pluck(alice) != nil {
                let sql = alice.update(
                    Self.updateAt <- Date(),
                    column <- value
                )
                try db.run(sql)
            } else {
                let sql = Self.romConfigTable.insert(
                    Self.key <- key,
                    Self.configScope <- scope.rawValue,
                    Self.updateAt <- Date(),
                    column <- value
                )
                try db.run(sql)
            }
            return true
        } catch {
        #if DEBUG
            fatalError(error.localizedDescription)
        #else
            return false
        #endif
        }
    }
}

extension GameConfigSession {
    // v3
    static let key              = RetroRomPersistence.key
    static let updateAt         = RetroRomPersistence.updateAt
    static let configScope      = SQLite.Expression<String>("scope")
    static let threadEnabled    = SQLite.Expression<Bool?>("thread_enabled")
    static let fastForwardMultiplier = SQLite.Expression<Double?>("fast_forward_multiplier")

    // v4
    static let videoDriver         = SQLite.Expression<String?>("video_driver")
    static let audioDriver         = SQLite.Expression<String?>("audio_driver")
    static let muteOnFastForward   = SQLite.Expression<Bool?>("mute_on_fastforward")
    static let overlayTouchPlayer  = SQLite.Expression<Int?>("overlay_touch_player")
    static let inputBindingProfile = SQLite.Expression<Data?>("input_binding_profile")

    // v5
    static let toolbarLayout = SQLite.Expression<Data?>("toolbar_layout")
    static let overlayTurboTapLatch = SQLite.Expression<Bool?>("overlay_turbo_tap_latch")
    static let overlayTurboSpeed = SQLite.Expression<Int?>("overlay_turbo_speed")

    /*
     * key, configScope, updateAt
     * v3: threadEnabled, fastForwardMultiplier
     * v4: videoDriver, audioDriver, muteOnFastForward,
     *     overlayTouchPlayer, inputBindingProfile
     * v5: toolbarLayout, overlayTurboTapLatch, overlayTurboSpeed
     */
    static let romConfigTable   = SQLite.Table("romconfig")

    static func deleteGameConfig(_ key: String) throws {
        let db = RetroRomPersistence.sqlite
        let alice = Self.romConfigTable.filter(Self.key == key && Self.configScope == "game")
        try db.run(alice.delete())
    }
}
