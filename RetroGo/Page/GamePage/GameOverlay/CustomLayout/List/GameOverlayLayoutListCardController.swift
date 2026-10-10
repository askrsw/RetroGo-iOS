//
//  GameOverlayLayoutListCardController.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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

/// Shows the layout list in game as a floating card at the top of the screen.
/// A bottom sheet would cover the controls, which sit low in portrait; with the
/// card the controls stay in sight and show each layout as it is picked.
/// The game stays paused while the card is open; tapping outside closes it.
final class GameOverlayLayoutListCardController: UIViewController {
    private let listController: GameOverlayLayoutListViewController
    private let card = UIView()
    private var pauseLease: GamePauseCoordinator.Lease?
    private var contentSizeObservation: NSKeyValueObservation?

    init(listController: GameOverlayLayoutListViewController) {
        self.listController = listController
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        contentSizeObservation?.invalidate()
        pauseLease?.release()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        pauseLease = GamePauseCoordinator.shared.acquire(reason: "overlay-layout-list")
        view.backgroundColor = .clear

        let background = UIControl()
        background.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        view.addSubview(background)
        background.snp.makeConstraints { make in make.edges.equalToSuperview() }

        card.backgroundColor = .systemGroupedBackground
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.35
        card.layer.shadowRadius = 16
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.addSubview(card)

        let navigation = UINavigationController(rootViewController: listController)
        navigation.view.layer.cornerRadius = 20
        navigation.view.layer.cornerCurve = .continuous
        navigation.view.clipsToBounds = true
        listController.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.close()
        })
        addChild(navigation)
        card.addSubview(navigation.view)
        navigation.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        navigation.didMove(toParent: self)

        // The card is as tall as the list, up to the limit in `layoutCard`.
        contentSizeObservation = listController.tableView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.layoutCard() }
        }
        layoutCard()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in self?.layoutCard(for: size) })
    }

    /// Portrait: across the top, over the game screen. Landscape: a centered
    /// column, between the controls on either side.
    private func layoutCard(for size: CGSize? = nil) {
        let size = size ?? view.bounds.size
        let isPortrait = size.width < size.height
        let tableView = listController.tableView!
        let contentHeight = tableView.contentSize.height + tableView.adjustedContentInset.top + tableView.adjustedContentInset.bottom
        let safeHeight = size.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 16
        // Portrait keeps the lower part, where the controls are, in sight.
        let maxHeight = isPortrait ? size.height * 0.55 : safeHeight
        let height = min(max(contentHeight, 160), maxHeight)
        card.snp.remakeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.centerX.equalToSuperview()
            make.height.equalTo(height)
            if isPortrait {
                make.width.equalTo(view.safeAreaLayoutGuide).offset(-24)
            } else {
                make.width.equalTo(min(420, size.width * 0.5))
            }
        }
    }

    func close(completion: (() -> Void)? = nil) {
        dismiss(animated: true) { [weak self] in
            self?.pauseLease?.release()
            self?.pauseLease = nil
            completion?()
        }
    }
}
