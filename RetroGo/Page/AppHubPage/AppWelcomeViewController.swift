//
//  AppWelcomeViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/23.
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

/// First-launch welcome sheet. Introduces RetroGo in three short feature
/// bullets and hands the user off to the empty state (which has its own
/// `Import ROMs` CTA). Shown once, then never again, controlled by
/// `AppSettings.shared.hasShownWelcome`.
///
/// Presented from `HomePageViewController.viewDidAppear`.
///
/// Dismissal contract: every exit path (X button, Get Started button,
/// swipe-down) goes through `markAsShownAndDismiss()` so the "seen" flag
/// is always set regardless of how the user closes the sheet.
final class AppWelcomeViewController: UIViewController {

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let closeButton = UIButton(type: .system)
    private let appIconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let featureStack = UIStackView()
    private let primaryButton = UIButton(type: .system)

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
            // Set the delegate on the sheet (which exists once
            // modalPresentationStyle is .pageSheet). Setting it on
            // `presentationController` directly at init time is racy —
            // that object is created lazily during actual presentation.
            sheet.delegate = self
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configUI()
        applyText()
    }
}

// MARK: - Static presenter

extension AppWelcomeViewController {

    /// Called once from `HomePageViewController.viewDidLoad`. Mirrors the
    /// `WhatsNewViewController.showIfNeeded()` pattern so first-launch
    /// presenters share a consistent shape:
    ///
    ///   1. Check the persisted "seen" flag, bail if true.
    ///   2. Wait 1s so the home page has finished its initial layout
    ///      (avoids a janky present-on-cold-launch animation).
    ///   3. Present from whichever VC is currently active.
    ///
    /// The flag is also set inside the VC's dismissal funnel, so even if
    /// the presentation succeeds but the user immediately backgrounds the
    /// app, the next launch won't show the welcome again.
    static func showIfNeeded() {
        guard !presentationPending else { return }
        guard !isCurrentlyDisplayed() else { return }
        guard !AppSettings.shared.hasShownWelcome else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard !presentationPending else { return }
            guard !isCurrentlyDisplayed() else { return }
            guard !AppSettings.shared.hasShownWelcome else { return }
            guard let presenter = UIViewController.currentActive() else { return }

            let controller = AppWelcomeViewController()
            presentationPending = true
            presenter.present(controller, animated: true) {
                presentationPending = false
            }
        }
    }

    /// Re-entrancy guard for the 1s delayed present block. Touched only
    /// on the main thread, matching the same pattern used by
    /// `WhatsNewViewController.presentationPending`.
    private static var presentationPending: Bool = false

    private static func isCurrentlyDisplayed() -> Bool {
        UIViewController.currentActive() is AppWelcomeViewController
    }
}

// MARK: - UI

private extension AppWelcomeViewController {

    func configUI() {
        // Scroll view fills the whole sheet — content is short on most
        // devices but needs to scroll on iPhone SE / large Dynamic Type.
        view.addSubview(scrollView)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.frameLayoutGuide.snp.width)
        }

        // Top-right close button — circular gray squircle matching the
        // existing modal-close pattern used elsewhere in the app.
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.backgroundColor = .tertiarySystemFill
        closeButton.layer.cornerRadius = 15
        closeButton.addAction(UIAction { [weak self] _ in
            self?.markAsShownAndDismiss()
        }, for: .touchUpInside)
        contentView.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.size.equalTo(30)
        }

        // App icon — pulled from the actual AppIcon asset so this stays
        // in sync with whatever ships in the App Store, not a separately
        // maintained copy. 80pt with a 22% corner radius (same as iOS
        // home-screen icon proportions) for instant brand recognition.
        appIconView.image = Self.bundleAppIcon()
        appIconView.contentMode = .scaleAspectFit
        appIconView.layer.cornerRadius = 80 * 0.22
        // Match iOS home-screen icon shape (superellipse / squircle), not
        // a plain circular arc. The visual difference is subtle but
        // perceptible at 80pt — the corners look "rounder" and softer.
        appIconView.layer.cornerCurve = .continuous
        appIconView.layer.masksToBounds = true
        contentView.addSubview(appIconView)
        appIconView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(40)
            make.centerX.equalToSuperview()
            make.size.equalTo(80)
        }

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(appIconView.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        contentView.addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        // Feature stack — three rows, each: squircle icon + (title +
        // description). The icons reuse the `settingsIcon` API so this
        // page shares the same visual language as the AppHub list.
        featureStack.axis = .vertical
        featureStack.spacing = 24
        featureStack.alignment = .fill
        contentView.addSubview(featureStack)
        featureStack.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(40)
            make.leading.trailing.equalToSuperview().inset(32)
        }

        featureStack.addArrangedSubview(makeFeatureRow(
            symbol: "sparkles",
            color: .mainColor,
            titleKey: "welcome_feature_native_title",
            descKey:  "welcome_feature_native_desc"
        ))
        featureStack.addArrangedSubview(makeFeatureRow(
            symbol: "memorychip.fill",
            color: .systemBlue,
            titleKey: "welcome_feature_platforms_title",
            descKey:  "welcome_feature_platforms_desc"
        ))
        featureStack.addArrangedSubview(makeFeatureRow(
            symbol: "tray.and.arrow.down.fill",
            color: .systemOrange,
            titleKey: "welcome_feature_roms_title",
            descKey:  "welcome_feature_roms_desc"
        ))

        // Primary CTA — identical styling to the empty-state import
        // button (240×48 capsule, mainColor). The user sees the same
        // button shape transition from welcome → empty state, which
        // reinforces "the action continues".
        configurePrimaryButton()
        contentView.addSubview(primaryButton)
        primaryButton.snp.makeConstraints { make in
            make.top.equalTo(featureStack.snp.bottom).offset(40)
            make.centerX.equalToSuperview()
            make.width.equalTo(240)
            make.height.equalTo(48)
            make.leading.greaterThanOrEqualToSuperview().offset(32)
            make.trailing.lessThanOrEqualToSuperview().offset(-32)
            // Bottom-pinned so the scroll content has the right size.
            make.bottom.equalToSuperview().offset(-32)
        }
    }

    func makeFeatureRow(
        symbol: String,
        color: UIColor,
        titleKey: String,
        descKey: String
    ) -> UIView {
        let iconSize = CGSize(width: 32, height: 32)
        let iconView = UIImageView(image: IconRender.shared.settingsIcon(
            symbol: symbol,
            background: color,
            size: iconSize
        ))
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.snp.makeConstraints { make in
            make.size.equalTo(iconSize)
        }

        let title = UILabel()
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .label
        title.numberOfLines = 0
        title.text = Bundle.localizedString(forKey: titleKey)

        let desc = UILabel()
        desc.font = .systemFont(ofSize: 14, weight: .regular)
        desc.textColor = .secondaryLabel
        desc.numberOfLines = 0
        desc.text = Bundle.localizedString(forKey: descKey)

        let textStack = UIStackView(arrangedSubviews: [title, desc])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .fill

        let row = UIStackView(arrangedSubviews: [iconView, textStack])
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .top
        return row
    }

    func configurePrimaryButton() {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .mainColor
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)

        var titleAttr = AttributeContainer()
        titleAttr.font = .systemFont(ofSize: 16, weight: .semibold)
        config.attributedTitle = AttributedString(
            Bundle.localizedString(forKey: "welcome_action"),
            attributes: titleAttr
        )
        primaryButton.configuration = config

        primaryButton.addAction(UIAction { [weak self] _ in
            Vibration.selection.vibrate()
            self?.markAsShownAndDismiss()
        }, for: .touchUpInside)
    }

    func applyText() {
        titleLabel.text = Bundle.localizedString(forKey: "welcome_title")
        subtitleLabel.text = Bundle.localizedString(forKey: "welcome_subtitle")
    }
}

// MARK: - Dismissal

private extension AppWelcomeViewController {

    /// Single funnel for every dismissal path. Marks the welcome as seen
    /// THEN dismisses, so even if the dismissal animation is cancelled
    /// the flag survives.
    func markAsShownAndDismiss() {
        AppSettings.shared.hasShownWelcome = true
        dismiss(animated: true)
    }
}

extension AppWelcomeViewController: UISheetPresentationControllerDelegate {
    /// Catches swipe-down dismissal. UIKit calls this AFTER the sheet is
    /// already gone, so we only need to flip the flag — no dismiss call
    /// (would be a no-op anyway).
    ///
    /// `UISheetPresentationControllerDelegate` inherits from
    /// `UIAdaptivePresentationControllerDelegate`, so this method
    /// satisfies both contracts.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        AppSettings.shared.hasShownWelcome = true
    }
}

// MARK: - App icon resolution

private extension AppWelcomeViewController {

    /// Extract the shipping AppIcon image from Info.plist's `CFBundleIcons`
    /// dictionary. Xcode auto-populates this when an `AppIcon` asset is
    /// configured, so it's the cleanest runtime-accurate source.
    ///
    /// Falls back to the `Icon_symbol` brand mark if the lookup fails (e.g.
    /// running in a context where Info.plist isn't fully populated).
    static func bundleAppIcon() -> UIImage? {
        if let icons   = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files   = primary["CFBundleIconFiles"] as? [String],
           let last    = files.last,
           let image   = UIImage(named: last) {
            return image
        }
        return UIImage(named: "Icon_symbol")
    }
}
