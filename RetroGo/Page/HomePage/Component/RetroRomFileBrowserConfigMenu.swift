//
//  RetroRomFileBrowserConfigMenu.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/23.
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
import Combine
import ObjcHelper
import RACoordinator

/// `UIMenu` factory for the FolderPage's options bar button
/// (the `slider.horizontal.3` icon in the nav bar).
///
/// ## Targetless design
///
/// The factory takes **no host VC parameter**. Every action mutates
/// `RetroRomFolderPageState.shared` (a Combine `ObservableObject`); all
/// live `RetroRomFolderHostViewController` instances subscribe to the
/// resulting `@Published` change and update independently. This drops the
/// menu's coupling to any particular host — the same `UIMenu` is safe to
/// install on any number of bar buttons across the nav stack.
///
/// ## Section order
///
/// 1. **Organize** — Folder / Core / Tag / Tree (always shown)
/// 2. **View layout** — Icon / List (hidden in Tree mode, which dictates
///    its own outline layout)
/// 3. **Sort** — Name / Last Play / Add Date / Game Duration
///    (Name and Add Date carry a trailing arrow showing direction)
/// 4. **Refresh** — one-shot tick on `state.refreshRequested`
///
/// Built eagerly from current `RetroRomFolderPageState`. Hosts that
/// observe state changes (via Combine) must reassign the bar button's
/// `menu` with a fresh `make()` result whenever organize / layout / sort
/// changes — otherwise checkmarks and the View Layout section visibility
/// will go stale.
///
/// We previously wrapped the children in `UIDeferredMenuElement.uncached`
/// to avoid manual invalidation, but on iOS 17+ that triggers a benign
/// but noisy `-[UIContextMenuInteraction updateVisibleMenuWithBlock:]
/// while no context menu is visible` warning every time a host with this
/// menu attached is laid out. Eager build sidesteps that.
enum RetroRomFileBrowserConfigMenu {

    /// Build the menu attached to the options bar-button.
    static func make() -> UIMenu {
        UIMenu(children: buildSections())
    }
}

// MARK: - Section assembly

private extension RetroRomFileBrowserConfigMenu {

    static func buildSections() -> [UIMenuElement] {
        // Defensive: if RetroArch hasn't finished booting yet, present an
        // empty menu — mode switches and sorts would write to state but
        // the host might not be ready to react.
        guard RetroArchX.shared().initialized else { return [] }

        let state = RetroRomFolderPageState.shared
        var sections: [UIMenuElement] = [organizeSection(state: state)]

        // View layout meaningless in tree mode (tree has its own layout).
        if state.organizeMode != .tree {
            sections.append(viewLayoutSection(state: state))
        }

        sections.append(sortSection(state: state))
        sections.append(refreshAction())
        return sections
    }
}

// MARK: - Organize section

private extension RetroRomFileBrowserConfigMenu {

    /// Folder / Core / Tag / Tree — the four mutually-exclusive ways to
    /// organize the library. Selection state reads directly from
    /// `state.organizeMode`; user picks just write a new value, and the
    /// `@Published` change propagates to all hosts.
    static func organizeSection(state: RetroRomFolderPageState) -> UIMenu {
        let current = state.organizeMode
        return UIMenu(options: .displayInline, children: [
            organizeAction(.byFolder,
                           titleKey: "homepage_config_by_folder",
                           image: UIImage(systemName: "folder"),
                           current: current),
            organizeAction(.byCore,
                           titleKey: "homepage_config_by_core",
                           image: UIImage(systemName: "cpu"),
                           current: current),
            organizeAction(.byTag,
                           titleKey: "Homepage_config_by_tag",     // legacy capital "H" key
                           image: UIImage(systemName: "tag"),
                           current: current),
            organizeAction(.tree,
                           titleKey: "homepage_config_tree",
                           image: IconRender.shared.treeSymbol(size: CGSize(width: 24, height: 24)),
                           current: current)
        ])
    }

    static func organizeAction(_ mode: RetroRomOrganizeMode,
                               titleKey: String,
                               image: UIImage?,
                               current: RetroRomOrganizeMode) -> UIAction {
        UIAction(
            title: Bundle.localizedString(forKey: titleKey),
            image: image,
            state: current == mode ? .on : .off
        ) { _ in
            Vibration.selection.vibrate()
            guard current != mode else { return }
            RetroRomFolderPageState.shared.organizeMode = mode
        }
    }
}

// MARK: - View layout section

private extension RetroRomFileBrowserConfigMenu {

    static func viewLayoutSection(state: RetroRomFolderPageState) -> UIMenu {
        let current = state.viewLayout
        return UIMenu(options: .displayInline, children: [
            layoutAction(.icon,
                         titleKey: "homepage_config_icon",
                         image: UIImage(systemName: "square.grid.2x2"),
                         current: current),
            layoutAction(.list,
                         titleKey: "homepage_config_list",
                         image: UIImage(systemName: "list.bullet"),
                         current: current)
        ])
    }

    static func layoutAction(_ layout: RetroRomViewLayout,
                             titleKey: String,
                             image: UIImage?,
                             current: RetroRomViewLayout) -> UIAction {
        UIAction(
            title: Bundle.localizedString(forKey: titleKey),
            image: image,
            state: current == layout ? .on : .off
        ) { _ in
            Vibration.selection.vibrate()
            guard current != layout else { return }
            RetroRomFolderPageState.shared.viewLayout = layout
        }
    }
}

// MARK: - Sort section

extension RetroRomFileBrowserConfigMenu {

    enum SortDirection { case asc, desc }

    /// Build the four sort `UIAction`s reflecting the current global
    /// `sortType`. Exposed (not `private`) so both wrappers can share
    /// one source of truth:
    /// - The nav-bar config menu wraps these in an inline section
    ///   (`UIMenu(options: .displayInline, children: sortActions())`).
    /// - The blank-area menu wraps them in a titled non-inline submenu
    ///   (`UIMenu(title: "Sort By", children: sortActions())`).
    static func sortActions() -> [UIAction] {
        let sort = RetroRomFolderPageState.shared.sortType

        // Resolve the current direction-bearing sort field, if any.
        let nameDirection: SortDirection? = sort == .fileNameAsc  ? .asc
                                          : sort == .fileNameDesc ? .desc : nil
        let addDateDirection: SortDirection? = sort == .addDateAsc  ? .asc
                                             : sort == .addDateDesc ? .desc : nil

        return [
            UIAction(
                title: titleWithDirection(key: "homepage_config_name",
                                          direction: nameDirection),
                // `textformat.abc` localizes to "甲乙丙" / "あ" / etc. by
                // default. Lock to English so the icon stays a stable
                // alphabetical metaphor across system languages.
                image: UIImage(systemName: "textformat.abc",
                               withConfiguration: UIImage.SymbolConfiguration(locale: Locale(identifier: "en"))),
                state: nameDirection != nil ? .on : .off
            ) { _ in
                Vibration.selection.vibrate()
                let next: RetroRomFileSortType
                switch nameDirection {
                case .asc:  next = .fileNameDesc
                case .desc: next = .fileNameAsc
                case nil:   next = .fileNameAsc
                }
                RetroRomFolderPageState.shared.sortType = next
            },
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_last_play"),
                image: UIImage(systemName: "gamecontroller"),
                state: sort == .lastPlay ? .on : .off
            ) { _ in
                Vibration.selection.vibrate()
                guard sort != .lastPlay else { return }
                RetroRomFolderPageState.shared.sortType = .lastPlay
            },
            UIAction(
                title: titleWithDirection(key: "homepage_config_add_date",
                                          direction: addDateDirection),
                image: UIImage(systemName: "calendar.badge.plus"),
                state: addDateDirection != nil ? .on : .off
            ) { _ in
                Vibration.selection.vibrate()
                let next: RetroRomFileSortType
                switch addDateDirection {
                case .asc:  next = .addDateDesc
                case .desc: next = .addDateAsc
                case nil:   next = .addDateDesc   // first selection: newest first
                }
                RetroRomFolderPageState.shared.sortType = next
            },
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_game_duration"),
                image: UIImage(systemName: "stopwatch"),
                state: sort == .playTime ? .on : .off
            ) { _ in
                Vibration.selection.vibrate()
                guard sort != .playTime else { return }
                RetroRomFolderPageState.shared.sortType = .playTime
            }
        ]
    }
}

private extension RetroRomFileBrowserConfigMenu {

    /// Nav-bar config menu wrapper: actions surface as an inline section.
    static func sortSection(state: RetroRomFolderPageState) -> UIMenu {
        UIMenu(options: .displayInline, children: sortActions())
    }

    /// Append a direction arrow to a sort title. The arrow doubles as the
    /// "selected" affordance — the row also carries a checkmark (.on),
    /// but the arrow shows which DIRECTION is currently active.
    static func titleWithDirection(key: String, direction: SortDirection?) -> String {
        let base = Bundle.localizedString(forKey: key)
        switch direction {
        case .asc:  return "\(base) ↑"
        case .desc: return "\(base) ↓"
        case nil:   return base
        }
    }
}

// MARK: - Refresh action

private extension RetroRomFileBrowserConfigMenu {

    /// Stateless tick on `state.refreshRequested`. The visible host (top
    /// of the active nav stack) gates its subscription on visibility and
    /// re-fetches + scrolls to top; non-visible hosts in the stack ignore
    /// the tick.
    static func refreshAction() -> UIAction {
        UIAction(
            title: Bundle.localizedString(forKey: "refresh"),
            image: UIImage(systemName: "arrow.clockwise")
        ) { _ in
            Vibration.selection.vibrate()
            RetroRomFolderPageState.shared.refreshRequested.send()
        }
    }
}
