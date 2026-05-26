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

final class RetroRomSectionParam: NSObject {
    var expanded: Bool = false
    var isHidden: Bool = false

    @objc
    dynamic var itemCount: Int = 0

    let type: RetroRomGameGroupType
    init(type: RetroRomGameGroupType) {
        self.type = type
        super.init()
    }

    var key: String {
        switch type {
        case .byTag(let tag): return String(tag.id)
        case .byCore(let core): return core.coreId
        }
    }

    var title: String {
        switch type {
        case .byCore(let core):
            if core == .noneCore() {
                return Bundle.localizedString(forKey: "homepage_unidentified_core")
            } else {
                return core.coreName
            }
        case .byTag(let tag): return tag.showTitle
        }
    }

    var icon: UIImage? {
        switch type {
        case .byTag(let tag): return tag.tagImage
        case .byCore(let core):
            let iconSize = CGSize(width: 22, height: 22)
            if core == .noneCore() {
                return IconRender.shared.settingsIcon(symbol: "questionmark", background: .systemGray, size: iconSize)
            } else if let platformKey = core.coreIcon {
                return IconRender.shared.platformIcon(key: platformKey, size: iconSize)
            } else {
                return UIImage(systemName: "cpu")
            }
        }
    }

    var tintColor: UIColor? {
        switch type {
        case .byCore(_): return nil
        case .byTag(let tag): return tag.showColor ?? .label
        }
    }
}

/// Minimal "header → host" callback contract used by
/// `RetroRomSectionHeaderView` to tell its owner that the user toggled
/// the expand/collapse chevron. Decouples the header from the legacy
/// `RetroRomSectionFileBrowser` protocol so the new architecture
/// (`RetroRomFolderByCoreSubview`, future `RetroRomFolderByTagSubview`)
/// can adopt the same header without inheriting the legacy browser's
/// shape.
///
/// `show == true` means the user wants the section expanded; `false`
/// means collapsed. The host is responsible for both:
///   1. Recording the new state on the model (`core.expanded` /
///      `tag.expanded`) — the header already does this in
///      `expandSection()` before calling us, so the holder reads
///      authoritative state from the model.
///   2. Re-applying the section's items to / removing them from the
///      diffable data source.
protocol RetroRomSectionHeaderHolder: AnyObject {
    func toggleSection(key: String, show: Bool)
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

    var param: RetroRomSectionParam? {
        didSet {
            if let param = param {
                titleLabel.text = param.title
                iconButton.setImage(param.icon, for: .normal)
                if let color = param.tintColor {
                    iconButton.tintColor = color
                }
                updateGameCount(param.itemCount)
                checkExpandStatus(animating: false)
                countObservation = param.observe(\.itemCount, options: .new, changeHandler: { [weak self] _, change in
                    guard let self = self, let count = change.newValue else { return }
                    DispatchQueue.main.async {
                        self.updateGameCount(count)
                    }
                })
            } else {
                countObservation = nil
                titleLabel.text = nil
                countLabel.text = nil
                iconButton.setImage(nil, for: .normal)
            }
        }
    }

    weak var holder: RetroRomSectionHeaderHolder?

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
        guard let headerAttr = layoutAttributes as? RetroRomHeaderLayoutAttributes, let param = param else { return }

        // 1. 核心逻辑：只有【钉住】+【展开】+【有货】才应该显示模糊
        let shouldShowBlurNow: Bool = headerAttr.isPinned && param.expanded && param.itemCount > 0

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
        guard let param = param else { return }

        let expanded: Bool = param.expanded

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
        guard let param = param else { return }
        iconButton.tintColor = param.tintColor
    }

    func updateTitle(_ text: String) {
        titleLabel.text = text
    }

    func languageChanged() {
        titleLabel.text = param?.title
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
        // 22×22 — same as the design-system nav-bar titleView icon size,
        // gives `IconRender` squircles enough room to read clearly while
        // staying balanced against the body-sized title label. Earlier
        // we had 18×18 with a tiny `cpu` SF Symbol; both the squircles
        // and SF Symbol glyphs felt too thin at that size.
        //
        // The 20pt horizontal inset lives inside the header (not on
        // `section.contentInsets`) so the section can keep its
        // horizontal contentInsets at 0 — the list cells already bake
        // 20pt into their own contentView constraints, and stacking
        // another 20pt at the section level would squeeze cells into
        // the middle 60% of the screen. With the inset baked into the
        // header instead, header subviews and cell content end up
        // perfectly aligned at the same 20pt-from-edge gutter.
        iconButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview().offset(-5)
            make.size.equalTo(CGSize(width: 22, height: 22))
        }

        expandButton.setImage(UIImage(named: "Icon_chevron"), for: .normal)
        expandButton.addTarget(self, action: #selector(chevronButtonAction(_:)), for: .touchUpInside)
        addSubview(expandButton)
        expandButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
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
        guard case .byCore(let core) = param?.type else {
            return
        }
        Vibration.selection.vibrate()

        guard core != .noneCore(), let current = UIViewController.currentActive() else {
            return
        }

        let coreInfoViewController = RetroRomCoreInfoViewController(coreInfoItem: core, interactive: true)
        current.navigationController?.pushViewController(coreInfoViewController, animated: true)
    }

    @objc
    private func chevronButtonAction(_ sender: UIButton) {
        Vibration.selection.vibrate()

        expandSection()
    }

    private func expandSection() {
        guard let param = param else { return }

        param.expanded.toggle()

        let key = param.key
        let show = param.expanded

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
