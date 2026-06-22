//
//  GameToolbarAction.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/2.
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

/// A customizable button on the in-game top toolbar.
///
/// `close` (leftmost) and `more` (rightmost) are fixed and intentionally not
/// part of this set — only the actions in between can be pinned to the bar or
/// collapsed into the More menu. `pauseResume` is a DEBUG-only developer tool
/// and is likewise excluded from customization (it always lives in More).
///
/// The raw value is the persisted identity; do not rename existing cases.
enum GameToolbarAction: String, CaseIterable {
    // Declaration order is the *within-tier* default order: ties in `priority`
    // are broken by the order below. (`setting` after `restart` keeps it last
    // in the default pinned set, nearest the More button.) Reordering cases is
    // safe — the raw value strings are the persisted identity.
    case lockLandscape
    case cheat
    case saveState
    case loadState
    case setting
    // Declared after the first `maxPinned` so it defaults into the More menu
    // (netplay is a low-frequency feature). `.medium` priority keeps it in the
    // overflow for already-customized users too.
    case netplay
    case restart
    case snap
    case mute

    /// Maximum number of actions that can be pinned to the bar at once.
    static let maxPinned = 5

    /// Coarse default-placement weight (see `ToolbarPriority`). Multiple actions may
    /// share a tier; declaration order breaks ties within a tier. This drives
    /// both the default layout and where a newly added action lands.
    var priority: ToolbarPriority {
        switch self {
        case .lockLandscape, .setting, .cheat: return .high
        case .saveState, .loadState,  .restart, .netplay: return .medium
        case .snap, .mute: return .low
        }
    }

    /// Localized title used for the More-menu entry and the layout editor row.
    /// `mute` is dynamic and resolved by the caller; this returns the
    /// "will mute" wording as a sensible default.
    var title: String {
        switch self {
        case .saveState: return Bundle.localizedString(forKey: "gamepage_save_state")
        case .loadState: return Bundle.localizedString(forKey: "gamestate_load_state")
        case .snap:      return Bundle.localizedString(forKey: "gamepage_toolbar_snapshot")
        case .mute:          return Bundle.localizedString(forKey: "gamepage_toolbar_mute")
        case .lockLandscape: return Bundle.localizedString(forKey: "gamepage_toolbar_lock_landscape")
        case .setting:       return Bundle.localizedString(forKey: "gamepage_toolbar_settings")
        case .restart:   return Bundle.localizedString(forKey: "gamepage_toolbar_restart")
        case .cheat:     return Bundle.localizedString(forKey: "cheat_title")
        case .netplay:   return Bundle.localizedString(forKey: "gamepage_toolbar_netplay")
        }
    }

    /// Default SF Symbol for the bar button / menu entry. `mute` is dynamic and
    /// resolved by the caller; this returns the "unmuted" symbol.
    var systemImageName: String {
        switch self {
        case .saveState: return "arrowshape.down.circle"
        case .loadState: return "arrowshape.up.circle"
        case .snap:      return "camera.circle"
        case .mute:          return "speaker.wave.2.circle"
        case .lockLandscape: return "lock.rotation"
        case .setting:       return "gear.circle"
        case .restart:   return "arrow.clockwise.circle"
        case .cheat:     return "star.circle"
        case .netplay:   return "network"
        }
    }
}

/// Coarse placement weight for toolbar actions. `high` lands at the front of the
/// pinned bar; `medium` at the front of the More overflow; `low` at its end.
/// Shared across actions on purpose — fine ordering comes from `GameToolbarAction`'s
/// declaration order within a tier.
enum ToolbarPriority {
    case high
    case medium
    case low

    fileprivate var rank: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        }
    }
}

extension GameToolbarAction {
    /// All actions in priority order: by tier (high → low), ties broken by
    /// declaration order. Used by `reconcile` to place a *missing* action when
    /// merging into a customized layout — NOT for the default layout, which
    /// follows declaration order (`defaultSplit`).
    static var canonicalOrder: [GameToolbarAction] {
        allCases.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.priority.rank, r = rhs.element.priority.rank
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// The default (un-customized) split: the first `maxPinned` actions in
    /// **declaration order** are pinned, the rest overflow into the More menu.
    /// Declaration order is the authored default layout; `priority` does not
    /// reorder it (priority only governs `reconcile` insertion).
    static func defaultSplit() -> (pinned: [GameToolbarAction], overflow: [GameToolbarAction]) {
        let ordered = Array(allCases)
        return (Array(ordered.prefix(maxPinned)), Array(ordered.dropFirst(maxPinned)))
    }

    /// Reconciles a stored (possibly stale) layout with the current action set:
    /// drops duplicates/overlaps and inserts any action missing from both lists
    /// by its `priority` — high to the pinned front (spilling the pinned tail to
    /// the overflow front if over `maxPinned`), medium to the overflow front,
    /// low to the overflow end. Together the result covers every action once.
    static func reconcile(
        pinned: [GameToolbarAction],
        overflow: [GameToolbarAction]
    ) -> (pinned: [GameToolbarAction], overflow: [GameToolbarAction]) {
        var seen = Set<GameToolbarAction>()
        var resultPinned = pinned.filter { seen.insert($0).inserted }
        var resultOverflow = overflow.filter { seen.insert($0).inserted }

        let missing = canonicalOrder.filter { !seen.contains($0) }
        resultPinned = missing.filter { $0.priority == .high } + resultPinned
        resultOverflow = missing.filter { $0.priority == .medium }
            + resultOverflow
            + missing.filter { $0.priority == .low }

        if resultPinned.count > maxPinned {
            let spill = resultPinned.suffix(resultPinned.count - maxPinned)
            resultPinned = Array(resultPinned.prefix(maxPinned))
            resultOverflow = Array(spill) + resultOverflow
        }
        return (resultPinned, resultOverflow)
    }
}
