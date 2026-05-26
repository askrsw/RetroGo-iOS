//
//  RetroRomFolderPageState.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/25.
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

import Combine
import Defaults
import RACoordinator

// MARK: - OrganizeMode

/// The four mutually-exclusive content-organization modes of the FolderPage.
///
/// Tree is now in the *same* family as byFolder / byCore / byTag — it's a
/// data-shape decision, not a visual layout. (That's the rewrite vs the
/// legacy `RetroRomHomePageState`, which split tree off into a separate
/// `homeBrowserType` axis.)
///
/// Raw values match the order shown in the config menu so a future
/// "remember last mode" feature can persist a tiny integer.
enum RetroRomOrganizeMode: Int, CaseIterable, Equatable {
    case byFolder = 0
    case byCore   = 1
    case byTag    = 2
    case tree     = 3
}

// MARK: - ViewLayout

/// Cell-presentation choice within byFolder / GroupDetail modes. The
/// CoreList / TagList pages always render as a vertical list (no `icon`
/// equivalent) and Tree has its own fixed outline layout — both ignore
/// this property.
enum RetroRomViewLayout: Int, CaseIterable, Equatable {
    case icon = 0
    case list = 1
}

// MARK: - RetroRomFileSortType

/// Sort criterion for the current page's items. Same six cases the legacy
/// `RetroRomFileBrowser` exposed; raw values preserved so any code that
/// reads/writes the integer (Defaults, debug logging) stays interchangeable
/// with old call sites during the transition.
enum RetroRomFileSortType: Int, CaseIterable, Equatable {
    case fileNameAsc  = 0
    case fileNameDesc = 1
    case lastPlay     = 2
    case addDateDesc  = 3
    case addDateAsc   = 4
    case playTime     = 5
}

// MARK: - RetroRomGameGroupKey

/// Identifies a single group within a byCore / byTag view.
///
/// Carries the resolved entity (`EmuCoreInfoItem` / `RetroRomFileTag`) —
/// not just an id — so downstream code (detail VC title, header view,
/// tag-color resolution, etc.) doesn't need a second lookup.
///
/// Case names use the `byCore` / `byTag` prefix to match the surrounding
/// vocabulary (`OrganizeMode.byCore`, "By Core" menu item, etc.) and read
/// naturally at the call site:
/// ```swift
/// case .byCore(let core): …
/// case .byTag(let tag):   …
/// ```
enum RetroRomGameGroupType {
    case byCore(_ core: EmuCoreInfoItem)
    case byTag(_ tag: RetroRomFileTag)
}

// MARK: - RetroRomFolderPageState

/// Single source of truth for FolderPage-wide state. Replaces the legacy
/// `RetroRomHomePageState`.
///
/// ## Why Combine?
///
/// Multiple `RetroRomFolderHostViewController` instances are alive at the
/// same time — every folder you've drilled into stays on the navigation
/// stack. They all need to react when the user toggles organize / sort /
/// layout in the config menu. The cleanest way to fan out an event to
/// "all live hosts" is a publisher each one subscribes to from `viewDidLoad`
/// (strategy A: every instance subscribes; nobody is special).
///
/// Each writable property is `@Published`, so a host subscribes with
/// ```swift
/// state.$organizeMode
///     .dropFirst()                // skip the current-value replay
///     .receive(on: DispatchQueue.main)
///     .sink { [weak self] mode in
///         self?.applyOrganizeMode(mode)
///     }
///     .store(in: &cancellables)
/// ```
/// and `cancellables` are released on `deinit` — no manual teardown.
///
/// ## Persistence
///
/// Each `@Published` property has a `didSet` that writes the new value to
/// `Defaults`. Init bypasses didSet by assigning the underlying `_x`
/// directly — so loading from disk doesn't trigger a redundant write-back.
///
/// We deliberately do NOT migrate the legacy `home_*` keys. Users get a
/// fresh default state once on the version that introduces this file;
/// the cost is one user-facing reset of mode/sort, well worth the
/// implementation simplicity.
final class RetroRomFolderPageState: ObservableObject {

    static let shared = RetroRomFolderPageState()

    // MARK: Published state

    @Published var organizeMode: RetroRomOrganizeMode {
        didSet {
            Defaults[.folderPageOrganizeMode] = organizeMode.rawValue
        }
    }

    @Published var viewLayout: RetroRomViewLayout {
        didSet {
            Defaults[.folderPageViewLayout] = viewLayout.rawValue
        }
    }

    @Published var sortType: RetroRomFileSortType {
        didSet {
            Defaults[.folderPageSortType] = sortType.rawValue
        }
    }

    // MARK: One-shot events

    /// Fires when the user taps the "Refresh" action in the config menu.
    /// Hosts all subscribe (strategy A), but only the visible host should
    /// actually re-fetch + scroll-to-top — the convention is to gate the
    /// sink with `navigationController?.topViewController === self`.
    /// Background hosts ignore the tick.
    ///
    /// Modeled as a `PassthroughSubject` rather than a `@Published Date`
    /// or similar because refresh has no value to carry — it's a verb,
    /// not a state. Subscribers don't get a current-value replay on
    /// subscription, which is correct: a fresh host coming online
    /// shouldn't auto-refresh.
    let refreshRequested = PassthroughSubject<Void, Never>()

    /// Fires after a `RetroRomFileManager.moveItem` completes
    /// successfully. The **source** host updates its own UI directly
    /// through `moveItem`'s `onSuccess` callback (cell animates out);
    /// this subject exists to inform the **destination** host that an
    /// item just landed under its folder — without it, a host sitting
    /// in the nav stack stays stale until the user manually refreshes.
    ///
    /// Modeled as a Combine subject rather than a NotificationCenter
    /// post so it shares the same observation idiom as `sortType` /
    /// `refreshRequested` (the host's `observeStateChanges` already
    /// wires up `state.foo.sink { ... }` for everything else).
    ///
    /// All hosts subscribe (strategy A). The destination host filters
    /// on `event.destinationFolderKey == folderKey` and fans the event
    /// out to its subview; every other host's sink no-ops.
    let itemMoved = PassthroughSubject<ItemMovedEvent, Never>()

    /// Payload for `itemMoved`. A small struct beats a tuple here — the
    /// sink site reads `event.item` / `event.destinationFolderKey` with
    /// zero ambiguity, and adding a future field (e.g. source folder
    /// key for cross-folder analytics) doesn't break call sites.
    struct ItemMovedEvent {
        let item: RetroRomBaseItem
        let destinationFolderKey: String
    }

    let itemDeleted = PassthroughSubject<RetroRomBaseItem, Never>()

    // MARK: Init

    private init() {
        // Use the underscore-prefixed `Published(wrappedValue:)` form so the
        // initial load from Defaults DOES NOT fire `didSet` — we don't want
        // launch to write back the same value we just read.
        let rawOrganize = Defaults[.folderPageOrganizeMode] ?? RetroRomOrganizeMode.byFolder.rawValue
        let rawLayout   = Defaults[.folderPageViewLayout]   ?? RetroRomViewLayout.icon.rawValue
        let rawSort     = Defaults[.folderPageSortType]     ?? RetroRomFileSortType.fileNameAsc.rawValue

        _organizeMode = Published(wrappedValue: RetroRomOrganizeMode(rawValue: rawOrganize) ?? .byFolder)
        _viewLayout   = Published(wrappedValue: RetroRomViewLayout(rawValue: rawLayout)     ?? .icon)
        _sortType     = Published(wrappedValue: RetroRomFileSortType(rawValue: rawSort) ?? .fileNameAsc)
    }
}
