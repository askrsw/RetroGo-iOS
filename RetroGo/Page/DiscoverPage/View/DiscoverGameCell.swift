//
//  DiscoverGameCell.swift
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

final class DiscoverGameCell: UITableViewCell {

    static let reuseID   = "DiscoverGameCell"
    static let rowHeight: CGFloat = 60

    // MARK: - Cover image view
    //
    // Overlays the placeholder view when a cached cover image is available.
    // The cell never fetches cover art from the network — it only reads from
    // Kingfisher's local cache (memory + disk).  Remote loading is handled
    // exclusively by DiscoverGameDetailViewController; once it succeeds, a
    // notification triggers an update in the visible cell (if any).

    private let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode        = .scaleAspectFill
        iv.clipsToBounds      = true
        iv.layer.cornerRadius = 6
        iv.isHidden           = true
        return iv
    }()

    /// Pending disk-cache lookup task.
    /// Cancelled when the cell is reused or reconfigured so a slow disk read
    /// never lands on the wrong row.
    private var localCacheTask: Task<Void, Never>?

    // MARK: - Placeholder palette
    // Colours are derived from the game name hash → same game always gets the same colour.
    // Canonical definition lives here; DiscoverGameHeaderView references it via
    // DiscoverGameCell.placeholderColor(for:) so the two surfaces always stay in sync.

    // Palette and color lookup — shared with DiscoverGameHeaderView.
    static let palette: [UIColor] = [
        UIColor(red: 0.90, green: 0.27, blue: 0.27, alpha: 1), // red
        UIColor(red: 0.20, green: 0.56, blue: 0.90, alpha: 1), // blue
        UIColor(red: 0.18, green: 0.72, blue: 0.54, alpha: 1), // teal
        UIColor(red: 0.61, green: 0.35, blue: 0.71, alpha: 1), // purple
        UIColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1), // amber
        UIColor(red: 0.20, green: 0.63, blue: 0.37, alpha: 1), // green
        UIColor(red: 0.94, green: 0.37, blue: 0.57, alpha: 1), // pink
        UIColor(red: 0.00, green: 0.59, blue: 0.65, alpha: 1), // cyan
    ]

    static func placeholderColor(for gameName: String) -> UIColor {
        palette[abs(gameName.hashValue) % palette.count]
    }

    // MARK: - Subviews

    private let placeholderView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 6
        v.clipsToBounds = true
        return v
    }()

    private let initialLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .label
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let detailLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        placeholderView.addSubview(initialLabel)
        initialLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let textStack = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        textStack.axis      = .vertical
        textStack.spacing   = 8
        textStack.alignment = .leading

        contentView.addSubview(placeholderView)
        // coverImageView sits on top of placeholderView and shares the same frame.
        contentView.addSubview(coverImageView)
        contentView.addSubview(textStack)

        placeholderView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(40)
        }

        coverImageView.snp.makeConstraints { make in
            make.edges.equalTo(placeholderView)
        }

        textStack.snp.makeConstraints { make in
            make.leading.equalTo(placeholderView.snp.trailing).offset(20)
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        localCacheTask?.cancel()
        localCacheTask    = nil
        coverImageView.image    = nil
        coverImageView.isHidden = true
    }

    // MARK: - Configure

    /// Configure the cell. `platform` is needed to look up the local cache key.
    func configure(with game: RAGameEntry, platform: RAPlatformItem) {
        // Cancel any pending disk lookup from a previous configuration.
        localCacheTask?.cancel()
        localCacheTask  = nil
        // Reset cover state — defensive guard against reconfigureItems / direct reuse.
        coverImageView.image    = nil
        coverImageView.isHidden = true

        nameLabel.text = game.name

        // Build detail line: "1996  ·  Nintendo" — skip zero/nil parts
        var parts: [String] = []
        if game.releaseYear > 0 { parts.append(String(game.releaseYear)) }
        if let dev = game.developer, !dev.isEmpty { parts.append(dev) }
        if parts.isEmpty, let region = game.region { parts.append(region) }
        detailLabel.text = parts.joined(separator: "  ·  ")
        detailLabel.isHidden = parts.isEmpty

        let initial = game.name.first.map { String($0).uppercased() } ?? "#"
        placeholderView.backgroundColor = Self.placeholderColor(for: game.name)
        initialLabel.text = initial

        // ── Fast path: memory cache (synchronous, zero latency) ──────────────
        if let cached = GameCoverService.shared.memoryCachedImage(for: game, platform: platform) {
            setCoverImage(cached)
            return
        }

        // ── Slow path: disk cache (async I/O, no network) ────────────────────
        // Disk reads are typically < 50 ms.  The task is cancelled in
        // prepareForReuse / at the top of the next configure call so a stale
        // result never lands on the wrong row.
        localCacheTask = Task { @MainActor [weak self] in
            let image = await GameCoverService.shared.localCachedImage(for: game, platform: platform)
            guard !Task.isCancelled, let self, let image else { return }
            self.setCoverImage(image)
        }
    }

    /// Show the cover image, hiding the placeholder behind it.
    func setCoverImage(_ image: UIImage) {
        coverImageView.image   = image
        coverImageView.isHidden = false
    }
}
