//
//  RetroRomEmptyTipView.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/25.
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

final class RetroRomEmptyTipView: UIView {
    let imageView = UIImageView(image: UIImage(systemName: "tray"))
    let titleLabel = UILabel()
    let tipLabel = UILabel()
    let importButton = UIButton(type: .system)
    let legalLabel = UILabel()

    /// Fires when the primary "Import ROMs" action button is tapped.
    /// HomePageViewController wires this to its existing `addAction` so the
    /// CTA reaches the same import flow as the nav-bar `+` button.
    var onImportTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configUI()
        updateTipText()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTipText() {
        let paragraph: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraph.alignment = .center
        paragraph.lineSpacing = 4.0
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraph,
            .font: UIFont.systemFont(ofSize: 15, weight: .regular)
        ]

        titleLabel.text = Bundle.localizedString(forKey: "homepage_empty_title")

        let tip = Bundle.localizedString(forKey: "homepage_empty_tip")
        tipLabel.attributedText = NSAttributedString(string: tip, attributes: attributes)

        // UIButton.Configuration owns the title; update via attributedTitle
        // (consistent with how it was set originally) so the font weight
        // survives language switching.
        var config = importButton.configuration ?? .filled()
        var titleAttr = AttributeContainer()
        titleAttr.font = .systemFont(ofSize: 16, weight: .semibold)
        config.attributedTitle = AttributedString(
            Bundle.localizedString(forKey: "homepage_empty_action"),
            attributes: titleAttr
        )
        importButton.configuration = config

        legalLabel.text = Bundle.localizedString(forKey: "homepage_empty_legal")
    }

    private func configUI() {
        // All visual elements live inside a transparent container so we
        // can vertically center the whole composition as one block. The
        // container auto-sizes to its content (imageView at top → legal
        // at bottom), then a single centerY constraint positions it.
        //
        // A small -30pt offset pulls the content slightly above pure
        // geometric center: the inbox illustration is the heaviest visual
        // element so leaving the composition exactly centered makes the
        // optical center feel low.
        let container = UIView()
        addSubview(container)
        container.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview().offset(-30)
            // Soft safety: never overflow the view (rare on iPhone, can
            // happen if this tip view is hosted in a much smaller frame).
            make.top.greaterThanOrEqualToSuperview().offset(8)
            make.bottom.lessThanOrEqualToSuperview().offset(-8)
        }

        container.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
            make.size.equalTo(CGSize(width: 120, height: 120))
        }

        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        container.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.equalTo(imageView.snp.bottom).offset(18)
        }

        tipLabel.numberOfLines = 0
        tipLabel.lineBreakMode = .byWordWrapping
        tipLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        container.addSubview(tipLabel)
        tipLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            // Was 8pt — bumped to 12pt so the subtitle has breathing room
            // under the bold title.
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
        }

        // Primary CTA — filled pill button using the brand color. Sized
        // generously (240pt wide) so the action has visual weight close to
        // the inbox illustration above it, not just a thin chip.
        configureImportButton()
        container.addSubview(importButton)
        importButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            // Was 24pt — 32pt gives the action room to breathe.
            make.top.equalTo(tipLabel.snp.bottom).offset(32)
            make.height.equalTo(48)
            make.width.equalTo(240)
            // Safety: on extremely narrow widths, shrink to fit rather
            // than overflow the safe area.
            make.leading.greaterThanOrEqualToSuperview().offset(40)
            make.trailing.lessThanOrEqualToSuperview().offset(-40)
        }

        // Legal disclaimer — close enough to the button (48pt) to read as
        // its footer, not a separate orphaned element. Pinning bottom to
        // the container is what gives the container its intrinsic height.
        legalLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        legalLabel.textColor = .tertiaryLabel
        legalLabel.textAlignment = .center
        legalLabel.numberOfLines = 0
        legalLabel.lineBreakMode = .byWordWrapping
        container.addSubview(legalLabel)
        legalLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.top.equalTo(importButton.snp.bottom).offset(48)
            make.bottom.equalToSuperview()
        }
    }

    private func configureImportButton() {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .mainColor
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)

        // Leading icon — tray.and.arrow.down.fill deliberately echoes the
        // outline tray illustration above. The "filled" variant feels more
        // like a button affordance than the outline version.
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        config.image = UIImage(systemName: "tray.and.arrow.down.fill", withConfiguration: iconConfig)
        config.imagePadding = 8
        config.imagePlacement = .leading

        var titleAttr = AttributeContainer()
        titleAttr.font = .systemFont(ofSize: 16, weight: .semibold)
        config.attributedTitle = AttributedString(
            Bundle.localizedString(forKey: "homepage_empty_action"),
            attributes: titleAttr
        )
        importButton.configuration = config

        importButton.addAction(UIAction { [weak self] _ in
            self?.onImportTapped?()
        }, for: .touchUpInside)
    }
}
