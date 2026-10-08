//
//  AppToastManager.swift
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

import UIKit
import YYText
import SnapKit
import ObjcHelper

enum AppToastLevel {
    case info
    case warning
    case error
    case success

    // Keep the color and icon logic here so the view stays minimal
    var themeColor: UIColor {
        switch self {
        case .info:    return .systemBlue
        case .warning: return .systemOrange
        case .error:   return .systemRed
        case .success: return .systemGreen
        }
    }
}

enum AppToastContext {
    case ui
    case game
}

final class AppToastManager {
    static let shared = AppToastManager()
    private init() { }

    private lazy var infoView = AppToastView()

    func toast(_ msg: String, context: AppToastContext, level: AppToastLevel, shouldVibrate: Bool = true) {
        runOnMainThread {
            self.show(msg, level: level)
        }
    }

    private func show(_ msg: String, level: AppToastLevel, shouldVibrate: Bool = true) {
        guard let window = UIWindow.currentKey() else { return }

        // 1. If the view isn't in the window yet, or its superview isn't the current window
        if infoView.superview == nil || infoView.superview != window {
            window.addSubview(infoView)

            // 2. Position it in the window (bottom center)
            infoView.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                // Some distance above the bottom safe area (e.g. 80pt)
                make.bottom.equalTo(window.safeAreaLayoutGuide.snp.bottom).offset(-50)
                // Cap the max width so it isn't too wide
                make.width.lessThanOrEqualTo(window).offset(-32)
                // Set a min width so it looks right
                make.width.greaterThanOrEqualTo(120)
            }
        }

        // 3. Bring the view to the front so other views don't cover it
        window.bringSubviewToFront(infoView)

        // 4. Show the content
        infoView.showMessage(msg, level: level)

        // 5. Haptic feedback
        if shouldVibrate {
            switch level {
                case .success: Vibration.success.vibrate()
                case .warning: Vibration.warning.vibrate()
                case .error: Vibration.error.vibrate()
                case .info: Vibration.selection.vibrate()
            }
        }
    }

    private func runOnMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async { block() }
        }
    }
}

// MARK: - AppToastView

fileprivate final class AppToastView: UIView {
    // MARK: - UI Components
    private let messageLabel = YYLabel()
    private let iconImageView = UIImageView()
    private let backgroundBlurView: UIVisualEffectView = {
        let effect = UIBlurEffect(style: .dark) // A dark frosted background makes the white text clearer
        let view = UIVisualEffectView(effect: effect)
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()

    // Timer for auto-hiding
    private var timer: Timer?

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup UI & SnapKit
    private func setupUI() {
        // 1. Base properties
        self.isUserInteractionEnabled = false // Let touches pass through

        // 2. Add the background (frosted glass)
        addSubview(backgroundBlurView)
        backgroundBlurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 3. Configure the icon
        iconImageView.contentMode = .scaleAspectFit
        addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(20)
        }

        // 4. Configure the label
        // Key: numberOfLines = 0 allows wrapping, and the constraints grow the height
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .left
        messageLabel.textVerticalAlignment = .center
        messageLabel.displaysAsynchronously = false // Turn off async drawing for simple text to avoid flicker
        addSubview(messageLabel)

        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(8)
            make.right.equalToSuperview().offset(-12)
            // Key point: the label's top/bottom insets decide the height of the whole view
            make.top.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().offset(-10)
        }

        // Hidden initially
        self.alpha = 0
        self.isHidden = true
    }

    // MARK: - Public Methods
    func showMessage(_ msg: String, level: AppToastLevel) {
        // 1. Set the content
        let icon = getIcon(for: level)
        let attributes = makeTextAttributes(color: .label)

        iconImageView.image = icon
        messageLabel.attributedText = NSAttributedString(string: msg, attributes: attributes)

        // 2. Handle showing
        self.isHidden = false
        // Animate in
        UIView.animate(withDuration: 0.25) {
            self.alpha = 1.0
        }

        // 3. Reset the timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 3.5, target: self, selector: #selector(hideTimerAction), userInfo: nil, repeats: false)

        // 4. For a YYLabel, setting preferredMaxLayoutWidth gives a more accurate height
        // Assumes the screen width minus the side margins (e.g. 32 + 32) and the inner padding
        let maxLabelWidth = UIScreen.main.bounds.width - 64 - 20 - 12 - 8 - 12
        messageLabel.preferredMaxLayoutWidth = maxLabelWidth
    }

    @objc private func hideTimerAction() {
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
        }) { _ in
            self.isHidden = true
            self.messageLabel.attributedText = nil
            self.iconImageView.image = nil
        }
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    private func getIcon(for level: AppToastLevel) -> UIImage? {
        let config = UIImage.SymbolConfiguration(paletteColors: [.white, level.themeColor])
        switch level {
        case .info:
            return UIImage(systemName: "info.circle.fill", withConfiguration: config)
        case .warning:
            return UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: config)
        case .error:
            return UIImage(systemName: "xmark.octagon.fill", withConfiguration: config)
        case .success:
            return UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
        }
    }

    private func makeTextAttributes(color: UIColor) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4 // A bit more line spacing
        style.lineBreakMode = .byWordWrapping // Allow wrapping
        return [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
    }
}
