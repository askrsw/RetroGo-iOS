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

    // 将颜色和图标逻辑直接封装在这里，让 View 变得极简
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

        // 1. 如果 View 还没有添加到 Window 上，或者父视图不是当前 Window
        if infoView.superview == nil || infoView.superview != window {
            window.addSubview(infoView)

            // 2. 设置在 Window 上的位置 (底部居中)
            infoView.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                // 距离底部安全区域一定距离 (例如 80pt)
                make.bottom.equalTo(window.safeAreaLayoutGuide.snp.bottom).offset(-50)
                // 限制最大宽度，防止太宽
                make.width.lessThanOrEqualTo(window).offset(-32)
                // 限制最小宽度，美观
                make.width.greaterThanOrEqualTo(120)
            }
        }

        // 3. 将 View 移到最上层，防止被其他 View 遮挡
        window.bringSubviewToFront(infoView)

        // 4. 显示内容
        infoView.showMessage(msg, level: level)

        // 5. 震动反馈
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
        let effect = UIBlurEffect(style: .dark) // 使用深色磨砂背景让白色文字更清晰
        let view = UIVisualEffectView(effect: effect)
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        return view
    }()

    // Timer 用于自动隐藏
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
        // 1. 设置基础属性
        self.isUserInteractionEnabled = false // 允许点击穿透

        // 2. 添加背景 (毛玻璃效果)
        addSubview(backgroundBlurView)
        backgroundBlurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 3. 配置 Icon
        iconImageView.contentMode = .scaleAspectFit
        addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(20)
        }

        // 4. 配置 Label
        // 关键：numberOfLines = 0 允许换行，配合约束撑开高度
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .left
        messageLabel.textVerticalAlignment = .center
        messageLabel.displaysAsynchronously = false // 简单文本建议关闭异步绘制避免闪烁
        addSubview(messageLabel)

        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(8)
            make.right.equalToSuperview().offset(-12)
            // 关键点：Label 的上下边距决定了整个 View 的高度
            make.top.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().offset(-10)
        }

        // 初始隐藏
        self.alpha = 0
        self.isHidden = true
    }

    // MARK: - Public Methods
    func showMessage(_ msg: String, level: AppToastLevel) {
        // 1. 设置内容
        let icon = getIcon(for: level)
        let attributes = makeTextAttributes(color: .label)

        iconImageView.image = icon
        messageLabel.attributedText = NSAttributedString(string: msg, attributes: attributes)

        // 2. 处理显示逻辑
        self.isHidden = false
        // 动画显示
        UIView.animate(withDuration: 0.25) {
            self.alpha = 1.0
        }

        // 3. 重置计时器
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 3.5, target: self, selector: #selector(hideTimerAction), userInfo: nil, repeats: false)

        // 4. 如果是 YYLabel，为了更精准的高度计算，可以设置 preferredMaxLayoutWidth
        // 这里假设屏幕宽度减去左右边距 (例如 32 + 32) 和 内部 Padding
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
        style.lineSpacing = 4 // 增加一点行间距
        style.lineBreakMode = .byWordWrapping // 允许换行
        return [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
    }
}
