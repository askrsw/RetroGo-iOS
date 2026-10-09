//
//  GameOverlayFastSpeedBubble.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/9.
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

/// Fast-forward speed picker shown while the fast-forward button is held: a
/// bubble with the same shape as `GameConfigDescView` around the 2x/3x/4x/6x
/// control of the settings page. Picking a speed or tapping outside closes it.
final class GameOverlayFastSpeedBubble: UIView {
    private let cornerRadius: CGFloat = 12
    private let deltaHeight: CGFloat = 14
    private let sharpWidth: CGFloat = 15
    private let sharpRadius: CGFloat = 4
    private let padding: CGFloat = 10

    private let options: [Double]
    private let onSelect: (Double) -> Void
    private let shapeLayer = CAShapeLayer()
    private let control: UISegmentedControl
    private var dimmingView: OCMaskView?

    init(options: [Double], selected: Double, onSelect: @escaping (Double) -> Void) {
        self.options = options
        self.onSelect = onSelect
        self.control = UISegmentedControl(items: options.map { "\(Int($0))x" })
        super.init(frame: .zero)

        shapeLayer.shadowColor = UIColor.black.cgColor
        shapeLayer.shadowRadius = 8
        shapeLayer.shadowOffset = .zero
        shapeLayer.shadowOpacity = 0.3
        layer.addSublayer(shapeLayer)
        backgroundColor = .clear

        control.selectedSegmentIndex = options.firstIndex { abs($0 - selected) < 0.001 } ?? UISegmentedControl.noSegment
        control.addAction(UIAction { [weak self] _ in self?.picked() }, for: .valueChanged)
        addSubview(control)

        NotificationCenter.default.addObserver(self, selector: #selector(dismiss), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Shows the bubble in the key window, pointing at `sourceRect` (window coordinates).
    func present(pointingAt sourceRect: CGRect) {
        guard let window = UIWindow.currentKey() else { return }

        let controlSize = CGSize(width: max(control.intrinsicContentSize.width, CGFloat(options.count) * 56), height: 36)
        let size = CGSize(width: controlSize.width + padding * 2, height: controlSize.height + padding * 2 + deltaHeight)
        let safe = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: 8, dy: 8)

        let x = min(max(sourceRect.midX - size.width * 0.5, safe.minX), safe.maxX - size.width)
        // Above the button when there is room (the controls sit low), else below.
        let above = sourceRect.minY - size.height >= safe.minY
        let y = above ? sourceRect.minY - size.height : sourceRect.maxY
        frame = CGRect(x: x, y: y, width: size.width, height: size.height)

        let anchorInset = cornerRadius + sharpWidth / 2
        let anchor = CGPoint(x: min(max(sourceRect.midX - x, anchorInset), size.width - anchorInset), y: above ? size.height : 0)
        shapeLayer.frame = bounds
        // Elevated gray like the layout editor panel: plain systemBackground is black in
        // dark mode and would vanish over a dark game screen.
        shapeLayer.fillColor = UIColor.secondarySystemBackground.resolvedColor(with: window.traitCollection).cgColor
        shapeLayer.path = CGPath.makeContextShape(anchor: anchor, bounds: bounds, cornerRadius: cornerRadius,
                                                  deltaHeight: deltaHeight, sharpWidth: sharpWidth, sharpRadius: sharpRadius)
        control.frame = CGRect(x: padding, y: (above ? 0 : deltaHeight) + padding, width: controlSize.width, height: controlSize.height)

        let mask = OCMaskView { [weak self] in
            self?.dismiss()
            return true
        }
        mask.bkColor = UIColor.black.withAlphaComponent(0.1)
        mask.frame = window.bounds
        window.addSubview(mask)
        dimmingView = mask
        window.addSubview(self)

        alpha = 0
        transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.15) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    private func picked() {
        let index = control.selectedSegmentIndex
        guard options.indices.contains(index) else { return }
        Vibration.selection.vibrate()
        onSelect(options[index])
        // Let the selection show before closing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.dismiss() }
    }

    @objc private func dismiss() {
        dimmingView?.removeFromSuperview()
        dimmingView = nil
        UIView.animate(withDuration: 0.12, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
        }
    }
}
