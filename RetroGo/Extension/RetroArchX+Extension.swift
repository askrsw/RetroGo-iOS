//
//  RetroArchX+Extension.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

import ObjcHelper
import RACoordinator

// MARK: - Interface

extension RetroArchX {
    func playGame(romUrl: URL?, core: EmuCoreInfoItem) {
        guard let currentViewController = UIViewController.currentActive() else {
            return
        }

        showLoadingIndicator()

        DispatchQueue.main.async {
            let controller = GamePageViewController(romUrl: romUrl, core: core)
            controller.modalPresentationStyle = .fullScreen
            currentViewController.present(controller, animated: true) { [weak self] in
                self?.hideLoadingIndicator()
            }
        }
    }

    func playGame(romItem: RetroRomFileItem, core: EmuCoreInfoItem) {
        guard let currentViewController = UIViewController.currentActive() else {
            return
        }

        showLoadingIndicator()

        DispatchQueue.main.async {
            let controller = GamePageViewController(romItem: romItem, core: core)
            controller.modalPresentationStyle = .fullScreen
            currentViewController.present(controller, animated: true) { [weak self] in
                self?.hideLoadingIndicator()
            }
        }
    }
}

// MARK: - Utils

extension RetroArchX {
    static private let kIndicatorTag     = 0xABCD
    static private let kIndicatorMaskTag = 0xABCE

    private func showLoadingIndicator() {
        guard let window = UIWindow.currentKey() else {
            return
        }

        let mask = UIView(frame: window.bounds)
        mask.backgroundColor = .systemBackground
        mask.alpha = 0.875
        mask.tag = Self.kIndicatorMaskTag
        window.addSubview(mask)

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.tag = Self.kIndicatorTag
        indicator.sizeToFit()
        indicator.tintColor = .label
        window.addSubview(indicator)
        indicator.center = window.center

        indicator.startAnimating()
    }

    private func hideLoadingIndicator() {
        guard let window = UIWindow.currentKey() else {
            return
        }

        let indicator = window.viewWithTag(Self.kIndicatorTag) as? UIActivityIndicatorView

        indicator?.stopAnimating()
        indicator?.removeFromSuperview()

        let mask = window.viewWithTag(Self.kIndicatorMaskTag)
        mask?.removeFromSuperview()
    }
}
