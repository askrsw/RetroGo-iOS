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
import ObjcHelper
import RACoordinator

/// `UIMenu` factory for the home-page file-browser "options" button
/// (the `slider.horizontal.3` icon in the nav bar). Replaces the legacy
/// custom popup `RetroRomFileBrowserConfigView` so the look, animations,
/// haptics, accessibility, and dismissal behavior come from UIKit for
/// free — matching the rest of the app's native-iOS design language.
///
/// Functional parity with the legacy view:
/// - **View mode** section (Icon / List / Tree) — single selection.
/// - **Organize by** section (By Folder / By Core / By Tag) — single
///   selection. Shown only when the view mode is NOT Tree (mirrors the
///   legacy `addSubViews()` conditional).
/// - **Sort** section (Name / Last Play / Add Date / Game Duration) —
///   single selection. Name and Add Date carry a trailing arrow that
///   reflects the current sort direction (↑ asc, ↓ desc).
/// - **Refresh** action — single tap, no state.
///
/// Implementation: the entire menu is wrapped in
/// `UIDeferredMenuElement.uncached`, which means the system rebuilds
/// the children every time the user opens the menu. That gives us
/// always-fresh checkmarks AND lets us conditionally include/exclude
/// the Organize section without any manual "updateState()" plumbing.
enum RetroRomFileBrowserConfigMenu {

    /// Build the menu attached to the options bar-button. `target` is
    /// captured weakly so the menu can't extend the home page's
    /// lifetime past dismissal.
    static func make(target: HomePageViewController) -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak target] completion in
                DispatchQueue.main.async {
                    Vibration.selection.vibrate()
                }

                // Side effect: dismiss the search keyboard if it's
                // active. The legacy ConfigView did this on present;
                // we replicate it here so the menu doesn't open with
                // a stale keyboard hovering behind it.
                target?.fileBrowser.resignKeyboardFocus()
                completion(buildSections(target: target))
            }
        ])
    }
}

// MARK: - Section assembly

private extension RetroRomFileBrowserConfigMenu {

    static func buildSections(target: HomePageViewController?) -> [UIMenuElement] {
        // Defensive: if RetroArch hasn't finished booting yet, present
        // an empty menu (matches the legacy `guard initialized` gate).
        guard let target = target, RetroArchX.shared().initialized else {
            return []
        }

        var sections: [UIMenuElement] = [
            viewModeSection(target: target)
        ]

        // Organize section hidden in tree mode — tree has its own
        // implicit hierarchy and doesn't take a separate grouping.
        if RetroRomHomePageState.shared.homeBrowserType != .tree {
            sections.append(organizeSection(target: target))
        }

        sections.append(sortSection(target: target))
        sections.append(refreshAction(target: target))

        return sections
    }

    static func viewModeSection(target: HomePageViewController) -> UIMenu {
        let current = RetroRomHomePageState.shared.homeBrowserType
        return UIMenu(options: .displayInline, children: [
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_icon"),
                image: UIImage(systemName: "square.grid.2x2"),
                state: current == .icon ? .on : .off
            ) { [weak target] _ in target?.iconOption() },
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_list"),
                image: UIImage(systemName: "list.bullet"),
                state: current == .list ? .on : .off
            ) { [weak target] _ in target?.listOption() },
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_tree"),
                image: UIImage(named: "Icon_tree"),
                state: current == .tree ? .on : .off
            ) { [weak target] _ in target?.treeOption() }
        ])
    }

    static func organizeSection(target: HomePageViewController) -> UIMenu {
        let current = RetroRomHomePageState.shared.homeOrganizeType
        return UIMenu(options: .displayInline, children: [
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_by_folder"),
                image: UIImage(systemName: "folder"),
                state: current == .byFolder ? .on : .off
            ) { [weak target] _ in target?.folderOption() },
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_by_core"),
                image: UIImage(systemName: "cpu"),
                state: current == .byCore ? .on : .off
            ) { [weak target] _ in target?.coreOption() },
            // Note: the localization key intentionally keeps the
            // legacy capital "H" ("Homepage_config_by_tag") — changing
            // it would orphan the existing translations.
            UIAction(
                title: Bundle.localizedString(forKey: "Homepage_config_by_tag"),
                image: UIImage(systemName: "tag"),
                state: current == .byTag ? .on : .off
            ) { [weak target] _ in target?.tagOption() }
        ])
    }

    static func sortSection(target: HomePageViewController) -> UIMenu {
        let sort = RetroRomHomePageState.shared.homeFileSortType

        // Resolve the current direction-bearing sort field, if any.
        let nameDirection:    SortDirection? = sort == .fileNameAsc ? .asc
                                             : sort == .fileNameDesc ? .desc : nil
        let addDateDirection: SortDirection? = sort == .addDateAsc ? .asc
                                             : sort == .addDateDesc ? .desc : nil

        return UIMenu(options: .displayInline, children: [
            UIAction(
                title: titleWithDirection(key: "homepage_config_name",
                                          direction: nameDirection),
                image: UIImage(systemName: "textformat.abc"),
                state: nameDirection != nil ? .on : .off
            ) { [weak target] _ in target?.nameOption() },
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_last_play"),
                image: UIImage(systemName: "gamecontroller"),
                state: sort == .lastPlay ? .on : .off
            ) { [weak target] _ in target?.lastPlayOption() },
            UIAction(
                title: titleWithDirection(key: "homepage_config_add_date",
                                          direction: addDateDirection),
                image: UIImage(systemName: "calendar.badge.plus"),
                state: addDateDirection != nil ? .on : .off
            ) { [weak target] _ in target?.addDateOption() },
            UIAction(
                title: Bundle.localizedString(forKey: "homepage_config_game_duration"),
                image: UIImage(systemName: "stopwatch"),
                state: sort == .playTime ? .on : .off
            ) { [weak target] _ in target?.gameDurationOption() }
        ])
    }

    static func refreshAction(target: HomePageViewController) -> UIAction {
        UIAction(
            title: Bundle.localizedString(forKey: "refresh"),
            image: UIImage(systemName: "arrow.clockwise")
        ) { [weak target] _ in target?.refresh() }
    }
}

// MARK: - Sort direction helper

private extension RetroRomFileBrowserConfigMenu {

    enum SortDirection { case asc, desc }

    /// Compose the menu-item title for a sort field whose direction
    /// matters. The arrow is appended to the localized base title so
    /// translations don't need extra direction-specific strings.
    ///
    /// Examples (zh-Hans): `"按名称 ↑"`, `"按添加日期 ↓"`.
    static func titleWithDirection(key: String, direction: SortDirection?) -> String {
        let base = Bundle.localizedString(forKey: key)
        switch direction {
        case .asc:  return "\(base) ↑"
        case .desc: return "\(base) ↓"
        case nil:   return base
        }
    }
}
