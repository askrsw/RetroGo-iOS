//
//  RetroRomFolderTitleView.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/26.
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

/// Custom navigation-bar `titleView` for non-root
/// `RetroRomFolderHostViewController` instances.
///
/// Visual layout (left to right):
///
///     [organize-mode icon]  [folder name]  [chevron.down]
///
/// Tapping anywhere on the title opens the bound `menu` (typically the
/// folder-action menu: Import / New Folder / Sort By submenu — same one
/// fed to the subview's blank-area context menu). The chevron is a pure
/// affordance hint; the entire title surface is the tap target.
///
/// ## Why a custom view instead of `navigationItem.title`
///
/// `navigationItem.title` only supports plain text. We want three things
/// the system title can't do:
///
/// 1. **A leading icon** that reflects the current `OrganizeMode`. Same
///    motif as the core-info page's title (small icon + bold text) —
///    the "Visual continuity across navigation transitions" rule from
///    `12_ui_design_system.md`.
/// 2. **A chevron** signaling "tap to act on this folder."
/// 3. **A menu binding** anchored to the title button so iOS auto-
///    positions the popover.
///
/// ## Root vs. non-root
///
/// This view is **only** installed on non-root hosts. Root uses
/// `prefersLargeTitles` + plain `navigationItem.title` so the "library"
/// landing page feels like the iOS Files browse tab. Subfolder pages
/// get this compact title — same trade-off the Files app makes.
///
/// ## Tap implementation
///
/// A transparent `UIButton` overlays the visible elements (icon, label,
/// chevron) and owns the menu via `showsMenuAsPrimaryAction = true`.
/// The icon/label/chevron are z-ordered below the button so they render
/// but don't intercept touches — the entire title rectangle opens the
/// menu, not just the chevron. Selection haptic fires on `.touchDown`
/// so the tick lands the instant the menu starts to present, matching
/// the nav-bar config button's feel.
final class RetroRomFolderTitleView: UIView {

    // MARK: - Public properties

    /// Folder display name shown in the center. Setting invalidates the
    /// intrinsic content size so the nav bar relayouts the title region
    /// to fit the new text width.
    var title: String? {
        didSet {
            guard title != oldValue else { return }
            titleLabel.text = title
            invalidateIntrinsicContentSize()
        }
    }

    /// Leading organize-mode icon — caller supplies the appropriate
    /// SF Symbol (`folder` / `cpu` / `tag`) or a same-size custom drawing
    /// (e.g. `IconRender.shared.treeSymbol(size:)`). Tinted by
    /// `iconTintColor` (defaults to `.mainColor`).
    ///
    /// Kept as a property rather than baked into init so the host can
    /// flip it on `OrganizeMode` changes without rebuilding the view.
    var icon: UIImage? {
        didSet { leadingIconView.image = icon }
    }

    /// Menu opened on tap. `nil` removes the binding (the chevron is
    /// still drawn — it's a static visual cue — but taps no-op).
    /// Re-assigning is cheap: UIButton just stores the reference.
    var menu: UIMenu? {
        didSet { tapButton.menu = menu }
    }

    // MARK: - Subviews

    private let leadingIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .mainColor
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        // 17pt semibold matches the system small-title font weight on
        // iOS 15+. Going through `.systemFont(ofSize:weight:)` keeps the
        // SF variant + dynamic type behavior consistent with system titles.
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        // Strong hugging so the label doesn't expand beyond its text and
        // push the chevron away from the title — we want chevron immediately
        // adjacent to text, not floating at the right edge.
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    /// Circular fill behind the chevron — same subtle grey as iOS Files'
    /// title chevron. Drawn as its own UIView (rather than via a single
    /// `chevron.down.circle.fill` SF Symbol) so we can independently
    /// control the chevron's color, the fill's color, and any future
    /// press / hover affordances without fighting the SF Symbol's
    /// internal palette-layer ordering.
    private let chevronCircleView: UIView = {
        let v = UIView()
        v.backgroundColor = .tertiarySystemFill
        // `cornerRadius = half side` makes the 20×20 square a circle.
        // Hardcoded rather than computed in `layoutSubviews` because the
        // view's size is fixed by a SnapKit constant constraint.
        v.layer.cornerRadius = 10
        // Tap button (the menu trigger) sits on top of this view in the
        // z-order; explicit `false` keeps any future hit-test changes
        // from accidentally letting taps die here.
        v.isUserInteractionEnabled = false
        return v
    }()

    private let chevronImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .secondaryLabel
        // 10pt symbol inside a 20pt circle leaves a ~5pt halo on each
        // side — visually consistent with what iOS Files draws.
        iv.image = UIImage(systemName: "chevron.down",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 10,
                                                                          weight: .semibold))
        iv.isUserInteractionEnabled = false
        return iv
    }()

    /// Transparent overlay that owns the menu + tap. Layered above the
    /// visible elements so it gets all touches; visible elements purely
    /// render. `.custom` type (not `.system`) so it doesn't apply the
    /// "fade content on touch-down" tint that would look wrong over our
    /// own subviews.
    private let tapButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    // MARK: - Layout constants

    private let iconSize: CGFloat = 22
    // 20pt is the outer diameter of the chevron's circular background,
    // matching iOS Files' title-chevron metrics.
    private let chevronSize: CGFloat = 20
    private let iconToTitlePadding: CGFloat = 6
    private let titleToChevronPadding: CGFloat = 6

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func configure() {
        // Order matters: tapButton added LAST so it sits on top of the
        // visible elements in the z-order and absorbs hits across the
        // whole title region.
        addSubview(leadingIconView)
        addSubview(titleLabel)
        addSubview(chevronCircleView)
        chevronCircleView.addSubview(chevronImageView)
        addSubview(tapButton)

        leadingIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: iconSize, height: iconSize))
        }
        chevronCircleView.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: chevronSize, height: chevronSize))
        }
        chevronImageView.snp.makeConstraints { make in
            // Center inside the circle. Symbol is 10pt; the 5pt halo is
            // automatic since the symbol image is smaller than the
            // 20-point container.
            make.center.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(leadingIconView.snp.trailing).offset(iconToTitlePadding)
            make.trailing.equalTo(chevronCircleView.snp.leading).offset(-titleToChevronPadding)
            make.centerY.equalToSuperview()
            make.top.bottom.equalToSuperview()
        }
        tapButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Tap-down handler: haptic tick + press-feedback animation.
        // With `showsMenuAsPrimaryAction = true`, UIKit starts
        // presenting the menu on touch-down — so this fires at the
        // user-perceived moment of "menu just appeared."
        //
        // We DON'T hook `.touchUpInside` for the spring-back: when a
        // menu is being presented, the button's normal touch-cycle
        // events are interrupted (UIKit hands control to the menu's
        // gesture system), so `.touchUpInside` is unreliable. Instead
        // the animation is self-contained — scale-down then spring-back
        // happens autonomously over ~0.45s without needing a release
        // event.
        tapButton.addAction(UIAction { [weak self] _ in
            Vibration.selection.vibrate()
            self?.playPressAnimation()
        }, for: .touchDown)
    }

    // MARK: - Press animation

    /// Subtle scale-down + spring-back, matching iOS Files' title-tap
    /// feedback. The whole title view (icon + label + chevron circle)
    /// scales as one because `transform` cascades through the view
    /// hierarchy — no per-subview animation needed.
    ///
    /// Phase 1 (~0.10s): smooth ease-out scale to 0.92, no overshoot.
    /// Phase 2 (~0.35s): spring back to identity with damping 0.55,
    /// producing a single visible wobble cycle.
    private func playPressAnimation() {
        UIView.animate(withDuration: 0.10,
                       delay: 0,
                       options: [.curveEaseOut,
                                 .allowUserInteraction,
                                 .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        } completion: { _ in
            UIView.animate(withDuration: 0.35,
                           delay: 0,
                           usingSpringWithDamping: 0.55,
                           initialSpringVelocity: 0.6,
                           options: [.allowUserInteraction,
                                     .beginFromCurrentState]) {
                self.transform = .identity
            }
        }
    }

    // MARK: - Sizing

    /// `UINavigationBar` reads `intrinsicContentSize` to decide how much
    /// horizontal space to give the titleView. Auto-layout-only sizing
    /// is unreliable for `navigationItem.titleView` (it's a known
    /// UIKit edge case across iOS versions), so we compute the width
    /// explicitly from icon + paddings + measured text + chevron.
    ///
    /// Height is locked to `iconSize` — title text never exceeds it
    /// within the nav-bar's title region.
    override var intrinsicContentSize: CGSize {
        let textWidth: CGFloat = {
            guard let text = title, !text.isEmpty else { return 0 }
            let attrs: [NSAttributedString.Key: Any] = [.font: titleLabel.font!]
            return (text as NSString).size(withAttributes: attrs).width.rounded(.up)
        }()
        let width = iconSize
                  + iconToTitlePadding
                  + textWidth
                  + titleToChevronPadding
                  + chevronSize
        return CGSize(width: width, height: iconSize)
    }
}
