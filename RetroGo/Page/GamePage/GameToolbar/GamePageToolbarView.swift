//
//  GamePageToolbarView.swift
//  RetroGo
//
//  Created by haharsw on 2026/3/14.
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
import ObjcHelper
import RACoordinator

/// The in-game top bar. Layout is data-driven: a fixed `close` button on the
/// left, a fixed `more` button on the right, and in between the user-pinned
/// `GameToolbarAction`s (see `GameConfigSession.globalToolbarActions()`). Any action not
/// pinned is collected into the native `UIMenu` shown by the `more` button,
/// which also hosts the DEBUG-only pause/resume control and the "edit layout"
/// entry point.
final class GamePageToolbarView: UIView {
    private weak var holder: GamePageViewController?

    let closeButton = UIButton(type: .system)
    let moreButton  = MenuLifecycleButton()

    /// Bar buttons currently shown for pinned actions, keyed by action.
    private var barButtons: [GameToolbarAction: UIButton] = [:]

    /// Cached rendered width per action button, for the iPad width-fit math.
    private var measuredButtonWidths: [GameToolbarAction: CGFloat] = [:]

    /// Pauses the game while the More menu is open; released after the menu
    /// dismissal animation finishes so gameplay does not resume underneath a
    /// still-closing overlay.
    private var menuPauseLease: GamePauseCoordinator.Lease?

    private var isGamePaused = false
    private var isGameMuted = false

    /// Brand-color plate shown behind the lock glyph when landscape is locked,
    /// so the state reads on any background (a mid-tone tint alone washes out).
    private weak var lockBackingView: UIView?
    /// Whether the running core supports savestates; gates save/load.
    private var savestateSupported = false
    /// Whether the running core supports cheats; gates the cheat entry.
    private var cheatSupported = false
    /// Whether the running core supports netplay (deterministic savestates).
    private var netplaySupported = false
    /// Green dot on the cheat bar button when at least one cheat is enabled.
    private weak var cheatBadgeView: UIView?
    /// Green dot on the netplay bar button when a session is active (only present
    /// when netplay is pinned to the bar).
    private weak var netplayBadgeView: UIView?
    /// Green dot on the More (⋯) button when a session is active AND netplay lives
    /// in the More overflow (its default placement).
    private weak var moreNetplayBadgeView: UIView?

    /// When hidden, the bar collapses to just the close + more buttons (more
    /// shows a `chevron.down.circle` and reveals every action in its menu).
    /// Restored from persisted global state on launch.
    private var isBarHidden = GameConfigSession.globalToolbarHidden

    /// Tint for close/more while hidden — a muted-but-crisp secondary color
    /// (full opacity, no translucency) signalling the collapsed state.
    private let hiddenTint: UIColor = .secondaryLabel

    /// Width the bar was last laid out for (iPad), to avoid rebuilding on every
    /// layout pass when nothing relevant changed.
    private var lastBarLayoutWidth: CGFloat = 0

    init(holder: GamePageViewController) {
        self.holder = holder
        super.init(frame: .zero)

        configUI()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(layoutDidChange),
            name: .gameToolbarLayoutChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cheatStateDidChange),
            name: .gameCheatStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(netplayStateDidChange),
            name: .netplayStateChanged,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Refreshes per-action availability from the running core's capabilities,
    /// then rebuilds the toolbar so both the bar buttons and the More menu reflect
    /// it. save/load need savestate support; the cheat entry needs cheat support.
    func refreshActionAvailability() {
        savestateSupported = RetroArchX.shared().isCurrentCoreSupportsSavestate()
        // Cheats need both engine support AND a cheat session (the rom-item-keyed
        // store); the document-browser launch path has no session.
        cheatSupported = (holder?.cheatSession != nil) && RetroArchX.shared().cheatSupported
        netplaySupported = RetroArchX.shared().currentCoreItem?.supportsNetplay ?? false
        rebuildToolbar()
    }

    /// Whether `action` is currently enabled given the running core's
    /// capabilities. Drives both the bar button `isEnabled` and the menu item's
    /// `.disabled` attribute, so the two stay in sync.
    private func isActionEnabled(_ action: GameToolbarAction) -> Bool {
        switch action {
        case .saveState, .loadState: return savestateSupported
        case .cheat:                 return cheatSupported
        case .netplay:               return netplaySupported
        default:                     return true
        }
    }

    @objc
    private func layoutDidChange() {
        rebuildToolbar()
    }
}

// MARK: - Layout

extension GamePageToolbarView {
    private func configUI() {
        closeButton.tintColor = .label
        closeButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeAction), for: .touchUpInside)
        applyIconShadow(to: closeButton)
        closeButton.sizeToFit()
        addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.size.equalTo(closeButton.size)
        }

        moreButton.tintColor = .label
        moreButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        // custom-type 按钮不走 .system 的 SF Symbol 自动缩放管线，glyph 会偏小。
        // 22pt 是和周围 .system circle 按钮目测协调的尺寸。
        moreButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 22, weight: .regular),
            forImageIn: .normal
        )
        applyIconShadow(to: moreButton)
        moreButton.showsMenuAsPrimaryAction = true
        // Tapping More vibrates like every other button, and pauses the game
        // for as long as the menu is open (resumed when it dismisses).
        moreButton.onMenuWillShow = { [weak self] in
            Vibration.selection.vibrate()
            self?.menuPauseLease = GamePauseCoordinator.shared.acquire(reason: "toolbar-more-menu")
        }
        moreButton.onMenuWillHide = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.menuPauseLease?.release()
                self?.menuPauseLease = nil
            }
        }
        moreButton.sizeToFit()
        addSubview(moreButton)
        moreButton.snp.makeConstraints { make in
            make.trailing.equalTo(safeAreaLayoutGuide.snp.trailing).offset(-20)
            make.centerY.equalToSuperview()
            make.size.equalTo(moreButton.size)
        }

        rebuildToolbar()
        applyHiddenAppearance()
    }

    /// Reflects `isBarHidden` on the persistent close/more buttons (icon + tint).
    /// The pinned bar buttons are handled by `rebuildBar`.
    private func applyHiddenAppearance() {
        let moreImage = isBarHidden ? "chevron.down.circle" : "ellipsis.circle"
        moreButton.setImage(UIImage(systemName: moreImage), for: .normal)
        let tint: UIColor = isBarHidden ? hiddenTint : .label
        closeButton.tintColor = tint
        moreButton.tintColor = tint
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Only iPad needs width-driven recomputation; iPhone is fixed to the
        // pinned set, and a hidden bar has no buttons either way.
        guard traitCollection.userInterfaceIdiom == .pad, !isBarHidden else { return }
        guard bounds.width != lastBarLayoutWidth else { return }
        rebuildToolbar()
    }

    /// Splits the actions into the ones rendered as bar buttons vs. the ones
    /// living in the More menu.
    /// - iPhone: exactly the pinned set (≤5).
    /// - iPad: as many as the width fits, in pinned-then-overflow order, so a
    ///   wide screen shows them all by default.
    /// - Hidden: nothing in the bar — every action goes to the menu.
    private func currentSplit() -> (bar: [GameToolbarAction], menu: [GameToolbarAction]) {
        let actions = GameConfigSession.globalToolbarActions()
        var ordered = actions.pinned + actions.overflow

        let isPad = traitCollection.userInterfaceIdiom == .pad
        let barCount: Int
        if isBarHidden {
            barCount = 0
        } else if isPad {
            barCount = fittableBarButtonCount(for: ordered)
        } else {
            barCount = actions.pinned.count
        }

        // iPad default rule: anchor `setting` as the rightmost bar button (just
        // left of More), mirroring the iPhone default where it's the last pinned
        // item. Only while the user hasn't reordered the menu themselves.
        if isPad, !actions.isCustomized, barCount >= 1,
           let index = ordered.firstIndex(of: .setting), index != barCount - 1 {
            ordered.remove(at: index)
            ordered.insert(.setting, at: barCount - 1)
        }

        return (Array(ordered.prefix(barCount)), Array(ordered.dropFirst(barCount)))
    }

    private func rebuildToolbar() {
        let split = currentSplit()
        rebuildBar(split.bar)
        rebuildMoreMenu(split.menu)
    }

    /// How many of `ordered`'s buttons fit between close and more at the current
    /// width, summing each button's *actual* width (cached) rather than assuming
    /// they're all the close button's width. Falls back to "all" before the
    /// first layout pass (width unknown).
    private func fittableBarButtonCount(for ordered: [GameToolbarAction]) -> Int {
        guard bounds.width > 0, closeButton.bounds.width > 0 else { return ordered.count }

        let spacing: CGFloat = 20
        let closeTrailing = 20 + closeButton.bounds.width
        let moreLeading = bounds.width - 20 - moreButton.bounds.width
        // Reserve one spacing as the gap between close and the first button.
        let available = moreLeading - closeTrailing - spacing

        var used: CGFloat = 0
        var count = 0
        for action in ordered {
            used += barButtonWidth(for: action) + spacing
            if used > available { break }
            count += 1
        }
        return count
    }

    /// Rendered width of a bar button for `action`, measured once and cached.
    /// All actions use the same SF-Symbol config, so the width is stable across
    /// dynamic state (e.g. mute/lock icon swaps).
    private func barButtonWidth(for action: GameToolbarAction) -> CGFloat {
        if let cached = measuredButtonWidths[action] { return cached }
        let width = makeBarButton(for: action).bounds.width
        measuredButtonWidths[action] = width
        return width
    }

    /// Rebuilds the middle action buttons (`actions`, left → right). Chained
    /// right-to-left from `more`.
    private func rebuildBar(_ actions: [GameToolbarAction]) {
        barButtons.values.forEach { $0.removeFromSuperview() }
        barButtons.removeAll()
        lastBarLayoutWidth = bounds.width

        var lastTrailing: ConstraintItem = moreButton.snp.leading
        for action in actions.reversed() {
            let button = makeBarButton(for: action)
            addSubview(button)
            button.snp.makeConstraints { make in
                make.trailing.equalTo(lastTrailing).offset(-20)
                make.centerY.equalToSuperview()
                make.size.equalTo(button.size)
            }
            lastTrailing = button.snp.leading
            barButtons[action] = button
        }
    }

    // Toolbar icons sit directly over unpredictable game frames (a white sky can
    // wash out the whole bar). A soft dark shadow traces each glyph's alpha outline
    // so it stays legible on any scene without a background plate — keeping the
    // bare-icon look. Tune opacity/radius if it's too faint or too heavy.
    private static let iconShadowOpacity: Float = 0.6
    private static let iconShadowRadius: CGFloat = 2.5

    private func applyIconShadow(to button: UIButton) {
        guard let iv = button.imageView else { return }
        iv.layer.shadowColor = UIColor.black.cgColor
        iv.layer.shadowOpacity = Self.iconShadowOpacity
        iv.layer.shadowRadius = Self.iconShadowRadius
        iv.layer.shadowOffset = .zero
        iv.layer.masksToBounds = false
    }

    private func makeBarButton(for action: GameToolbarAction) -> UIButton {
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.setImage(UIImage(systemName: imageName(for: action)), for: .normal)
        applyIconShadow(to: button)
        if action == .lockLandscape {
            configureLockBacking(on: button)
            applyLockLandscapeStyle(to: button)
        }
        button.addAction(UIAction { [weak self] _ in self?.perform(action) }, for: .touchUpInside)
        button.isEnabled = isActionEnabled(action)
        if action == .cheat {
            addCheatBadge(to: button)
        }
        if action == .netplay {
            addNetplayBadge(to: button)
        }
        button.sizeToFit()
        return button
    }
}

// MARK: - Cheat active badge

extension GamePageToolbarView {
    /// Whether any cheat is currently enabled for this game.
    private func cheatHasActive() -> Bool {
        holder?.cheatSession?.hasActiveCheat ?? false
    }

    /// Adds a small green dot at the top-trailing corner of the cheat bar button,
    /// shown only while a cheat is active. Recreated whenever the bar rebuilds.
    private func addCheatBadge(to button: UIButton) {
        let dot = UIView()
        dot.backgroundColor = .systemGreen
        dot.layer.cornerRadius = Self.cheatBadgeSize / 2
        dot.layer.borderColor = UIColor.black.withAlphaComponent(0.35).cgColor
        dot.layer.borderWidth = 0.5
        dot.isUserInteractionEnabled = false
        dot.isHidden = !cheatHasActive()
        button.addSubview(dot)
        dot.snp.makeConstraints { make in
            make.width.height.equalTo(Self.cheatBadgeSize)
            make.top.equalToSuperview().offset(1)
            make.trailing.equalToSuperview().offset(-1)
        }
        cheatBadgeView = dot
    }

    private static let cheatBadgeSize: CGFloat = 8

    @objc
    private func cheatStateDidChange() {
        cheatBadgeView?.isHidden = !cheatHasActive()
    }
}

// MARK: - Netplay active badge

extension GamePageToolbarView {
    /// Whether a netplay session is currently active (hosting or connected).
    private func netplayHasActive() -> Bool {
        RANetplayCoordinator.shared.isNetplayEnabled
    }

    /// A reusable styled green dot, matching the cheat badge.
    private func makeBadgeDot() -> UIView {
        let dot = UIView()
        dot.backgroundColor = .systemGreen
        dot.layer.cornerRadius = Self.cheatBadgeSize / 2
        dot.layer.borderColor = UIColor.black.withAlphaComponent(0.35).cgColor
        dot.layer.borderWidth = 0.5
        dot.isUserInteractionEnabled = false
        return dot
    }

    /// Green dot on the netplay bar button (only when netplay is pinned).
    private func addNetplayBadge(to button: UIButton) {
        let dot = makeBadgeDot()
        dot.isHidden = !netplayHasActive()
        button.addSubview(dot)
        dot.snp.makeConstraints { make in
            make.width.height.equalTo(Self.cheatBadgeSize)
            make.top.equalToSuperview().offset(1)
            make.trailing.equalToSuperview().offset(-1)
        }
        netplayBadgeView = dot
    }

    /// Lazily attaches the More-button dot, then updates its visibility: shown when
    /// a session is active AND netplay sits in the More overflow (its default).
    /// When netplay is pinned, the bar button carries the dot instead.
    private func refreshMoreNetplayBadge() {
        if moreNetplayBadgeView == nil {
            let dot = makeBadgeDot()
            moreButton.addSubview(dot)
            dot.snp.makeConstraints { make in
                make.width.height.equalTo(Self.cheatBadgeSize)
                make.top.equalToSuperview().offset(1)
                make.trailing.equalToSuperview().offset(-1)
            }
            moreNetplayBadgeView = dot
        }
        let inMore = currentSplit().menu.contains(.netplay)
        moreNetplayBadgeView?.isHidden = !(netplayHasActive() && inMore)
    }

    @objc
    private func netplayStateDidChange() {
        netplayBadgeView?.isHidden = !netplayHasActive()
        // Rebuilds the More menu so the in-menu network icon reflects active state,
        // and refreshes the More-button dot.
        rebuildMoreMenu(currentSplit().menu)
    }
}

// MARK: - More menu

extension GamePageToolbarView {
    /// Builds the More menu from the actions that are *not* shown as bar
    /// buttons (computed by `currentSplit`): everything when hidden, the
    /// width/pin overflow otherwise.
    private func rebuildMoreMenu(_ menuActions: [GameToolbarAction]) {
        var sections: [UIMenuElement] = []

        let actionItems = menuActions.map(menuAction(for:))
        if !actionItems.isEmpty {
            sections.append(UIMenu(title: "", options: .displayInline, children: actionItems))
        }

    #if DEBUG
        sections.append(UIMenu(title: "", options: .displayInline, children: [pauseResumeMenuAction()]))
    #endif

        let editAction = UIAction(
            title: Bundle.localizedString(forKey: "gamepage_toolbar_edit_layout"),
            image: UIImage(systemName: "pencil.circle")
        ) { [weak self] _ in
            self?.editLayoutAction()
        }
        sections.append(UIMenu(title: "", options: .displayInline, children: [editAction]))

        let toggleKey = isBarHidden ? "gamepage_toolbar_show_menu" : "gamepage_toolbar_hide_menu"
        let toggleImage = isBarHidden ? "eye" : "eye.slash"
        let toggleAction = UIAction(
            title: Bundle.localizedString(forKey: toggleKey),
            image: UIImage(systemName: toggleImage)
        ) { [weak self] _ in
            self?.toggleHidden()
        }
        sections.append(UIMenu(title: "", options: .displayInline, children: [toggleAction]))

        moreButton.menu = UIMenu(title: "", children: sections)
        refreshMoreNetplayBadge()
    }

    private func menuAction(for action: GameToolbarAction) -> UIAction {
        let menuItem = UIAction(
            title: title(for: action),
            image: menuImage(for: action)
        ) { [weak self] _ in
            self?.perform(action)
        }
        if !isActionEnabled(action) {
            menuItem.attributes = .disabled
        }
        return menuItem
    }

    /// Menu-row icon. A UIMenu row can't host a floating dot subview, so an active
    /// netplay session is shown by rendering the `network` icon green instead.
    private func menuImage(for action: GameToolbarAction) -> UIImage? {
        let image = UIImage(systemName: imageName(for: action))
        if action == .netplay, netplayHasActive() {
            return image?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        }
        return image
    }

    /// Resolved title accounting for dynamic actions (`mute`, `lockLandscape`).
    private func title(for action: GameToolbarAction) -> String {
        switch action {
        case .mute:
            let key = isGameMuted ? "gamepage_toolbar_unmute" : "gamepage_toolbar_mute"
            return Bundle.localizedString(forKey: key)
        case .lockLandscape:
            let key = (holder?.isLandscapeLocked ?? false)
                ? "gamepage_toolbar_unlock_landscape"
                : "gamepage_toolbar_lock_landscape"
            return Bundle.localizedString(forKey: key)
        default:
            return action.title
        }
    }

    /// Resolved SF Symbol accounting for dynamic actions (`mute`, `lockLandscape`).
    private func imageName(for action: GameToolbarAction) -> String {
        switch action {
        case .mute:
            return isGameMuted ? "speaker.slash.circle" : "speaker.wave.2.circle"
        case .lockLandscape:
            // Direction-lock semantics intentionally win over the all-`.circle`
            // toolbar house style here: a plain circle lock doesn't say "screen
            // rotation". `lock.rotation` has no `.circle`/`.fill` variant, so the
            // open/closed pair conveys state — closed when locked to landscape,
            // open when free to rotate.
            return (holder?.isLandscapeLocked ?? false) ? "lock.rotation" : "lock.open.rotation"
        default:
            return action.systemImageName
        }
    }

#if DEBUG
    private func pauseResumeMenuAction() -> UIAction {
        let title = Bundle.localizedString(forKey: isGamePaused ? "gamepage_toolbar_resume" : "gamepage_toolbar_pause")
        let image = UIImage(systemName: isGamePaused ? "play.circle" : "pause.circle")
        return UIAction(title: title, image: image) { [weak self] _ in
            self?.pauseResumeAction()
        }
    }
#endif

    private func netplayAction() {
        let controller = GameNetplayViewController()
        let nav = UINavigationController(rootViewController: controller)
        holder?.present(nav, animated: true)
    }
}

// MARK: - Hide / show

extension GamePageToolbarView {
    private static let hideAnimationDuration: TimeInterval = 0.25

    private func toggleHidden() {
        Vibration.selection.vibrate()

        isBarHidden.toggle()
        GameConfigSession.setGlobalToolbarHidden(isBarHidden)

        let split = currentSplit()
        rebuildMoreMenu(split.menu)

        if isBarHidden {
            collapseBar()
        } else {
            expandBar(split.bar)
        }

        // Cross-dissolve the more icon (ellipsis ⇄ chevron.down.circle) and the
        // close/more tint between full and muted — blended smoothly by the
        // transition (tintColor itself isn't directly animatable).
        let tint: UIColor = isBarHidden ? hiddenTint : .label
        UIView.transition(with: moreButton, duration: Self.hideAnimationDuration, options: .transitionCrossDissolve) {
            self.moreButton.setImage(UIImage(systemName: self.isBarHidden ? "chevron.down.circle" : "ellipsis.circle"), for: .normal)
            self.moreButton.tintColor = tint
        }
        UIView.transition(with: closeButton, duration: Self.hideAnimationDuration, options: .transitionCrossDissolve) {
            self.closeButton.tintColor = tint
        }
    }

    /// Animates the existing pinned buttons collapsing toward `more`, then
    /// removes them. Called when transitioning shown → hidden.
    private func collapseBar() {
        let buttons = Array(barButtons.values)
        barButtons.removeAll()
        layoutIfNeeded()

        let moreCenterX = moreButton.center.x
        UIView.animate(withDuration: Self.hideAnimationDuration, delay: 0, options: .curveEaseIn) {
            for button in buttons {
                let dx = moreCenterX - button.center.x
                button.transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: 0.4, y: 0.4)
                button.alpha = 0
            }
        } completion: { _ in
            buttons.forEach { $0.removeFromSuperview() }
        }
    }

    /// Rebuilds the bar buttons and animates them expanding out from `more`.
    /// Called when transitioning hidden → shown.
    private func expandBar(_ actions: [GameToolbarAction]) {
        rebuildBar(actions)
        layoutIfNeeded()

        let moreCenterX = moreButton.center.x
        let buttons = Array(barButtons.values)
        for button in buttons {
            let dx = moreCenterX - button.center.x
            button.transform = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: 0.4, y: 0.4)
            button.alpha = 0
        }
        UIView.animate(withDuration: Self.hideAnimationDuration, delay: 0, options: .curveEaseOut) {
            for button in buttons {
                button.transform = .identity
                button.alpha = 1
            }
        }
    }
}

// MARK: - Action dispatch

extension GamePageToolbarView {
    private func perform(_ action: GameToolbarAction) {
        switch action {
        case .saveState: saveStateAction()
        case .loadState: loadStateAction()
        case .snap:          snapAction()
        case .mute:          muteAction()
        case .lockLandscape: lockLandscapeAction()
        case .setting:       settingAction()
        case .restart:       restartAction()
        case .cheat:         cheatAction()
        case .netplay:       netplayAction()
        }
    }

    private func updatePauseResumeAppearance() {
        rebuildMoreMenu(currentSplit().menu)
    }

    private func updateMuteButtonAppearance() {
        barButtons[.mute]?.setImage(UIImage(systemName: imageName(for: .mute)), for: .normal)
        rebuildMoreMenu(currentSplit().menu)
    }
}

// MARK: - Actions

extension GamePageToolbarView {
    private func saveStateAction() {
        Vibration.selection.vibrate()

        guard RetroArchX.shared().isCurrentCoreSupportsSavestate() else {
            return
        }

        guard let currentCoreItem = RetroArchX.shared().currentCoreItem else {
            return
        }

        // During a netplay session the blocking naming alert would pause the local
        // loop and stall the peer, so save instantly with an auto (timestamp) name.
        // The capture itself (core_serialize) is read-only and does not desync peers.
        if RANetplayCoordinator.shared.isNetplayEnabled {
            let rawName = DateFormatter.yyyyMMddHHmmss().string(from: Date())
            let ret = RetroRomFileManager.shared.saveState(rawName: rawName, showName: rawName, sha256: holder?.romItem?.sha256, romKey: holder?.romItem?.key, autoSave: false)
            let key = ret ? "gamepage_state_saved" : "gamepage_state_save_failed"
            let str = String(format: Bundle.localizedString(forKey: key), rawName)
            let msg = EmuInGameMessage(message: str, title: nil, type: ret ? .info : .error, duration: 3.5, priority: 0)
            holder?.inGameInfoView.showMessage(msg)
            return
        }

        guard let romPath = RetroArchX.shared().getCurrentRomPath(),
              let sha256 = FileManager.default.sha256ForFile(atPath: romPath) else {
            return
        }

        let allItems = RetroRomPersistence.shared.getGameStateItems(coreId: currentCoreItem.coreId, sha256: sha256) ?? []
        let manualItems = allItems.filter { !$0.isAutoSaved }
        let mode = GameStateListViewController.Mode.save { [weak self] rawName, showName, _ in
            self?.performSaveState(rawName: rawName, showName: showName)
        }
        let controller = GameStateListViewController(gameStateItems: manualItems, showClose: true, mode: mode)
        let naviController = UINavigationController(rootViewController: controller)
        holder?.present(naviController, animated: true)
    }

    @discardableResult
    private func performSaveState(rawName: String, showName: String) -> RetroRomGameStateItem? {
        let ret = RetroRomFileManager.shared.saveState(rawName: rawName, showName: showName, sha256: holder?.romItem?.sha256, romKey: holder?.romItem?.key, autoSave: false)
        let key = ret ? "gamepage_state_saved" : "gamepage_state_save_failed"
        let str = String(format: Bundle.localizedString(forKey: key), showName)
        let msg = EmuInGameMessage(message: str, title: nil, type: ret ? .info : .error, duration: 3.5, priority: 0)
        holder?.inGameInfoView.showMessage(msg)

        guard ret, let coreId = RetroArchX.shared().currentCoreItem?.coreId else { return nil }
        return RetroRomGameStateItem(rawName: rawName, coreId: coreId, showName: showName, romKey: holder?.romItem?.key, sha256: holder?.romItem?.sha256, createAt: Date())
    }

    private func loadStateAction() {
        Vibration.selection.vibrate()

        guard RetroArchX.shared().isCurrentCoreSupportsSavestate() else {
            return
        }

        // Netplay is host-authoritative for state loading: only the host may load
        // and broadcast a state to everyone. A client loading directly desyncs the
        // frame counters and drops the connection, so block it on the client side.
        let netplay = RANetplayCoordinator.shared
        if netplay.isNetplayEnabled, !netplay.isServer {
            let text = Bundle.localizedString(forKey: "netplay_load_host_only")
            let msg = EmuInGameMessage(message: text, title: nil, type: .warning, duration: 3.0, priority: 0)
            holder?.inGameInfoView.showMessage(msg)
            return
        }

        guard
            let currentCoreItem = RetroArchX.shared().currentCoreItem,
            let romPath = RetroArchX.shared().getCurrentRomPath(),
            let sha256 = FileManager.default.sha256ForFile(atPath: romPath) else {
            return
        }

        let items = RetroRomPersistence.shared.getGameStateItems(coreId: currentCoreItem.coreId, sha256: sha256) ?? []
        let controller = GameStateListViewController(gameStateItems: items, showClose: true)
        let naviController = UINavigationController(rootViewController: controller)
        holder?.present(naviController, animated: true)
    }

    private func snapAction() {
        Vibration.selection.vibrate()

        let nowString = DateFormatter.yyyyMMddHHmmss().string(from: Date())
        let pngName  = "snap-\(nowString).png"
        let snapPath = AppConfig.shared.snapshotFolder + pngName
        RetroArchX.shared().saveScreenshot(to: snapPath, notify: true)
    }

    private func pauseResumeAction() {
        Vibration.selection.vibrate()

        let success: Bool
        if isGamePaused {
            success = RetroArchX.shared().resume()
            if success {
                isGamePaused = false
            }
        } else {
            success = RetroArchX.shared().pause()
            if success {
                isGamePaused = true
            }
        }

        if success {
            updatePauseResumeAppearance()
        }
    }

    private func muteAction() {
        Vibration.selection.vibrate()

        let nextMuted = !isGameMuted
        if RetroArchX.shared().mute(nextMuted) {
            isGameMuted = nextMuted
            updateMuteButtonAppearance()
        }
    }

    private func lockLandscapeAction() {
        Vibration.selection.vibrate()

        holder?.toggleLandscapeLock()
        updateLockLandscapeAppearance()
    }

    private func updateLockLandscapeAppearance() {
        if let button = barButtons[.lockLandscape] {
            button.setImage(UIImage(systemName: imageName(for: .lockLandscape)), for: .normal)
            applyLockLandscapeStyle(to: button)
        }
        rebuildMoreMenu(currentSplit().menu)
    }

    /// Locked landscape shows a restrained translucent-white disc behind the glyph,
    /// not a saturated brand plate: a filled plate gives the state a background-
    /// independent anchor, but a brand color pulls the eye away from the game. A
    /// quiet white disc reads as "active" (especially over darker scenes) while
    /// staying out of the way; the open state is a bare glyph. Tune via constants.
    private static let lockBackingColor: UIColor = UIColor.white.withAlphaComponent(0.30)
    private static let lockBackingSize: CGFloat = 34

    private func configureLockBacking(on button: UIButton) {
        let backing = UIView()
        backing.backgroundColor = Self.lockBackingColor
        backing.layer.cornerRadius = Self.lockBackingSize / 2
        backing.isUserInteractionEnabled = false
        button.addSubview(backing)
        button.sendSubviewToBack(backing)
        backing.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(Self.lockBackingSize)
        }
        lockBackingView = backing
    }

    private func applyLockLandscapeStyle(to button: UIButton) {
        let locked = holder?.isLandscapeLocked ?? false
        lockBackingView?.isHidden = !locked
        // White glyph on the plate when locked; bare label-color glyph when free.
        button.tintColor = locked ? .white : .label
    }

    private func restartAction() {
        Vibration.selection.vibrate()

        RetroArchX.shared().reset()
    }

    private func settingAction() {
        Vibration.selection.vibrate()

        guard let session = holder?.configSession else { return }

        let controller = GameConfigViewController(session: session, applyInputBinding: false, showCloseButton: true)
        let naviController = UINavigationController(rootViewController: controller)
        holder?.present(naviController, animated: true)
    }

    private func cheatAction() {
        Vibration.selection.vibrate()

        guard let session = holder?.cheatSession else { return }

        let controller = GameCheatListViewController(session: session, showClose: true)
        let naviController = UINavigationController(rootViewController: controller)
        holder?.present(naviController, animated: true)
    }

    private func editLayoutAction() {
        Vibration.selection.vibrate()

        let controller = GameToolbarLayoutViewController()
        let naviController = UINavigationController(rootViewController: controller)
        holder?.present(naviController, animated: true)
    }

    @objc
    private func closeAction() {
        Vibration.selection.vibrate()

        // Drop the engine's cheat list so it never leaks into the next game. The
        // Swift/SQLite library is untouched; cheats are re-pushed on next launch.
        RetroArchX.shared().clearCheats()

        if AppSettings.shared.autoSaveLoadState {
            let name = RetroRomGameStateItem.getAutoSaveStateName(romItem: holder?.romItem)
            _ = RetroRomFileManager.shared.saveState(rawName: name, showName: nil, sha256: holder?.romItem?.sha256, romKey: holder?.romItem?.key, autoSave: true)
            holder?.romItem?.pulseImage = !(holder?.romItem?.pulseImage ?? false)
            RetroArchX.shared().stop()
        } else {
            RetroArchX.shared().stop()
        }

        holder?.romUrl?.stopAccessingSecurityScopedResource()
        holder?.dismiss(animated: true)
    }
}

// MARK: - Menu lifecycle button

/// A `UIButton` whose primary-action `UIMenu` reports when it opens and closes.
/// `UIButton` is its own `UIContextMenuInteractionDelegate` for the menu shown
/// by `showsMenuAsPrimaryAction`, so overriding these delegate hooks gives us
/// reliable open/close callbacks the plain `menu` API doesn't expose.
final class MenuLifecycleButton: UIButton {
    var onMenuWillShow: (() -> Void)?
    var onMenuWillHide: ((UIContextMenuInteractionAnimating?) -> Void)?

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onMenuWillShow?()
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onMenuWillHide?(animator)
    }
}
