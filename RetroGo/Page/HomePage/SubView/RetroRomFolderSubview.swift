//
//  RetroRomFolderSubview.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/24.
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

// `GameGroupKey` lives in `RetroRomFolderPageState.swift` alongside the
// other state/data shapes (`OrganizeMode`, `ViewLayout`, etc.).

// MARK: - RetroRomFolderSubview

/// The contract for any content-rendering view installed inside
/// `RetroRomFolderHostViewController`.
///
/// Each concrete subview owns the on-screen presentation for exactly one
/// `(folderKey, organize mode)` combination — byFolder, byCore-list,
/// byTag-list, tree, etc. The host instantiates the right subview for
/// the current global mode, installs it, calls `reload()`, and forwards
/// notifications by calling the matching method.
///
/// ## Design constraints
///
/// - **No modal presentation, no navigation.** Subviews do not call
///   `present(...)` or touch `navigationController`. All such actions
///   bubble up through `RetroRomFolderSubviewDelegate`.
/// - **No NotificationCenter subscriptions.** The host is the single
///   observer; it calls into the subview when something relevant fires.
///   This keeps subviews stateless w.r.t. global events and easy to swap
///   without leaking observers.
/// - **No reads/writes to `RetroRomFolderPageState.shared`.** The host
///   resolves global state into concrete inputs (folderKey, sort order
///   already applied to data, etc.) before handing them to the subview.
///   The one exception is the sort type — subviews read it directly when
///   ordering their `subItems` because it's stable across the subview's
///   lifetime, and re-reading is cheaper than threading it through every
///   reload call.
/// - **Idempotent `reload()`.** Every call must re-fetch and re-render
///   from scratch. No assumptions about prior state.
protocol RetroRomFolderSubview: UIView {

    // MARK: Properties

    /// Weak back-reference to the host. Captured weakly to prevent the
    /// retain cycle (host owns subview, subview reports back to host).
    var delegate: RetroRomFolderSubviewDelegate? { get set }

    /// The scope this subview is rendering. For byFolder it's the
    /// directly-displayed folder; for byCore/byTag/tree it's the
    /// subtree root.
    var folderKey: String { get }

    /// Whether the subview's current data set is effectively empty —
    /// the host uses this to decide whether to overlay an empty-state
    /// view (`RetroRomEmptyTipView`). Implementations should compute
    /// this from the freshly-loaded data, not cache stale results.
    var couldShowEmptyTip: Bool { get }

    // MARK: Required lifecycle hooks

    /// Re-fetch data and re-render. Called by the host on:
    /// - initial install
    /// - `viewWillAppear` (returning from a pushed child)
    /// - `.romCountChanged`, `.retroFileImported`, `.retroFolderImported`
    ///   notifications (when no finer-grained method is implemented)
    /// - sort criterion change
    ///
    /// Must be idempotent and synchronous (or signal completion via
    /// `subviewDidChangeContent`). Implementations that perform async
    /// work should show their own in-flight indicator and call back when
    /// the data settles.
    func reload()

    /// Re-render every localizable string in the subview's hierarchy.
    /// Triggered when the user toggles the in-app language. The host
    /// observes `.languageChanged` and fans out to its current subview.
    func languageChanged()

    // MARK: Optional fine-grained updates

    /// Apply an incremental insert for newly-imported file items. Used
    /// when the host wants to avoid the visual flash of a full reload
    /// after a large import.
    ///
    /// Default implementation falls back to `reload()`. Subviews where
    /// implementing a true incremental insert is non-trivial (tree
    /// outline, byCore grouping that may shift bucket counts) are
    /// expected to keep the default.
    func fileItemImported(_ keys: [String])

    /// Same idea as `fileItemImported`, for folder-shaped imports.
    /// `itemKeys` are the keys inserted under `folderKey`.
    func folderItemImported(folderKey: String, itemKeys: [String])

    /// Remove a deleted item from the visible data set.
    func itemDeleted(_ item: RetroRomBaseItem)

    /// A tag's color was changed by the user. Subviews displaying tag
    /// dots / chips should refresh the affected cells. The tag's title
    /// is unchanged, so cell text doesn't need recomputing.
    func fileTagColorChanged(tagId: Int)

    /// A file's preferred core was reassigned by the user (long-press
    /// → Assign Core → pick a different one). Either or both of
    /// `newCoreId` / `oldCoreId` may be non-nil:
    ///
    /// - `newCoreId` is non-nil when the newly-assigned core is NOT
    ///   already in the file's extension-derived core set — i.e., the
    ///   file is gaining membership in a section it wasn't in before.
    ///   byCore subviews should add the file under this section.
    /// - `oldCoreId` is non-nil when the previous preferred core was
    ///   NOT in the file's extension-derived core set — i.e., the file
    ///   was previously displayed under that section solely because of
    ///   the prefer-core assignment, and now needs to be removed from
    ///   it.
    ///
    /// `RetroRomFileItem.assignCore(_:)` posts `.fileCoreAssigned`
    /// only when at least one of these is non-nil; the host bridges
    /// the notification's userInfo into this call.
    ///
    /// Default falls back to no-op — most subviews (icon / list /
    /// tree in byFolder mode) don't render core-dependent content, so
    /// the assignment has no visible effect on them. byCore overrides
    /// to surgically update the affected sections.
    func fileCoreAssigned(_ file: RetroRomFileItem,
                          newCoreId: String?,
                          oldCoreId: String?)

    /// A file's tag assignments changed (long-press → Tags → pick).
    /// `added` and `removed` are sets of tag IDs that the file gained /
    /// lost. Bridges from `.fileTagFileChanged` notification. Default
    /// no-op — only byTag subviews need to act on this.
    func fileTagsChanged(_ file: RetroRomFileItem,
                         added: Set<Int>,
                         removed: Set<Int>)

    /// A tag entity was deleted. Bridges from `.fileTagDeleted`.
    /// Default no-op — only byTag subviews care (they need to drop
    /// the corresponding section).
    func fileTagDeleted(_ tag: RetroRomFileTag)

    /// A tag's title was changed. Bridges from `.fileTagTitleChanged`.
    /// Default no-op — only byTag subviews care (they need to refresh
    /// the affected section header).
    func fileTagTitleChanged(_ tag: RetroRomFileTag)

    /// An item just arrived under this subview's `folderKey` via a
    /// move operation initiated in a different host. The host filters
    /// on the destinationFolderKey before calling this; subviews can
    /// assume the item belongs in their visible scope.
    ///
    /// **Idempotency requirement**: implementations MUST handle the
    /// case where the item is already in their view (the
    /// `state.itemMoved` Combine broadcast may overlap with the
    /// initiating host's own `itemDeleted(_:)` callback in
    /// edge cases — particularly tree mode where the same host can
    /// be both the source and destination).
    ///
    /// Default falls back to `reload()` for subviews where "an item
    /// arrived" doesn't have a precise insertion point.
    func itemMovedIn(_ item: RetroRomBaseItem)

    /// **Pure data step** — re-sort the internal `items` array by the
    /// current global sort criterion (`RetroRomFolderPageState.shared.sortType`).
    ///
    /// Does **NOT** touch the UI. No snapshot apply, no animation, no
    /// cell work. Callers that also want the on-screen order to refresh
    /// follow up with `applyData(animated:)`.
    ///
    /// Cheap enough to call on **every** host in the nav stack when sort
    /// changes — even background hosts behind a covering VC. Keeping their
    /// `items` arrays in sync means a later `applyData(animated: false)`
    /// from `viewWillAppear` produces the correct order without re-fetching.
    ///
    /// Default implementation falls back to `reload()` for subviews where
    /// in-place reorder isn't well-defined (tree outline; byCore/byTag
    /// groupings whose section partitions might also need adjusting).
    func sort()

    /// **UI sync step** — push the current internal data state to the
    /// rendered view. For diffable-backed subviews, this means building
    /// a fresh snapshot from the current `items` array and calling
    /// `dataSource.apply(...)`. Does not re-fetch or re-sort.
    ///
    /// - parameter animated: Whether the diff-apply animates.
    ///   - `true`: cells slide / fade to their new positions. Pair with
    ///     visible-host state changes (sort, layout) where the user
    ///     should see the transition.
    ///   - `false`: snapshot applies instantly, no animation. Pair with
    ///     `viewWillAppear` of a host returning from a covering child —
    ///     no transition is appropriate when the page is just coming
    ///     back into view.
    ///
    /// ## Typical pairings
    ///
    /// | Trigger                                    | Calls                                |
    /// |--------------------------------------------|--------------------------------------|
    /// | sort changed AND host is visible           | `sort()` + `applyData(animated: true)` |
    /// | sort changed AND host is background        | `sort()` only (no UI work)           |
    /// | `viewWillAppear` (returning from a child)  | `applyData(animated: false)`         |
    ///
    /// Skipping the UI step for background hosts is the central CPU /
    /// battery win of this split — we never animate work the user
    /// can't see.
    ///
    /// Default implementation falls back to `reload()`.
    func applyData(animated: Bool)

    /// Insert a freshly-created folder into the visible item list and
    /// scroll it into view. Used by the "New Folder" blank-area menu
    /// action: the host's `RetroRomFileManager.createNewFolder(in:)`
    /// returns the new folder, the subview makes it visible, and the
    /// host follows up with a rename alert.
    ///
    /// Implementations should append to the **tail** regardless of the
    /// current sort criterion — the user just made this folder, they
    /// want to see it land somewhere predictable. The next reload /
    /// `viewWillAppear` will re-sort it into its proper spot.
    ///
    /// Default implementation falls back to `reload()` for subviews
    /// where "where does the new folder appear" doesn't have a clean
    /// answer (byCore / byTag / tree).
    func appendNewFolder(_ folder: RetroRomFolderItem)
}

// MARK: - Default optional implementations

/// All optional methods default to a full `reload()` so adopting types
/// only override the ones where an incremental update is cheaper.
extension RetroRomFolderSubview {
    func fileItemImported(_ keys: [String]) {
        reload()
    }

    func folderItemImported(folderKey: String, itemKeys: [String]) {
        reload()
    }

    func itemDeleted(_ item: RetroRomBaseItem) {
        reload()
    }

    func fileTagColorChanged(tagId: Int) {
        reload()
    }

    func itemMovedIn(_ item: RetroRomBaseItem) {
        reload()
    }

    /// Default no-op: assign-core changes don't affect cell visibility
    /// in icon / list / tree subviews (those show the file regardless
    /// of which core it runs on). byCore overrides for surgical
    /// section updates.
    func fileCoreAssigned(_ file: RetroRomFileItem,
                          newCoreId: String?,
                          oldCoreId: String?) {
        // Intentionally empty.
    }

    func fileTagsChanged(_ file: RetroRomFileItem,
                         added: Set<Int>,
                         removed: Set<Int>) {
        // Intentionally empty. byTag overrides.
    }

    func fileTagDeleted(_ tag: RetroRomFileTag) {
        // Intentionally empty. byTag overrides.
    }

    func fileTagTitleChanged(_ tag: RetroRomFileTag) {
        // Intentionally empty. byTag overrides.
    }

    /// Defaults to `reload()` — safe fallback for subviews where in-place
    /// reorder isn't well-defined.
    func sort() {
        reload()
    }

    /// Defaults to `reload()` for subviews that don't have a clean
    /// "insert at the tail" semantic (byCore / byTag / tree groupings).
    func appendNewFolder(_ folder: RetroRomFolderItem) {
        reload()
    }

    /// Defaults to `reload()` — safe fallback for subviews that don't have
    /// a snapshot-style data source to apply.
    func applyData(animated: Bool) {
        reload()
    }
}

// MARK: - RetroRomFolderSubviewDelegate

/// The contract a host VC fulfills to receive user actions from any
/// `RetroRomFolderSubview` it owns. All methods are passed the source
/// subview as a sanity-check / multi-subview discriminator, even though
/// in practice the host holds exactly one subview at a time.
///
/// `AnyObject` constraint is required so the protocol can be referenced
/// as a `weak var` — see the cycle note on `RetroRomFolderSubview.delegate`.
protocol RetroRomFolderSubviewDelegate: AnyObject {

    // MARK: Navigation events

    /// User tapped a folder cell in a byFolder subview. The host should
    /// push a new `RetroRomFolderHostViewController` rooted at
    /// `folder.key` onto the navigation stack.
    func subview(_ subview: RetroRomFolderSubview,
                 didTapFolder folder: RetroRomFolderItem)

    /// User tapped a file cell. The host should launch the game — if
    /// the file has a runnable core, start immediately; otherwise
    /// present a core selector. Mirrors the legacy
    /// `RetroRomFileBrowser.startGame(_:core:)` flow.
    func subview(_ subview: RetroRomFolderSubview,
                 didTapFile file: RetroRomFileItem)

    /// User tapped a file cell **inside a specific core's section**
    /// — byCore mode surface only. The (file, core) association is
    /// explicit in the UI (the user picked a row IN this core's
    /// section), so the host should launch that core directly rather
    /// than re-resolving via `getRunningCore` (which might pick a
    /// different core when the file supports multiple).
    ///
    /// `core == nil` means the user tapped a row in the "no recognized
    /// core" bucket. Host should fall back to the standard launch
    /// path (`launchGame(file)`), which presents the core picker.
    ///
    /// Default forwards to `didTapFile(file:)`, so subviews that don't
    /// have a per-core context (icon, list, tree in byFolder mode)
    /// don't have to implement this.
    func subview(_ subview: RetroRomFolderSubview,
                 didTapFile file: RetroRomFileItem,
                 withPreferredCore core: EmuCoreInfoItem?)
    
    // MARK: Modal / contextual events

    /// User tapped the primary CTA on the empty-state overlay. The host
    /// should run the same flow as the nav-bar `+` button — present the
    /// import sheet, route the result through the document picker, and
    /// kick off the import with this subview's `folderKey` as the
    /// destination.
    func subviewDidTapEmptyStateCTA(_ subview: RetroRomFolderSubview)

    /// Build the context menu for a long-pressed item. Subview owns
    /// preview snapshotting (it has the cell); host owns the actions
    /// (rename / move / delete / assign-core / tag …) because those
    /// require alert presentation and file-manager calls.
    ///
    /// Returning `nil` suppresses the menu entirely — useful when the
    /// host knows the item is in a state where actions don't apply
    /// (e.g. mid-import).
    func subview(_ subview: RetroRomFolderSubview,
                 contextMenuForItem item: RetroRomBaseItem) -> UIMenu?

    /// Build the context menu for a long-press on the blank background
    /// (cell-free area within the subview's bounds). Mirrors `iOS Files`
    /// app's behavior: long-pressing empty space surfaces "Import…",
    /// "New Folder", and a "Sort By" submenu. Returning `nil` suppresses
    /// the menu entirely.
    ///
    /// Subview owns the gesture (a `UIContextMenuInteraction` on its
    /// `collectionView.backgroundView` or equivalent) but not the action
    /// content — the actions need host-level capabilities (modal
    /// presentation for the import sheet, mutating `RetroRomFileManager`,
    /// reading global sort state).
    func subviewContextMenuForBlankArea(_ subview: RetroRomFolderSubview) -> UIMenu?

    /// User dragged a file/folder cell and dropped it onto a folder cell
    /// in the same subview. The host runs the actual move through
    /// `RetroRomFileManager.moveItem(_:to:presentingVC:onSuccess:)` —
    /// which validates the destination (can't drop into a descendant,
    /// can't collide on name), shows the failure alert if needed, and
    /// toasts on success. On success the host calls back into the subview
    /// via `itemDeleted(_:)` so the dragged cell animates out of
    /// the current folder view (the item has physically moved to
    /// `dstFolder`, so its place in this folder no longer exists).
    ///
    /// Subview only owns the gesture / preview animation; it never calls
    /// `RetroRomFileManager` or presents alerts directly.
    func subview(_ subview: RetroRomFolderSubview,
                 didDropItem srcItem: RetroRomBaseItem,
                 intoFolder dstFolder: RetroRomFolderItem)

    // MARK: Coordination events

    /// Optional: subview signals that its visible content has changed,
    /// typically right after `reload()` settles. The host re-evaluates
    /// any out-of-subview UI tied to data — empty-state overlay
    /// visibility, item-count badges, etc. Default no-op.
    func subviewDidChangeContent(_ subview: RetroRomFolderSubview)
}

// MARK: - Default delegate implementations

extension RetroRomFolderSubviewDelegate {

    func subviewDidChangeContent(_ subview: RetroRomFolderSubview) {
        // Default no-op. Hosts that overlay an empty-state view or
        // surface a content-count somewhere should override this.
    }

    func subview(_ subview: RetroRomFolderSubview,
                 didDropItem srcItem: RetroRomBaseItem,
                 intoFolder dstFolder: RetroRomFolderItem) {
        // Default no-op. Hosts that opt in to drag-and-drop move
        // (the byFolder host) override this to run the actual move.
    }

    /// Default: forward to the no-core variant. Hosts that want to
    /// honor the explicit per-section core should override this
    /// method to launch the picked core directly.
    func subview(_ subview: RetroRomFolderSubview,
                 didTapFile file: RetroRomFileItem,
                 withPreferredCore core: EmuCoreInfoItem?) {
        self.subview(subview, didTapFile: file)
    }
}
