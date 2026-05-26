//
//  RetroRomFolderHostViewController.swift
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
import SnapKit
import Combine
import ObjcHelper
import RACoordinator

/// Single host VC for the new Files-app-style library page.
///
/// One instance per folder in the navigation stack: the tab root holds
/// folderKey `"root"`, every push into a subfolder creates a fresh
/// instance with that subfolder's key. The host owns:
///
/// - the nav bar (large title, `+` / `slider` bar buttons, config UIMenu)
/// - the currently-installed `RetroRomFolderSubview` (renders content)
/// - the optional `RetroRomEmptyTipView` overlay
/// - Combine subscriptions on `RetroRomFolderPageState` — mode / layout
///   / sort / refresh events fanning out to all live hosts (strategy A)
/// - all NotificationCenter observation (subview is stateless w.r.t.
///   global library events; host fans events out to subview methods)
/// - the routing for tap → push / launch and context-menu → modal flows
///
/// The subview is dumb: it renders + bubbles up taps. Everything that
/// requires a `UIViewController` (modal, push, alert) lives here.
final class RetroRomFolderHostViewController: UIViewController {

    // MARK: - Scope

    /// The folder this host VC represents. Stable for the VC's lifetime —
    /// changing folders means pushing a new host instance, not mutating
    /// this property.
    let folderKey: String

    // MARK: - Owned state

    /// Currently-installed subview. `nil` between init and `installSubview()`.
    private var subview: RetroRomFolderSubview?

    /// Optional overlay shown when the global library is empty.
    private var emptyTipView: RetroRomEmptyTipView?

    /// Combine subscriptions. Released automatically on `deinit`, so
    /// strategy A (every host subscribes) has no manual teardown cost.
    private var cancellables = Set<AnyCancellable>()

    /// Retained so state-change sinks can rebuild and reassign its
    /// `.menu`. The menu is eagerly built from `RetroRomFolderPageState`,
    /// so checkmarks and the View Layout section visibility need an
    /// explicit refresh whenever the underlying state changes.
    private var configBarButton: UIBarButtonItem?

    /// Custom navigation-bar `titleView` installed for non-root hosts.
    /// Root uses `prefersLargeTitles` + plain `navigationItem.title`
    /// (iOS Files browse-tab landing-page style); subfolders get this
    /// compact icon + name + chevron + folder-action menu title.
    ///
    /// `nil` on root hosts. Held so the Combine sinks for organize /
    /// sort changes can flip the leading icon and re-bind the menu
    /// without re-creating the view.
    private var folderTitleView: RetroRomFolderTitleView?

    // MARK: - Init

    init(folderKey: String = "root") {
        self.folderKey = folderKey
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        navigationController?.navigationBar.prefersLargeTitles = true

        // Root tab: large title (iOS Files browse-tab landing-page style).
        // Subfolders: compact title with a custom titleView showing
        // [organize icon] [folder name] [chevron] + folder-action menu.
        // `.automatic` would inherit large-title from the previous VC
        // and propagate it through every push — explicit per-VC mode
        // is required to get the "large at root, small below" pattern.
        if folderKey == "root" {
            navigationItem.largeTitleDisplayMode = .always
        } else {
            navigationItem.largeTitleDisplayMode = .never
            installFolderTitleView()
        }

        updateNavigationTitle()
        configNavigationBarButtonItems()
        installSubview()
        observeNotifications()
        observeStateChanges()
        refreshEmptyState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning from a pushed child or coming back to the foreground.
        // While we were off-screen, background sort/import/delete events
        // updated our internal `items` array via `sort()` / `itemDeleted`
        // / etc. — but we deliberately skipped the snapshot apply to
        // avoid layout work behind a covering VC. Now push the current
        // data state to the visible UI in one shot, no animation (no
        // transition is appropriate for a returning view).
        subview?.applyData(animated: false)
        refreshEmptyState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Selection haptic when the user navigates back out of this VC,
        // mirroring how every other discrete tap in the page (cells,
        // nav-bar menu items, context-menu actions) ticks. The system
        // back button doesn't expose a tap callback, so we infer the
        // event from disappear-state.
        //
        // - `isMovingFromParent` filters out "this VC is being covered
        //   by a pushed child" (where we'd otherwise haptic on going
        //   DEEPER, which is wrong) — that case has it false.
        // - `transitionCoordinator?.isInteractive` filters out the
        //   swipe-back gesture: the continuous swipe is its own
        //   tactile signal, and stacking an extra haptic on top feels
        //   double-tapped. iOS system apps follow the same convention
        //   (discrete actions tick, continuous gestures don't).
        //
        // `Vibration` internally honors the app-level haptics-enabled
        // toggle in settings, so no need to gate on it here.
        guard isMovingFromParent else { return }
        let isSwipeBack = transitionCoordinator?.isInteractive ?? false
        if !isSwipeBack {
            Vibration.selection.vibrate()
        }
    }
}

// MARK: - Combine subscriptions on RetroRomFolderPageState

private extension RetroRomFolderHostViewController {

    /// Strategy A: every live host subscribes to the same publishers.
    /// All hosts react to organize / layout changes (so parents in the
    /// nav stack pick up the new mode on back-navigation). Sort fires a
    /// reload on every host. Refresh fires on every host but only the
    /// visible one acts.
    func observeStateChanges() {
        let state = RetroRomFolderPageState.shared

        state.$organizeMode
            .dropFirst()                          // skip current-value replay on subscribe
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.installSubview()
                self?.refreshConfigMenu()
                // OrganizeMode change flips the leading icon in the
                // compact title view (folder ↔ cpu ↔ tag ↔ tree). No-op
                // on root (no title view).
                self?.refreshFolderTitleView()
            }
            .store(in: &cancellables)

        state.$viewLayout
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Layout swap currently rebuilds the subview. If individual
                // subviews learn to swap their layout in-place, this can
                // narrow to `self?.subview?.viewLayoutChanged()`.
                self?.installSubview()
                self?.refreshConfigMenu()
                // ViewLayout doesn't affect the title icon or
                // folder-action menu, so no title view refresh here.
            }
            .store(in: &cancellables)

        state.$sortType
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Every host (visible or not) re-sorts its `items` array
                // so the data stays consistent across the nav stack.
                // Background hosts: that's all they do — no UI work
                // behind a covering VC.
                self.subview?.sort()

                // Visible host: also push the new order to the UI with
                // an animation. Background hosts' applies will happen
                // later via their own `viewWillAppear` → `applyData(false)`.
                if self.navigationController?.topViewController === self {
                    self.subview?.applyData(animated: true)
                }

                // Sort affects the direction-arrow + checkmark on the
                // sort section, so rebuild the nav-bar config menu. The
                // title-chevron menu doesn't surface sort actions, so
                // it doesn't need refreshing here.
                self.refreshConfigMenu()
            }
            .store(in: &cancellables)

        state.refreshRequested
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                // Only the visible host reacts. Parent VCs sitting in the
                // nav stack hear the tick but ignore it — a refresh while
                // they're off-screen would be visual churn.
                guard let self = self,
                      self.navigationController?.topViewController === self else { return }
                self.subview?.reload()
            }
            .store(in: &cancellables)

        state.itemMoved
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                // Only the host whose folder is the move destination
                // cares — every other host sees a tick that's not for
                // them and bails. Source-side cleanup is handled
                // inline by the host that initiated `moveItem` via the
                // `onSuccess` callback, so we don't duplicate it here.
                guard let self = self,
                      event.destinationFolderKey == self.folderKey else { return }
                self.subview?.itemMovedIn(event.item)
                self.refreshEmptyState()
            }
            .store(in: &cancellables)

        state.itemDeleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                guard let self = self else { return }
                self.subview?.itemDeleted(item)
                self.refreshEmptyState()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Subview management

private extension RetroRomFolderHostViewController {

    /// Tear down the current subview, build the right one for the current
    /// global state, install it edge-to-edge, wire delegate, re-evaluate
    /// empty state.
    ///
    /// Every host in the nav stack re-installs on a mode change — so
    /// when the user backs out of a deep folder, the parent already
    /// reflects the new mode.
    func installSubview() {
        let sectionParams: [String: RetroRomSectionParam]? = { (subview: RetroRomFolderSubview?) in
            if let sectionedSubView = subview as? RetroRomFolderSectionedSubview {
                return sectionedSubView.sectionParams
            } else {
                return nil
            }
        }(subview)

        subview?.removeFromSuperview()
        subview = nil

        guard let newSubview = makeSubview(sectionParams: sectionParams) else { return }
        newSubview.delegate = self

        view.addSubview(newSubview)
        newSubview.snp.makeConstraints { make in
            // Edge-to-edge so the inner scroll view passes under the nav
            // bar — required for large-title scroll collapse to animate.
            make.edges.equalToSuperview()
        }

        subview = newSubview
        refreshEmptyState()
    }

    /// Pick the concrete subview class for the current `OrganizeMode` +
    /// `ViewLayout`. Unimplemented combinations fall back to a labeled
    /// placeholder so mode switches stay visible during development.
    func makeSubview(sectionParams: [String: RetroRomSectionParam]?) -> RetroRomFolderSubview? {
        let state = RetroRomFolderPageState.shared

        // byFolder + icon  →  grid of icon cells.
        // byFolder + list  →  table-style list of full-width cells.
        // tree             →  outline view of the subtree rooted at
        //                     this host's `folderKey` (independent of
        //                     `viewLayout` — tree has its own visual).
        if state.organizeMode == .byFolder {
            switch state.viewLayout {
            case .icon:
                return RetroRomFolderUnifiedSubview(folderKey: folderKey, style: .icon)
            case .list:
                return RetroRomFolderUnifiedSubview(folderKey: folderKey, style: .list)
            }
        }
        if state.organizeMode == .tree {
            return RetroRomFolderTreeSubview(folderKey: folderKey)
        }
        // byCore / byTag share the same sectioned UI body
        // (`RetroRomFolderSectionedSubview`) with different data
        // sources injected. Both handle icon + list layouts internally
        // via the captured `viewLayout` at init.
        if state.organizeMode == .byCore {
            let ds = RetroRomByCoreSectionedDataSource(folderKey: folderKey)
            return RetroRomFolderSectionedSubview(folderKey: folderKey, dataSource: ds, oldParameters: sectionParams)
        }
        if state.organizeMode == .byTag {
            let ds = RetroRomByTagSectionedDataSource(folderKey: folderKey)
            return RetroRomFolderSectionedSubview(folderKey: folderKey, dataSource: ds, oldParameters: sectionParams)
        }

        return nil
    }
}

// MARK: - Empty state overlay

private extension RetroRomFolderHostViewController {

    /// Show / hide the empty-library overlay based on the current subview's
    /// `couldShowEmptyTip`. The empty-state CTA routes through `addAction()`
    /// so it's the same flow as the nav-bar `+` button.
    func refreshEmptyState() {
        emptyTipView?.removeFromSuperview()
        emptyTipView = nil

        guard subview?.couldShowEmptyTip == true else { return }

        let tip = RetroRomEmptyTipView()
        tip.onImportTapped = { [weak self] in
            self?.addAction()
        }
        view.addSubview(tip)
        tip.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyTipView = tip
    }
}

// MARK: - Navigation bar

private extension RetroRomFolderHostViewController {

    /// Title from the host's own `folderKey` — each host has its own scope,
    /// reading global state would make every level show the same string.
    /// Routes to either the system large-title (`navigationItem.title`,
    /// root) or the custom `RetroRomFolderTitleView` (subfolders).
    func updateNavigationTitle() {
        let text = currentFolderTitleText()
        if folderKey == "root" {
            navigationItem.title = text
        } else {
            folderTitleView?.title = text
        }
    }

    /// Resolve the user-visible title text for this host's folder. Root
    /// falls back to the app's homepage title constant; everything else
    /// reads the folder's persisted display name.
    func currentFolderTitleText() -> String {
        if folderKey == "root" {
            return Bundle.localizedString(forKey: "homepage_main_title")
        }
        return RetroRomFileManager.shared
            .folderItem(key: folderKey)?
            .itemPageTitle
            ?? Bundle.localizedString(forKey: "homepage_main_title")
    }

    /// Build the leading icon for the title view based on the current
    /// `OrganizeMode`. Matches the symbol set used by
    /// `RetroRomFileBrowserConfigMenu.organizeSection(...)` so the icon
    /// the user sees in the title is the same icon next to the checked
    /// row in the nav-bar config menu.
    func organizeModeIcon() -> UIImage? {
        switch RetroRomFolderPageState.shared.organizeMode {
        case .byFolder: return UIImage(systemName: "folder")
        case .byCore:   return UIImage(systemName: "cpu")
        case .byTag:    return UIImage(systemName: "tag")
        case .tree:     return IconRender.shared.treeSymbol(size: CGSize(width: 22, height: 22))
        }
    }

    /// Create and install the compact title view for a non-root host.
    /// Title text itself is left to `updateNavigationTitle()` (single
    /// source of truth — also called on language change).
    func installFolderTitleView() {
        let titleView = RetroRomFolderTitleView()
        titleView.icon = organizeModeIcon()
        titleView.menu = makeFolderTitleMenu()
        navigationItem.titleView = titleView
        folderTitleView = titleView
    }

    /// Re-derive the title view's leading icon **and** menu from current
    /// `RetroRomFolderPageState.organizeMode`:
    ///
    /// - Icon: folder / cpu / tag / tree, swapped to match the mode.
    /// - Menu: "New Folder" entry is conditionally present (byFolder
    ///   only). When the user flips organize mode, the menu may gain
    ///   or lose that entry.
    ///
    /// No-op on root (no title view to refresh).
    func refreshFolderTitleView() {
        guard let titleView = folderTitleView else { return }
        titleView.icon = organizeModeIcon()
        titleView.menu = makeFolderTitleMenu()
    }

    func configNavigationBarButtonItems() {
        let plusIcon = UIImage(systemName: "plus")
        let plusButton = UIBarButtonItem(image: plusIcon,
                                         landscapeImagePhone: plusIcon,
                                         style: .plain,
                                         target: self, action: #selector(addAction))
        plusButton.tintColor = .label

        // Wrap a UIButton in a UIBarButtonItem customView so we get a
        // `.touchDown` hook for the menu-open haptic. UIBarButtonItem's
        // built-in `.menu` setter has no "menu will show" callback;
        // UIButton fires `.touchDown` immediately as the menu starts to
        // present (with `showsMenuAsPrimaryAction = true`), which matches
        // the user-perceived moment of "the menu just appeared."
        let configIcon = UIImage(systemName: "slider.horizontal.3")
        let configButtonView = UIButton(type: .system)
        configButtonView.setImage(configIcon, for: .normal)
        configButtonView.showsMenuAsPrimaryAction = true
        configButtonView.menu = RetroRomFileBrowserConfigMenu.make()
        configButtonView.tintColor = .label
        configButtonView.addAction(UIAction { _ in
            Vibration.selection.vibrate()
        }, for: .touchDown)

        // Targetless menu: actions inside the menu mutate
        // `RetroRomFolderPageState.shared`; we receive the change via
        // Combine. `refreshConfigMenu()` rebuilds and reassigns this
        // button's menu when state changes.
        let configButton = UIBarButtonItem(customView: configButtonView)
        self.configBarButton = configButton

        navigationItem.rightBarButtonItems = [configButton, plusButton]
    }

    /// Rebuild the eager `UIMenu` from current `RetroRomFolderPageState`
    /// and reassign it on the bar button. Cheap (a few `UIAction`s) and
    /// only fires on actual state changes (Combine `dropFirst` +
    /// `removeDuplicates`).
    func refreshConfigMenu() {
        (configBarButton?.customView as? UIButton)?.menu = RetroRomFileBrowserConfigMenu.make()
    }
}

// MARK: - Blank-area menu (long-press on empty subview space)

private extension RetroRomFolderHostViewController {

    /// Menu surfaced when the user long-presses the subview's blank
    /// area (between cells, on the empty-state overlay, etc.). The
    /// semantic is **"what can I do at this position in the library?"**
    /// — create something, or change how the content is arranged.
    ///
    /// Deliberately distinct from the title-chevron menu
    /// (`makeFolderTitleMenu`), which operates on the **current folder
    /// itself** (rename, assign core, etc.). The two menus share
    /// "New Folder" because that action belongs to both intents.
    ///
    /// Layout mirrors the iOS Files app blank-area menu — a "create"
    /// section above an "arrange" section. The Sort-By children come
    /// from `RetroRomFileBrowserConfigMenu.sortActions()`, the same
    /// source feeding the nav-bar config menu's inline sort section,
    /// so checkmarks and direction arrows stay in sync.
    func makeBlankAreaMenu() -> UIMenu? {
        // Defensive: don't surface a menu before RetroArch boots. Sort
        // would mutate global state with no listener; Import depends on
        // the manager being warm to read supported file types.
        guard RetroArchX.shared().initialized else { return nil }

        let importAction = UIAction(title: Bundle.localizedString(forKey: "homepage_import_for_folder"),
                                    image: UIImage(systemName: "plus")) { [weak self] _ in
            Vibration.selection.vibrate()
            self?.addAction()
        }

        let sortSubmenu = UIMenu(title: Bundle.localizedString(forKey: "homepage_sort_by"),
                                 image: UIImage(systemName: "arrow.up.arrow.down"),
                                 children: RetroRomFileBrowserConfigMenu.sortActions())

        // "New Folder" only makes sense in byFolder mode — byCore and
        // byTag render computed buckets (one section per core/tag), not
        // real folder children, so creating a new folder has no visible
        // landing spot in the current view. tree mode also drops it
        // here because tree's own UX (long-press a folder cell → "New
        // Folder Under") covers nested creation more precisely.
        var createSectionChildren: [UIMenuElement] = [importAction]
        if RetroRomFolderPageState.shared.organizeMode == .byFolder {
            let newFolderMenuItem = UIAction(title: Bundle.localizedString(forKey: "homepage_new_folder"),
                                             image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                Vibration.selection.vibrate()
                self?.createNewFolderAction()
            }
            createSectionChildren.append(newFolderMenuItem)
        }

        // Two sections separated by an inline divider. UIMenu renders a
        // separator automatically between sibling `.displayInline` groups.
        let createSection  = UIMenu(options: .displayInline,
                                    children: createSectionChildren)
        let arrangeSection = UIMenu(options: .displayInline,
                                    children: [sortSubmenu])

        return UIMenu(title: "", children: [createSection, arrangeSection])
    }
}

// MARK: - Folder-title menu (tap the chevron next to the folder name)

private extension RetroRomFolderHostViewController {

    /// Menu opened by tapping the compact title view's chevron on
    /// non-root hosts. Semantically **"act on THIS folder"** — the
    /// folder the user is currently inside — not "things I could do at
    /// this position." Three actions:
    ///
    /// 1. **Assign Core** — set the default emulator core for the folder.
    ///    Same `assignCoreAction(item:)` factory used by the long-press
    ///    cell menu, parameterized with the current folder.
    /// 2. **Rename** — opens the rename alert against the current folder.
    ///    Same `renameAction(item:)` factory.
    /// 3. **New Folder** — create a child folder under the current one
    ///    and immediately begin renaming it. Same `createNewFolderAction`
    ///    imperative method used by the blank-area menu.
    ///
    /// **Why not duplicate the blank-area menu**: Import and Sort already
    /// have first-class entry points in the nav bar (the `+` and slider
    /// buttons sit right next to this title). Repeating them in the
    /// title menu would feel redundant. Instead, the title menu
    /// concentrates on actions that have no other entry point at this
    /// nav level (the cell-level long-press menu only acts on tapped
    /// cells, not on the containing folder itself).
    ///
    /// Returns `nil` when the current folder can't be resolved — e.g.
    /// the host is mid-init, or the folder was concurrently deleted.
    /// (Not expected in practice; the host's lifetime is bound to the
    /// folder's existence.)
    func makeFolderTitleMenu() -> UIMenu? {
        guard let folder = RetroRomFileManager.shared.folderItem(key: folderKey) else { return nil }

        var actions: [UIAction] = []

        if let assignCore = assignCoreAction(item: folder) {
            actions.append(assignCore)
        }
        actions.append(renameAction(item: folder))

        // "New Folder" only makes sense in byFolder mode. byCore / byTag
        // organize the same files into computed buckets — the cells the
        // user sees aren't real folder children of the current folder, so
        // "create a subfolder here" has no meaningful target. Tree mode
        // is also a computed view of the byFolder hierarchy; we could
        // surface New Folder there too, but for v1 byFolder-only keeps
        // the rule simple.
        if RetroRomFolderPageState.shared.organizeMode == .byFolder {
            let newFolder = UIAction(title: Bundle.localizedString(forKey: "homepage_new_folder"),
                                     image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                Vibration.selection.vibrate()
                self?.createNewFolderAction()
            }
            actions.append(newFolder)
        }

        return UIMenu(title: "", children: actions)
    }
}

// MARK: - Import flow

private extension RetroRomFolderHostViewController {

    @objc
    func addAction() {
        Vibration.selection.vibrate()
        guard RetroArchX.shared().initialized else { return }

        let sheet = RetroRomImportSheetViewController { [weak self] type in
            self?.importGame(fileType: type)
        }
        present(sheet, animated: true)
    }

    func importGame(fileType: RetroRomImportSheetViewController.FileType) {
        // The import sheet dismisses itself before invoking this callback,
        // so the document picker can be presented immediately.
        let types: [UTType] = fileType == .file
            ? RetroArchX.shared().allSupportedExtensions
            : [.folder]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        documentPicker.allowsMultipleSelection = (fileType == .file)
        present(documentPicker, animated: true, completion: nil)
    }

    /// "New Folder" entry point from the blank-area context menu.
    /// Three-step flow:
    ///   1. `RetroRomFileManager.createNewFolder(in:)` mutates SQLite +
    ///      filesystem, returns the new folder (or nil + toast on failure).
    ///   2. `subview?.appendNewFolder(_:)` inserts the new cell at the
    ///      tail of the visible list, animates the insert, and scrolls
    ///      it into view.
    ///   3. `presentRenameAlert(for:)` immediately surfaces the rename
    ///      alert pre-filled with the default "New Folder" name so the
    ///      user types over it without an extra tap.
    ///
    /// Step 2 and step 3 are independent — the alert doesn't require the
    /// new cell to be visible (it commits via `item.updateShowName(_:)`
    /// which propagates through KVO regardless of cell realization).
    /// We still run step 2 first so when the user dismisses the alert
    /// (Cancel, or OK after typing), they see their folder where they
    /// expect it.
    func createNewFolderAction() {
        createNewFolderAction(under: folderKey)
    }

    /// Tree-mode variant: create a new folder under a specific parent
    /// (not necessarily this host's `folderKey`). Used by
    /// `newFolderUnderAction` so the user can spawn a subfolder
    /// directly inside any folder they long-press in the tree, without
    /// first having to "navigate" into it. The subview is responsible
    /// for animating the insert under the right parent — tree's
    /// `appendNewFolder` reads `folder.parent` and places it correctly.
    func createNewFolderAction(under parent: RetroRomFolderItem) {
        createNewFolderAction(under: parent.key)
    }

    private func createNewFolderAction(under parentKey: String) {
        guard let folder = RetroRomFileManager.shared.createNewFolder(in: parentKey) else { return }
        subview?.appendNewFolder(folder)
        presentRenameAlert(for: folder)
        refreshEmptyState()
    }
}

extension RetroRomFolderHostViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        // Import targets THIS host's folder, not any global "current"
        // folder. Importing inside GBA lands ROMs in GBA, regardless of
        // where else in the stack mutation happened.
        RetroRomFileManager.shared.importGame(urls: urls, rootParent: folderKey)
    }
}

// MARK: - NotificationCenter observation

/// Host is the single observer for global library events. It fans them
/// out by calling the matching method on the current subview. This keeps
/// subviews stateless w.r.t. notifications (easy to swap without leaking
/// observers) and centralizes the dispatch in one place.
private extension RetroRomFolderHostViewController {

    func observeNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleRomCountChanged),
                       name: .romCountChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleFileImported(_:)),
                       name: .retroFileImported, object: nil)
        nc.addObserver(self, selector: #selector(handleFolderImported(_:)),
                       name: .retroFolderImported, object: nil)
        nc.addObserver(self, selector: #selector(handleLanguageChanged),
                       name: .languageChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleFileTagColorChanged(_:)),
                       name: .fileTagColorChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleFileCoreAssigned(_:)),
                       name: .fileCoreAssigned, object: nil)
        nc.addObserver(self, selector: #selector(handleFileTagsChanged(_:)),
                       name: .fileTagFileChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleFileTagDeleted(_:)),
                       name: .fileTagDeleted, object: nil)
        nc.addObserver(self, selector: #selector(handleFileTagTitleChanged(_:)),
                       name: .fileTagTitleChanged, object: nil)
        nc.addObserver(self, selector: #selector(handleRetroArchXReady(_:)), name: .RetroArchXReady, object: nil)
    }

    @objc
    func handleRomCountChanged() {
        refreshEmptyState()
    }

    @objc
    func handleFileImported(_ notif: Notification) {
        let keys = (notif.userInfo?["fileKeys"] as? [String]) ?? []
        subview?.fileItemImported(keys)
        refreshEmptyState()
    }

    @objc
    func handleFolderImported(_ notif: Notification) {
        let folderKey = (notif.userInfo?["folderKey"] as? String) ?? ""
        let fileKeys  = (notif.userInfo?["fileKeys"] as? [String]) ?? []
        subview?.folderItemImported(folderKey: folderKey, itemKeys: fileKeys)
        refreshEmptyState()
    }

    @objc
    func handleLanguageChanged() {
        updateNavigationTitle()
        subview?.languageChanged()
    }

    @objc
    func handleFileTagColorChanged(_ notif: Notification) {
        guard let tagId = notif.object as? Int else { return }
        subview?.fileTagColorChanged(tagId: tagId)
    }

    /// Bridge `.fileCoreAssigned` (posted by `RetroRomFileItem.assignCore`)
    /// to the subview's protocol method. `userInfo["new"]` and
    /// `userInfo["old"]` are coreId strings that the file gained /
    /// lost membership in — both optional; at least one is present
    /// when the notification fires (`assignCore` doesn't post if
    /// neither changes the file's section membership).
    @objc
    func handleFileCoreAssigned(_ notif: Notification) {
        guard let file = notif.object as? RetroRomFileItem else { return }
        let info = notif.userInfo as? [String: String]
        subview?.fileCoreAssigned(file,
                                  newCoreId: info?["new"],
                                  oldCoreId: info?["old"])
    }

    /// Bridge `.fileTagFileChanged` (posted by
    /// `RetroRomFileItem.assignTags(_:)` etc.) to the subview. The
    /// userInfo carries `Set<Int>` for added and removed tag ids.
    @objc
    func handleFileTagsChanged(_ notif: Notification) {
        guard let file = notif.object as? RetroRomFileItem else { return }
        let added = (notif.userInfo?["added"] as? Set<Int>) ?? []
        let removed = (notif.userInfo?["removed"] as? Set<Int>) ?? []
        subview?.fileTagsChanged(file, added: added, removed: removed)
    }

    /// Bridge `.fileTagDeleted` — the entire tag entity is gone.
    @objc
    func handleFileTagDeleted(_ notif: Notification) {
        guard let tag = notif.object as? RetroRomFileTag else { return }
        subview?.fileTagDeleted(tag)
    }

    /// Bridge `.fileTagTitleChanged` — tag display string changed.
    @objc
    func handleFileTagTitleChanged(_ notif: Notification) {
        guard let tag = notif.object as? RetroRomFileTag else { return }
        subview?.fileTagTitleChanged(tag)
    }

    @objc
    func handleRetroArchXReady(_ notif: Notification) {
        refreshConfigMenu()
    }
}

// MARK: - RetroRomFolderSubviewDelegate

extension RetroRomFolderHostViewController: RetroRomFolderSubviewDelegate {

    // MARK: Navigation

    func subview(_ subview: RetroRomFolderSubview,
                 didTapFolder folder: RetroRomFolderItem) {
        // Each push creates a new host instance with the child's folderKey.
        // The new instance reads global mode at install time, so push
        // navigation always lands in whatever the user's current mode is.
        let next = RetroRomFolderHostViewController(folderKey: folder.key)
        navigationController?.pushViewController(next, animated: true)
    }

    func subview(_ subview: RetroRomFolderSubview,
                 didTapFile file: RetroRomFileItem) {
        launchGame(file)
    }

    /// byCore variant: launch the **specific core** the user picked
    /// (the row was tapped IN that core's section). Falls back to the
    /// generic launch path when `core == nil` (the "no recognized
    /// core" bucket) — that path opens the core picker.
    func subview(_ subview: RetroRomFolderSubview,
                 didTapFile file: RetroRomFileItem,
                 withPreferredCore core: EmuCoreInfoItem?) {
        if let core = core, core != .noneCore() {
            launchGame(file, withCore: core)
        } else {
            launchGame(file)
        }
    }

    // MARK: Modal / contextual

    func subviewDidTapEmptyStateCTA(_ subview: RetroRomFolderSubview) {
        addAction()
    }

    func subview(_ subview: RetroRomFolderSubview,
                 contextMenuForItem item: RetroRomBaseItem) -> UIMenu? {
        // `newFolderUnderAction` returns nil outside tree mode, so the
        // single `compactMap` line below silently drops it for icon /
        // list. Tree mode picks it up automatically.
        let actions: [UIAction] = [
            playOrEnterAction(item: item),
            assignCoreAction(item: item),
            gameSettingAction(item: item),
            importForFolderAction(item: item),
            newFolderUnderAction(item: item),
            moveToAction(item: item),
            renameAction(item: item),
            tagAction(item: item),
            deleteAction(item: item)
        ].compactMap { $0 }

        return UIMenu(title: "", children: actions)
    }

    func subview(_ subview: RetroRomFolderSubview,
                 didDropItem srcItem: RetroRomBaseItem,
                 intoFolder dstFolder: RetroRomFolderItem) {
        // Same code path as the long-press → "Move to…" action's success
        // branch, just with the destination decided by the user's drag
        // gesture instead of a folder picker. `moveItem` itself handles:
        // - "forbidden destination" alert (dst is a descendant of src,
        //   or a name collision)
        // - success / failure toast
        // - the actual SQLite + filesystem move
        //
        // On success we tell THIS subview the source item is gone (so it
        // animates out of the current folder view) and re-evaluate the
        // empty-state overlay. We deliberately don't auto-push into
        // `dstFolder` — the drag/drop gesture is a "file it away here"
        // action, not a "go to the destination" navigation.
        RetroRomFileManager.shared.moveItem(srcItem, to: dstFolder, presentingVC: self) { [weak self] in
            self?.subview?.itemDeleted(srcItem)
            self?.refreshEmptyState()
        }
    }

    func subviewContextMenuForBlankArea(_ subview: RetroRomFolderSubview) -> UIMenu? {
        makeBlankAreaMenu()
    }

    // MARK: Coordination

    func subviewDidChangeContent(_ subview: RetroRomFolderSubview) {
        refreshEmptyState()
    }
}

// MARK: - Game launch

private extension RetroRomFolderHostViewController {

    /// If the file resolves to a runnable core, launch immediately;
    /// otherwise present a core picker.
    func launchGame(_ file: RetroRomFileItem) {
        guard RetroArchX.shared().canRunOnThisDevice() else { return }

        if let core = RetroRomCoreManager.shared.getRunningCore(file) {
            RetroArchX.playGame(romItem: file, core: core)
        } else {
            let picker = RetroRomCoreSelectViewController(action: .runRomWithItem(item: file))
            let nav    = UINavigationController(rootViewController: picker)
            present(nav, animated: true)
        }
    }

    /// byCore variant: launch with an explicit core (the one whose
    /// section the user tapped in). Bypasses `getRunningCore` so the
    /// user's per-section intent is respected even when the file
    /// supports multiple cores. No picker fallback — caller has
    /// already chosen.
    func launchGame(_ file: RetroRomFileItem, withCore core: EmuCoreInfoItem) {
        guard RetroArchX.shared().canRunOnThisDevice() else { return }
        RetroArchX.playGame(romItem: file, core: core)
    }
}

// MARK: - Context menu actions

/// Differences vs the deleted legacy `RetroRomFileBrowser` extension:
///
/// - Modals are presented from `self` (the host VC).
/// - Delete / Move-To call the callback-based `RetroRomFileManager`
///   APIs (`deleteItem(_:completion:)`, `moveItem(_:to:presentingVC:onSuccess:)`).
/// - Rename action is omitted in v1 — it requires a "begin renaming this
///   item" hook on the subview protocol that we haven't added yet.
private extension RetroRomFolderHostViewController {

    func playOrEnterAction(item: RetroRomBaseItem) -> UIAction? {
        if let file = item as? RetroRomFileItem {
            return UIAction(title: Bundle.localizedString(forKey: "homepage_play"),
                            image: UIImage(systemName: "play")) { [weak self] _ in
                Vibration.selection.vibrate()
                self?.launchGame(file)
            }
        }
        if let folder = item as? RetroRomFolderItem {
            // "Enter" stays available even in tree mode. The folder
            // cell's TAP behavior in tree is expand/collapse (in-place
            // browsing), but the long-press menu's "Enter" is a
            // deliberate "open this folder as its own page" action —
            // useful when the user wants to drill into a subtree
            // without first switching organize mode. The pushed host
            // VC reads the global `organizeMode` at install time, so
            // a tree-mode user gets a tree-mode child page rooted at
            // the picked folder; same for byFolder users.
            return UIAction(title: Bundle.localizedString(forKey: "homepage_enter"),
                            image: UIImage(systemName: "folder")) { [weak self] _ in
                Vibration.selection.vibrate()
                guard let self = self else { return }
                let next = RetroRomFolderHostViewController(folderKey: folder.key)
                self.navigationController?.pushViewController(next, animated: true)
            }
        }
        return nil
    }

    /// Tree-only menu item: "create a child folder directly under the
    /// long-pressed folder cell." Available in tree mode because the
    /// user can see — and operate on — multiple folder levels at once;
    /// in icon/list mode the user can only see one level, and "new
    /// folder here" via the blank-area menu already covers the use
    /// case unambiguously.
    ///
    /// Returns `nil` outside tree mode, and for non-folder items.
    func newFolderUnderAction(item: RetroRomBaseItem) -> UIAction? {
        guard RetroRomFolderPageState.shared.organizeMode == .tree,
              let folder = item as? RetroRomFolderItem else {
            return nil
        }
        return UIAction(title: Bundle.localizedString(forKey: "homepage_new_folder"),
                        image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
            Vibration.selection.vibrate()
            self?.createNewFolderAction(under: folder)
        }
    }

    func assignCoreAction(item: RetroRomBaseItem) -> UIAction? {
        UIAction(title: Bundle.localizedString(forKey: "homepage_asign_core"),
                 image: UIImage(systemName: "cpu")) { [weak self] _ in
            Vibration.selection.vibrate()
            guard let self = self else { return }

            let action: RetroRomCoreSelectViewController.Action
            if let file = item as? RetroRomFileItem {
                action = .assignCoreForFile(item: file)
            } else if let folder = item as? RetroRomFolderItem {
                action = .assignCoreForFolder(folder: folder)
            } else {
                return
            }
            let picker = RetroRomCoreSelectViewController(action: action)
            let nav    = UINavigationController(rootViewController: picker)
            self.present(nav, animated: true)
        }
    }

    func gameSettingAction(item: RetroRomBaseItem) -> UIAction? {
        // Per-game setting only makes sense for runnable files with a
        // resolvable core; folders / unresolvable files get nothing.
        guard let file = item as? RetroRomFileItem else { return nil }
        let core = RetroRomCoreManager.shared.getRunningCore(file)
        return UIAction(title: Bundle.localizedString(forKey: "configpage_rom_setting"),
                        image: UIImage(systemName: "gear")) { [weak self] _ in
            Vibration.selection.vibrate()
            let session = GameConfigSession(scope: .game, core: core, game: file)
            let vc      = GameConfigViewController(session: session,
                                                   applyInputBinding: true,
                                                   showCloseButton: true)
            let nav     = UINavigationController(rootViewController: vc)
            self?.present(nav, animated: true)
        }
    }

    /// "Import into this folder" — only applies when the long-pressed item
    /// is itself a folder. File items don't have an "import into" concept.
    func importForFolderAction(item: RetroRomBaseItem) -> UIAction? {
        guard let folder = item as? RetroRomFolderItem else { return nil }
        return UIAction(title: Bundle.localizedString(forKey: "homepage_import_for_folder"),
                        image: UIImage(systemName: "plus")) { [weak self] _ in
            Vibration.selection.vibrate()
            // Push into the target folder first, then trigger the import
            // sheet on THAT host. Matches the "import lands in the visible
            // folder" rule, even when the user initiated from a parent.
            guard let self = self else { return }
            let next = RetroRomFolderHostViewController(folderKey: folder.key)
            self.navigationController?.pushViewController(next, animated: true)
            // Defer until the push transition settles so the sheet appears
            // on the destination VC, not the source.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak next] in
                next?.addAction()
            }
        }
    }

    func moveToAction(item: RetroRomBaseItem) -> UIAction? {
        // "Move to" is a folder-hierarchy action — it changes the
        // item's parent folder. byCore / byTag don't expose the folder
        // hierarchy in the UI (cells are grouped by core or tag, not
        // by location), so surfacing this action there is confusing:
        // the user would pick a folder, the move would succeed, and
        // the cell would seemingly stay in place (it's still in the
        // same core/tag section). Hide entirely in those modes;
        // users who want to reorganize folders switch to byFolder
        // first.
        let mode = RetroRomFolderPageState.shared.organizeMode
        guard mode == .byFolder || mode == .tree else { return nil }

        return UIAction(title: Bundle.localizedString(forKey: "homepage_move_to"),
                        image: UIImage(systemName: "arrow.right.doc.on.clipboard")) { [weak self] _ in
            Vibration.selection.vibrate()
            guard let self = self else { return }
            // Selector is a pure folder picker now; we receive the
            // destination via `onPicked` and drive the actual move +
            // toast/alert through `RetroRomFileManager.moveItem(...)`.
            let selector = RetroRomLocationSelector(srcItem: item) { [weak self] dstFolder in
                guard let self = self else { return }
                RetroRomFileManager.shared.moveItem(item, to: dstFolder, presentingVC: self) { [weak self] in
                    // Source folder lost the item — refresh local view.
                    // Intentionally NOT auto-pushing into dstFolder: the
                    // legacy "navigate to destination after move" feels
                    // jarring in a push-based nav model.
                    self?.subview?.itemDeleted(item)
                    self?.refreshEmptyState()
                }
            }
            let nav = UINavigationController(rootViewController: selector)
            self.present(nav, animated: true)
        }
    }

    /// Rename via a `UIAlertController` with a single `UITextField`.
    /// Available for both files and folders — `showName` is a display-only
    /// field in SQLite (the underlying `rawName` / filesystem path is
    /// unchanged), so file renames are non-destructive and there's no
    /// reason to gate this to folders only.
    ///
    /// Earlier iterations rendered an inline `UITextView` directly on the
    /// cell. That looked clever but suffered three real UX problems:
    /// cell title font is small (~14pt), the editing area is narrow
    /// (~120pt cell width), and there was no explicit Cancel affordance.
    /// An alert sidesteps all three and matches what every iOS system
    /// app does for rename (Mail, Notes, Reminders, Photos).
    func renameAction(item: RetroRomBaseItem) -> UIAction {
        UIAction(title: Bundle.localizedString(forKey: "homepage_rename"),
                 image: UIImage(systemName: "pencil.line")) { [weak self] _ in
            Vibration.selection.vibrate()
            self?.presentRenameAlert(for: item)
        }
    }

    /// Build and present the rename alert. Persistence happens through
    /// `RetroRomBaseItem.updateShowName(_:)` which toggles `pulseText`;
    /// the cell's KVO observer picks that up and refreshes the title
    /// label automatically — no snapshot apply needed.
    func presentRenameAlert(for item: RetroRomBaseItem) {
        let currentName = item.itemName
        let title       = Bundle.localizedString(forKey: "homepage_rename")
        let alert = UIAlertController(title: title,
                                      message: currentName,
                                      preferredStyle: .alert)

        alert.addTextField { tf in
            tf.text                  = currentName
            tf.clearButtonMode       = .whileEditing
            tf.autocorrectionType    = .no
            tf.autocapitalizationType = .none
            tf.returnKeyType         = .done
            // Default alert textField font is ~13pt — too tight for ROM
            // names full of region tags and revision suffixes. 17pt is
            // the standard body size and visibly improves legibility.
            tf.font = .systemFont(ofSize: 17)
        }

        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"),
                                      style: .cancel) { _ in
            Vibration.light.vibrate()
        })

        let okTitle = Bundle.localizedString(forKey: "ok")
        alert.addAction(UIAlertAction(title: okTitle, style: .default) { [weak self, weak alert] _ in
            Vibration.selection.vibrate()
            guard let tf = alert?.textFields?.first else { return }
            let newName = (tf.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self?.commitRename(item: item, newName: newName, original: currentName)
        })

        alert.view.tintColor = .label
        present(alert, animated: true) {
            // Pre-select the portion before the first "." (extension), so
            // typing immediately replaces the base name without nuking
            // the extension. Matches the legacy inline editor's selection
            // behavior. `selectedTextRange` must be set AFTER the field
            // is in the responder chain, which is why this lives in the
            // `present(completion:)` block rather than the configuration
            // handler above.
            guard let tf = alert.textFields?.first else { return }
            let nsText = (tf.text ?? "") as NSString
            let dotRange = nsText.range(of: ".")
            let endOffset = dotRange.location == NSNotFound ? nsText.length : dotRange.location
            guard endOffset > 0,
                  let endPos = tf.position(from: tf.beginningOfDocument, offset: endOffset) else { return }
            tf.selectedTextRange = tf.textRange(from: tf.beginningOfDocument, to: endPos)
        }
    }

    /// Handle the OK-pressed validation + persistence path. Split out so
    /// the alert builder stays declarative.
    func commitRename(item: RetroRomBaseItem, newName: String, original: String) {
        // Empty name is rejected — keeping `showName` non-empty is a hard
        // invariant for the cell layer (titleLabel can't render "" without
        // collapsing layout) and for `RetroRomPersistence`'s queries.
        guard !newName.isEmpty else {
            let msg = Bundle.localizedString(forKey: "homepage_rename_empty")
            AppToastManager.shared.toast(msg, context: .ui, level: .error)
            return
        }

        // No-op when the user pressed OK without changing anything. We
        // skip both the SQLite write and the success toast — the alert
        // already dismissed itself, which is feedback enough that
        // "nothing happened, on purpose."
        guard newName != original else { return }

        if item.updateShowName(newName) {
            let msg = Bundle.localizedString(forKey: "homepage_rename_success")
            AppToastManager.shared.toast(msg, context: .ui, level: .success)

            // If the renamed item IS the folder this host represents
            // (i.e. the user renamed the current folder via the title-
            // chevron menu's Rename action), reflect the new name in
            // the navigation bar immediately. Cells listen to
            // `pulseText` KVO and self-refresh; `RetroRomFolderTitleView`
            // doesn't observe the item, so the host pushes the update.
            // Doesn't fire for cell-long-press renames of sibling
            // items — those don't match this host's `folderKey`.
            if let folder = item as? RetroRomFolderItem, folder.key == folderKey {
                updateNavigationTitle()
            }
        } else {
            let msg = Bundle.localizedString(forKey: "homepage_rename_failed")
            AppToastManager.shared.toast(msg, context: .ui, level: .error)
        }
    }

    func tagAction(item: RetroRomBaseItem) -> UIAction? {
        guard let file = item as? RetroRomFileItem else { return nil }
        return UIAction(title: Bundle.localizedString(forKey: "tags"),
                        image: UIImage(systemName: "tag")) { [weak self] _ in
            Vibration.selection.vibrate()
            let selector = RetroRomTagSelector(fileItem: file)
            let nav      = UINavigationController(rootViewController: selector)
            self?.present(nav, animated: true)
        }
    }

    func deleteAction(item: RetroRomBaseItem) -> UIAction {
        UIAction(title: Bundle.localizedString(forKey: "homepage_delete"),
                 image: UIImage(systemName: "trash"),
                 attributes: .destructive) { [weak self] _ in
            Vibration.selection.vibrate()
            self?.confirmDelete(item)
        }
    }

    /// Two-step: alert confirmation → `RetroRomFileManager.deleteItem`
    /// (async) → on completion we drop the item from the subview and
    /// re-evaluate the empty state. The file manager also posts
    /// `.romCountChanged` on success, which our notification handler
    /// catches as a redundant refresh — cheap, and keeps external
    /// mutation paths consistent.
    func confirmDelete(_ item: RetroRomBaseItem) {
        let title   = item.itemName
        let message = item.isFile
            ? Bundle.localizedString(forKey: "homepage_delete_confirm_file")
            : Bundle.localizedString(forKey: "homepage_delete_confirm_folder")

        let alert = UIAlertController(title: title, message: message,
                                      preferredStyle: .alert)
        alert.addAction(.init(title: Bundle.localizedString(forKey: "delete"),
                              style: .destructive) { [weak self] _ in
            Vibration.medium.vibrate()
            RetroRomFileManager.shared.deleteItem(item) { [weak self] success in
                if success {
                    if success {
                        RetroRomFolderPageState.shared.itemDeleted.send(item)
                        self?.refreshEmptyState()
                    }
                }
            }
        })
        alert.addAction(.init(title: Bundle.localizedString(forKey: "cancel"),
                              style: .cancel) { _ in
            Vibration.light.vibrate()
        })
        alert.view.tintColor = .label
        present(alert, animated: true)
    }
}
