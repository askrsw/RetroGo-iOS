//
//  WelcomeOfferFloatingView.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/2.
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

/// App-wide pill counting down the welcome offer. It sits just above the root
/// view, so presented pages (game, purchase page, sheets) cover it. Tapping it
/// opens the purchase page; it can be dragged and snaps to the nearest side.
@MainActor
final class WelcomeOfferFloatingView: UIControl {
    private static let edgeInset: CGFloat = 12
    private static let height: CGFloat = 40

    private weak var hostWindow: UIWindow?
    private let iconView = UIImageView(image: UIImage(systemName: "gift.fill"))
    private let label = UILabel()
    private var timer: Timer?
    /// Center set by dragging; nil keeps the default spot.
    private var draggedCenter: CGPoint?
    private var isDragging = false

    static func install(in window: UIWindow) {
        let view = WelcomeOfferFloatingView(window: window)
        window.addSubview(view)
        view.refresh()
    }

    private init(window: UIWindow) {
        hostWindow = window
        super.init(frame: .zero)
        configUI()

        NotificationCenter.default.addObserver(self, selector: #selector(stateDidChange), name: .appStoreWelcomeOfferDidStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stateDidChange), name: .appStorePurchaseStateDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func configUI() {
        backgroundColor = UIColor(hex: 0x8B5CF6, alpha: 1.0)
        layer.cornerRadius = Self.height / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
        isHidden = true

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false

        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.isUserInteractionEnabled = false

        addSubview(iconView)
        addSubview(label)

        addTarget(self, action: #selector(tapAction), for: .touchUpInside)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panAction(_:))))
    }

    @objc
    private func stateDidChange() {
        refresh()
    }

    private func refresh() {
        guard let remaining = AppStoreWelcomeOffer.remaining,
              !AppStoreProFeatureGate.shared.isProUnlocked else {
            isHidden = true
            timer?.invalidate()
            timer = nil
            return
        }

        keepAboveRootView()
        let formatter = Bundle.localizedString(forKey: "iap_welcome_offer_floating_format")
        label.text = String(format: formatter, AppStoreWelcomeOffer.formattedRemaining(remaining))
        isHidden = false
        if !isDragging {
            layoutPill()
        }

        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
    }

    /// The root view can be replaced (home page switch); stay right above it so
    /// modal presentations keep covering the pill.
    private func keepAboveRootView() {
        guard let window = hostWindow, let rootView = window.rootViewController?.view,
              rootView.superview == window else { return }
        let subviews = window.subviews
        guard let rootIndex = subviews.firstIndex(of: rootView),
              subviews.firstIndex(of: self) != rootIndex + 1 else { return }
        window.insertSubview(self, aboveSubview: rootView)
    }

    private func layoutPill() {
        guard let window = hostWindow else { return }
        let textSize = label.sizeThatFits(CGSize(width: 240, height: Self.height))
        let width = 14 + 18 + 6 + ceil(textSize.width) + 14
        bounds = CGRect(x: 0, y: 0, width: width, height: Self.height)
        iconView.frame = CGRect(x: 14, y: (Self.height - 18) / 2, width: 18, height: 18)
        label.frame = CGRect(x: 14 + 18 + 6, y: 0, width: ceil(textSize.width), height: Self.height)

        if let draggedCenter {
            center = clampedCenter(draggedCenter, in: window)
        } else {
            // Default: trailing side, above the tab bar area.
            let safe = window.safeAreaInsets
            center = CGPoint(x: window.bounds.width - safe.right - Self.edgeInset - width / 2,
                             y: window.bounds.height - safe.bottom - 140)
        }
    }

    private func clampedCenter(_ point: CGPoint, in window: UIWindow) -> CGPoint {
        let safe = window.safeAreaInsets
        let halfW = bounds.width / 2, halfH = bounds.height / 2
        let minX = safe.left + Self.edgeInset + halfW
        let maxX = window.bounds.width - safe.right - Self.edgeInset - halfW
        let minY = safe.top + Self.edgeInset + halfH
        let maxY = window.bounds.height - safe.bottom - Self.edgeInset - halfH
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    @objc
    private func tapAction() {
        Vibration.selection.vibrate()
        AppStoreProFeatureGate.shared.presentPurchasePage()
    }

    @objc
    private func panAction(_ gesture: UIPanGestureRecognizer) {
        guard let window = hostWindow else { return }
        switch gesture.state {
        case .began:
            isDragging = true
        case .changed:
            let translation = gesture.translation(in: window)
            center = clampedCenter(CGPoint(x: center.x + translation.x, y: center.y + translation.y), in: window)
            gesture.setTranslation(.zero, in: window)
        case .ended, .cancelled:
            isDragging = false
            // Snap to the nearer side.
            let snapX = center.x < window.bounds.midX ? 0 : window.bounds.width
            let target = clampedCenter(CGPoint(x: snapX, y: center.y), in: window)
            draggedCenter = target
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                self.center = target
            }
        default:
            break
        }
    }
}
