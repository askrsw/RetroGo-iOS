//
//  DiscoverGameHeaderView.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/20.
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
import RACoordinator

// ---------------------------------------------------------------------------
// MARK: - DiscoverGameHeaderView
//
// Used as the tableHeaderView on the Game Detail page.
// Shows: cover art (placeholder until real image loads) + game title + platform.
// ---------------------------------------------------------------------------

final class DiscoverGameHeaderView: UIView {

    // MARK: - Layout constants

    static let coverWidth:  CGFloat = 120
    static let coverHeight: CGFloat = 160
    static let totalHeight: CGFloat = 260

    // MARK: - Subviews

    /// Gradient strip behind the cover: solid colour at top → clear at bottom.
    /// Works in both light and dark mode without opacity hacks.
    private let backdropGradient: CAGradientLayer = {
        let g = CAGradientLayer()
        g.locations = [0, 1]
        g.startPoint = CGPoint(x: 0.5, y: 0)
        g.endPoint   = CGPoint(x: 0.5, y: 1)
        return g
    }()

    private let backdropView: UIView = {
        let v = UIView()
        return v
    }()

    /// Transparent container whose only job is to cast a shadow.
    /// Must sit below coverImageView in z-order and share the same frame.
    /// Shadow + masksToBounds = true cannot coexist on one layer, so we use
    /// two layers: this one has the shadow, coverImageView clips content.
    private let coverShadowView: UIView = {
        let v = UIView()
        v.backgroundColor       = .clear
        v.layer.cornerRadius    = 10
        v.layer.shadowColor     = UIColor.black.cgColor
        v.layer.shadowOffset    = CGSize(width: 0, height: 4)
        v.layer.shadowOpacity   = 0.25
        v.layer.shadowRadius    = 8
        v.layer.masksToBounds   = false
        v.isHidden              = true   // shown only when cover image is set
        return v
    }()

    /// The cover image view — clips content to cornerRadius via masksToBounds.
    let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode        = .scaleAspectFill
        iv.clipsToBounds      = true       // masksToBounds = true → clips to cornerRadius
        iv.layer.cornerRadius = 10
        return iv
    }()

    /// Colored placeholder shown when no cover image is available.
    private let placeholderView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.clipsToBounds = true
        return v
    }()

    private let placeholderLabel: UILabel = {
        let l = UILabel()
        l.font          = .systemFont(ofSize: 48, weight: .semibold)
        l.textColor     = UIColor.white.withAlphaComponent(0.9)
        l.textAlignment = .center
        return l
    }()

    // MARK: - Loading overlay (shown while cover art is being fetched)

    private let loadingContainerView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        v.layer.cornerRadius = 10
        v.clipsToBounds = true
        v.isHidden = true
        return v
    }()

    private let loadingSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        return s
    }()

    private let loadingLabel: UILabel = {
        let l = UILabel()
        l.text          = "正在加载游戏封面"
        l.font          = .systemFont(ofSize: 11)
        l.textColor     = UIColor.white.withAlphaComponent(0.85)
        l.textAlignment = .center
        return l
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font          = .systemFont(ofSize: 17, weight: .semibold)
        l.textColor     = .label
        l.textAlignment = .center
        l.numberOfLines = 3
        l.lineBreakMode = .byWordWrapping
        return l
    }()

    private let platformLabel: UILabel = {
        let l = UILabel()
        l.font          = .systemFont(ofSize: 13)
        l.textColor     = .secondaryLabel
        l.textAlignment = .center
        return l
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backdropView.layer.addSublayer(backdropGradient)
        addSubview(backdropView)
        addSubview(placeholderView)
        placeholderView.addSubview(placeholderLabel)
        addSubview(coverShadowView)   // shadow layer — must be below coverImageView
        addSubview(coverImageView)    // image layer — clips to cornerRadius
        // Loading overlay sits on top of placeholderView
        addSubview(loadingContainerView)
        loadingContainerView.addSubview(loadingSpinner)
        loadingContainerView.addSubview(loadingLabel)
        addSubview(nameLabel)
        addSubview(platformLabel)

        backdropView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.coverHeight + 40)
        }

        placeholderView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.centerX.equalToSuperview()
            make.width.equalTo(Self.coverWidth)
            make.height.equalTo(Self.coverHeight)
        }

        placeholderLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Shadow view and image view both match the placeholder frame.
        // coverShadowView is below coverImageView in z-order (added first).
        coverShadowView.snp.makeConstraints { make in
            make.edges.equalTo(placeholderView)
        }

        coverImageView.snp.makeConstraints { make in
            make.edges.equalTo(placeholderView)
        }

        // Loading overlay matches the placeholder frame
        loadingContainerView.snp.makeConstraints { make in
            make.edges.equalTo(placeholderView)
        }

        loadingSpinner.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-10)
        }

        loadingLabel.snp.makeConstraints { make in
            make.top.equalTo(loadingSpinner.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(8)
        }

        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(placeholderView.snp.bottom).offset(16)
            make.leading.equalToSuperview().offset(24)
            // Lower priority so the system's UIView-Encapsulated-Layout-Width (required)
            // wins during the brief window when tableHeaderView width is still 0.
            make.trailing.equalToSuperview().offset(-24).priority(750)
        }

        platformLabel.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(6)
            make.leading.equalToSuperview().offset(24)
            make.trailing.equalToSuperview().offset(-24).priority(750)
            // Critical: closes the vertical chain so systemLayoutSizeFitting
            // can compute the header's intrinsic height correctly.
            make.bottom.equalToSuperview().offset(-24)
        }
    }

    // MARK: - Configure

    func configure(game: RAGameEntry, platformName: String) {
        nameLabel.text     = game.name
        platformLabel.text = platformName

        let color = DiscoverGameCell.placeholderColor(for: game.name)

        // Gradient: opaque theme colour → fully transparent (reveals systemGroupedBackground)
        backdropGradient.colors = [
            color.withAlphaComponent(0.55).cgColor,
            color.withAlphaComponent(0.0).cgColor,
        ]
        placeholderView.backgroundColor = color
        placeholderLabel.text = game.name.first.map { String($0).uppercased() } ?? "#"

        // Reset state for each new game.
        backdropView.alpha        = 1       // restored in case a previous cover faded it
        placeholderLabel.isHidden = false   // show letter until loading starts
        coverImageView.image      = nil
        coverImageView.isHidden   = true
        coverShadowView.isHidden  = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdropGradient.frame = backdropView.bounds
        // Explicit shadowPath avoids an implicit shadow-bounds query on every frame.
        // Must be updated whenever the bounds change (i.e. here).
        coverShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: coverShadowView.bounds, cornerRadius: 10).cgPath
    }

    // MARK: - Loading indicator control

    func showLoadingIndicator() {
        // Hide the initial letter/character so only the solid colour block
        // is visible behind the translucent loading overlay — cleaner look.
        placeholderLabel.isHidden = true
        loadingContainerView.isHidden = false
        loadingSpinner.startAnimating()
    }

    func hideLoadingIndicator() {
        // Restore the letter in case no cover was found (placeholder fallback).
        placeholderLabel.isHidden = false
        loadingContainerView.isHidden = true
        loadingSpinner.stopAnimating()
    }

    /// Call this once a cover image has been fetched successfully.
    /// Hides the loading indicator and fades out the colour backdrop — the
    /// cover itself provides the visual interest; the gradient is redundant.
    func setCoverImage(_ image: UIImage) {
        hideLoadingIndicator()

        coverImageView.image     = image
        coverImageView.isHidden  = false
        coverShadowView.isHidden = false   // shadow appears with the cover

        // Fade the gradient backdrop to transparent so the cover sits cleanly
        // against the plain system-grouped background.
        UIView.animate(withDuration: 0.35) {
            self.backdropView.alpha = 0
        }
    }
}
