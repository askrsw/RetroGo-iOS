//
//  RetroRomSectionHeaderView.swift
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
import SnapKit
import ObjcHelper
import RACoordinator

enum RetroRomSectionHeaderType {
    case tag(tag: RetroRomFileTag)
    case core(core: EmuCoreInfoItem)
}

final class RetroRomSectionHeaderView: UICollectionReusableView {
    static let sectionHeaderElementKind = "section-header-element-kind"

    private let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private var isCurrentlyBlured: Bool = false

    private let titleLabel = UILabel(frame: .zero)
    private let iconButton = UIButton(type: .system)
    private let countLabel = UILabel(frame: .zero)
    private let expandButton = UIButton(type: .system)

    private var countObservation: NSKeyValueObservation?

    var type: RetroRomSectionHeaderType? {
        didSet {
            if let type = type {
                switch type {
                    case .tag(let tag):
                        titleLabel.text = tag.showTitle
                        iconButton.setImage(tag.tagImage, for: .normal)
                        iconButton.tintColor = tag.showColor ?? .label
                        updateGameCount(tag.itemCount)
                        checkExpandStatus(animating: false)
                        countObservation = tag.observe(\.itemCount, options: .new, changeHandler: { [weak self] _, change in
                            guard let self = self, let count = change.newValue else { return }
                            DispatchQueue.main.async {
                                self.updateGameCount(count)
                            }
                        })
                    case .core(let core):
                        if core != .noneCore() {
                            titleLabel.text = core.coreName
                            iconButton.setImage(UIImage(systemName: "cpu"), for: .normal)
                            iconButton.tintColor = .mainColor
                        } else {
                            titleLabel.text = Bundle.localizedString(forKey: "homepage_unidentified_core")
                            iconButton.setImage(UIImage(systemName: "circle.slash"), for: .normal)
                            iconButton.tintColor = .label
                        }
                        updateGameCount(core.itemCount)
                        checkExpandStatus(animating: false)
                        countObservation = core.observe(\.itemCount, options: .new, changeHandler: { [weak self] _, change in
                            guard let self = self, let count = change.newValue else { return }
                            DispatchQueue.main.async {
                                self.updateGameCount(count)
                            }
                        })
                }
            } else {
                countObservation = nil
                titleLabel.text = nil
                countLabel.text = nil
                iconButton.setImage(nil, for: .normal)
            }
        }
    }

    weak var holder: RetroRomSectionFileBrowser?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapAction(_:)))
        self.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    deinit {
        countObservation = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurEffectView.frame = self.bounds.inset(by: .init(top: 0, left: -20, bottom: 10, right: -20))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        countObservation = nil
        isCurrentlyBlured = false
        blurEffectView.alpha = 0
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        guard let headerAttr = layoutAttributes as? RetroRomHeaderLayoutAttributes else { return }

        // 1. 核心逻辑：只有【钉住】+【展开】+【有货】才应该显示模糊
        let shouldShowBlurNow: Bool
        switch type {
        case .tag(let tag):
            shouldShowBlurNow = headerAttr.isPinned && tag.expanded && tag.itemCount > 0
        case .core(let core):
            shouldShowBlurNow = headerAttr.isPinned && core.expanded && core.itemCount > 0
        default:
            shouldShowBlurNow = false
        }

        // 2. 只有状态变化时才执行动画
        if self.isCurrentlyBlured != shouldShowBlurNow {
            self.isCurrentlyBlured = shouldShowBlurNow

            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                self.blurEffectView.alpha = shouldShowBlurNow ? 1.0 : 0.0
                self.backgroundColor = .clear
            }
        }
    }

    func checkExpandStatus(animating: Bool) {
        guard let type = type else { return }

        let expanded: Bool
        if case .tag(let tag) = type {
            expanded = tag.expanded
        } else if case .core(let core) = type {
            expanded = core.expanded
        } else {
            return
        }

        if animating {
            UIView.animate(withDuration: 0.1) { [unowned self] in
                if expanded {
                    expandButton.transform = CGAffineTransform(rotationAngle: .pi * 0.5)
                } else {
                    expandButton.transform = .identity
                }
            }
        } else {
            if expanded {
                expandButton.transform = CGAffineTransform(rotationAngle: .pi * 0.5)
            } else {
                expandButton.transform = .identity
            }
        }

        if !expanded {
            isCurrentlyBlured = false
            self.blurEffectView.alpha = 0
        }
    }

    func updateTagColor() {
        guard let type = type else { return }
        if case .tag(let tag) = type {
            iconButton.tintColor = tag.showColor ?? .label
        }
    }

    func updateTitle(_ text: String) {
        titleLabel.text = text
    }
}

extension RetroRomSectionHeaderView {
    private func updateGameCount(_ count: Int) {
        if count <= 0 {
            countLabel.text = nil
            countLabel.isHidden = true
            blurEffectView.alpha = 0
            isCurrentlyBlured = false
        } else {
            countLabel.isHidden = false
            countLabel.text = Bundle.localizedString(forKey: "homepage_game_count", count: count)
        }
    }

    private func configure() {
        iconButton.tintColor = .label
        iconButton.addTarget(self, action: #selector(coreButtonAction(_:)), for: .touchUpInside)
        addSubview(iconButton)
        iconButton.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview().offset(-5)
            make.size.equalTo(CGSize(width: 18, height: 18))
        }

        expandButton.setImage(UIImage(named: "Icon_chevron"), for: .normal)
        expandButton.addTarget(self, action: #selector(chevronButtonAction(_:)), for: .touchUpInside)
        addSubview(expandButton)
        expandButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalTo(iconButton)
            make.size.equalTo(CGSize(width: 30, height: 30))
        }

        countLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        countLabel.textColor = .secondaryLabel
        countLabel.adjustsFontForContentSizeCategory = true
        addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.trailing.equalTo(expandButton.snp.leading).offset(-10)
            make.centerY.equalTo(iconButton)
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconButton.snp.trailing).offset(10)
            make.centerY.equalTo(iconButton)
            make.trailing.lessThanOrEqualTo(countLabel.snp.leading).offset(-8)
        }

        // 设置抗压缩优先级：确保 countLabel 不会被长标题挤没
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 设置抗拉伸优先级：标题可以变长，但 countLabel 紧随其后
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        blurEffectView.frame = self.bounds
        blurEffectView.alpha = 0 // 默认隐藏
        self.insertSubview(blurEffectView, at: 0)

        self.backgroundColor = .clear
    }

    @objc
    private func tapAction(_ tap: UITapGestureRecognizer) {
        Vibration.selection.vibrate()

        // 1. 获取要做动画的 View (通常是 self)
        let targetView = self

        // 2. 创建一个覆盖整个视图的临时 View
        var overlayRect = targetView.bounds
        overlayRect = overlayRect.inset(by: .init(top: 0, left: -20, bottom: 10, right: -20))
        let overlay = UIView(frame: overlayRect)

        // 3. 设置高亮颜色（推荐用黑色或白色的半透明，这样能适配任何底色）
        // 0.1 ~ 0.2 的透明度通常比较合适
        overlay.backgroundColor = UIColor.label.withAlphaComponent(0.2)

        // 4.如果你原来的 View 有圆角，这里最好同步一下，否则高亮层会是直角的
        overlay.layer.cornerRadius = targetView.layer.cornerRadius
        // 如果 layer 是连续圆角，可以使用 cornerCurve
        if #available(iOS 13.0, *) {
            overlay.layer.cornerCurve = targetView.layer.cornerCurve
        }
        overlay.clipsToBounds = true

        // 5. 禁用交互，防止阻挡其他事件（虽然生命周期很短）
        overlay.isUserInteractionEnabled = false

        // 6. 添加到视图层级
        targetView.addSubview(overlay)

        // 7. 执行“立即出现，缓慢消失”的动画
        UIView.animate(withDuration: 0.6, delay: 0, options: [.curveEaseOut], animations: {
            // 动画目标：透明度变为 0
            overlay.alpha = 0.0
        }, completion: { _ in
            // 动画结束：从父视图移除，释放内存
            overlay.removeFromSuperview()
        })

        // 8. 实际执行的动作
        expandSection()
    }

    @objc
    private func coreButtonAction(_ sender: UIButton) {
        if case .core(let core) = type {
            Vibration.selection.vibrate()

            guard core != .noneCore(), let current = UIViewController.currentActive() else {
                return
            }

            let coreInfoViewController = RetroRomCoreInfoViewController(coreInfoItem: core, interactive: true)
            current.navigationController?.pushViewController(coreInfoViewController, animated: true)
        }
    }

    @objc
    private func chevronButtonAction(_ sender: UIButton) {
        Vibration.selection.vibrate()

        expandSection()
    }

    private func expandSection() {
        guard let type = type else { return }

        let key: String
        let show: Bool
        if case .tag(let tag) = type {
            tag.expanded.toggle()
            show = tag.expanded
            key = String(tag.id)
        } else if case .core(let core) = type {
            core.expanded.toggle()
            show = core.expanded
            key = core.coreId
        } else {
            return
        }

        holder?.toggleSection(key: key, show: show)
        checkExpandStatus(animating: true)
    }
}

class RetroRomHeaderLayoutAttributes: UICollectionViewLayoutAttributes {
    var isPinned: Bool = false

    // 必须重写此方法以支持拷贝
    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! RetroRomHeaderLayoutAttributes
        copy.isPinned = self.isPinned
        return copy
    }

    // 必须重写此方法用于比较，决定是否需要更新视图
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RetroRomHeaderLayoutAttributes else { return false }
        return super.isEqual(object) && other.isPinned == self.isPinned
    }
}

class StickyHeaderLayout: UICollectionViewCompositionalLayout {
    // 必须重写此方法，否则系统不会使用自定义的 Attributes 类
    override class var layoutAttributesClass: AnyClass {
        return RetroRomHeaderLayoutAttributes.self
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true // 保证滚动时不断重新计算属性
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let attributes = super.layoutAttributesForElements(in: rect)

        attributes?.forEach { attr in
            // 只处理我们的 Section Header
            if attr.representedElementKind == RetroRomSectionHeaderView.sectionHeaderElementKind,
               let headerAttr = attr as? RetroRomHeaderLayoutAttributes {

                guard let cv = collectionView else { return }

                // 关键判断：如果 Header 的视觉位置 y 等于 contentOffset + 边距，说明它被 Pin 住了
                let contentOffsetY = cv.contentOffset.y + cv.adjustedContentInset.top
                headerAttr.isPinned = attr.frame.origin.y <= contentOffsetY + 1
            }
        }
        return attributes
    }
}
