//
//  ODRResourceViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/10.
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

private enum ODRAccessoryKind {
    case none
    case ready
    case download
    case delete
    case loading
}

/// Lists the app's On-Demand Resources in three groups: the English base
/// databases (game database, optional cheat library), the language packs
/// (translations for one App language each; the one of the current App
/// language is marked recommended), and the cover cache. Each row shows size
/// and state with a download / update / delete action.
final class ODRResourceViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case base
        case languagePacks
        case cache
    }

    private let loader = OnDemandResourceLoader.shared
    private let baseResources = OnDemandResourceLoader.baseResources
    private let languagePacks = OnDemandResourceLoader.languagePacks
    private lazy var tableView = configUI()
    private var coverCacheSize: Int64?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "odr_page_title")
        navigationItem.titleView = makeTitleView()
        navigationItem.largeTitleDisplayMode = .never

        _ = tableView
        reloadCoverCacheSize()
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged(_:)),
            name: .odrResourceStateDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged(_:)),
            name: .activeLanguagePackDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func makeTitleView() -> UIView? {
        let title = Bundle.localizedString(forKey: "odr_page_title")
        let icon  = IconRender.shared.settingsIcon(
            symbol: "externaldrive.fill",
            background: .systemTeal,
            size: CGSize(width: 28, height: 28)
        )
        return Self.makeIconTitleView(title, icon: icon)
    }

    private func configUI() -> UITableView {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.tintColor = .mainColor
        table.estimatedRowHeight = 64
        table.rowHeight = UITableView.automaticDimension
        table.estimatedSectionHeaderHeight = 0
        table.register(ODRResourceCell.self, forCellReuseIdentifier: ODRResourceCell.reuseID)
        view.addSubview(table)
        table.snp.makeConstraints { $0.edges.equalToSuperview() }
        return table
    }

    @objc private func stateChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.tableView.reloadData() }
    }

    private func resource(at indexPath: IndexPath) -> ODRResource? {
        switch Section(rawValue: indexPath.section) {
        case .base:          return baseResources[indexPath.row]
        case .languagePacks: return languagePacks[indexPath.row]
        default:             return nil
        }
    }

    // MARK: - Cell content

    private func title(for r: ODRResource) -> String {
        r.nativeName ?? Bundle.localizedString(forKey: r.titleKey)
    }

    private func iconSymbol(for r: ODRResource) -> String {
        switch r.id {
        case "gamerdb": return "gamecontroller.fill"
        case "cheat":   return "star.circle.fill"
        default:        return r.kind == .languagePack ? "character.book.closed.fill" : "externaldrive.fill"
        }
    }

    private func iconColor(for r: ODRResource) -> UIColor {
        switch r.id {
        case "gamerdb": return .systemBlue
        case "cheat":   return UIColor(red: 0.78, green: 0.56, blue: 0.06, alpha: 1.0)
        default:        return r.kind == .languagePack ? .systemIndigo : .systemGray
        }
    }

    private func sizeString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func coverCacheStatusString() -> String {
        guard let coverCacheSize else {
            return Bundle.localizedString(forKey: "odr_cache_calculating")
        }
        return sizeString(coverCacheSize)
    }

    private func statusString(for r: ODRResource) -> String {
        var parts = [sizeString(r.approxByteSize)]
        switch loader.state(for: r) {
        case .ready:         parts.append(Bundle.localizedString(forKey: "odr_status_ready"))
        case .outdated:      parts.append(Bundle.localizedString(forKey: "odr_status_outdated"))
        case .notDownloaded: parts.append(Bundle.localizedString(forKey: "odr_status_not_downloaded"))
        case .downloading:   parts.append(Bundle.localizedString(forKey: "odr_status_downloading"))
        }
        if r.kind == .languagePack, r == loader.currentLanguagePack {
            parts.append(Bundle.localizedString(forKey: "odr_langpack_recommended"))
        }
        return parts.joined(separator: " · ")
    }

    private func accessoryKind(for r: ODRResource) -> ODRAccessoryKind {
        switch loader.state(for: r) {
        case .ready:         return .ready
        case .downloading:   return .loading
        case .outdated,
             .notDownloaded: return .download
        }
    }

    private func isDeletable(_ r: ODRResource) -> Bool {
        guard !r.isRequired else { return false }
        switch loader.state(for: r) {
        case .ready, .outdated: return true
        case .notDownloaded, .downloading: return false
        }
    }

    // MARK: - Actions

    private func download(_ r: ODRResource) {
        if case .downloading = loader.state(for: r) { return }
        let title = title(for: r)
        let activity = RetroRomActivityView(mainTitle: title)
        activity.install()
        activity.activeMessage(downloadingText(0), title: title)

        loader.startDownload(r, progress: { [weak activity, weak self] p in
            guard let self else { return }
            activity?.activeMessage(self.downloadingText(p), title: title)
        }, completion: { [weak self, weak activity] ok, error in
            if ok {
                activity?.successMessage(
                    Bundle.localizedString(forKey: "odr_download_done"),
                    title: title, canDismiss: true)
            } else {
                let msg = Bundle.localizedString(forKey: "odr_download_failed")
                    + (error.map { "\n\($0.localizedDescription)" } ?? "")
                activity?.errorMessage(msg, title: title, canDismiss: true)
            }
            self?.tableView.reloadData()
        })
        tableView.reloadData()
    }

    private func downloadingText(_ fraction: Double) -> String {
        let pct = Int((fraction * 100).rounded())
        let fmt = Bundle.localizedString(forKey: "odr_downloading_fmt") // "Downloading %d%%"
        return String(format: fmt, pct)
    }

    private func confirmDelete(_ r: ODRResource) {
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "odr_delete_confirm_title"),
            message: String(format: Bundle.localizedString(forKey: "odr_delete_confirm_msg_fmt"), title(for: r)),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: Bundle.localizedString(forKey: "odr_action_delete"),
            style: .destructive) { [weak self] _ in
                self?.loader.delete(r)
                self?.tableView.reloadData()
            })
        present(alert, animated: true)
    }

    private func reloadCoverCacheSize() {
        GameCoverService.shared.diskCacheSize { [weak self] bytes in
            guard let self else { return }
            self.coverCacheSize = bytes
            self.tableView.reloadSections(IndexSet(integer: Section.cache.rawValue), with: .automatic)
        }
    }

    private func confirmClearCoverCache() {
        let alert = UIAlertController(
            title: Bundle.localizedString(forKey: "odr_cache_delete_confirm_title"),
            message: Bundle.localizedString(forKey: "odr_cache_delete_confirm_msg"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: Bundle.localizedString(forKey: "odr_action_delete"),
            style: .destructive) { [weak self] _ in
                GameCoverService.shared.clearCache { [weak self] in
                    self?.coverCacheSize = 0
                    self?.tableView.reloadSections(IndexSet(integer: Section.cache.rawValue), with: .automatic)
                }
            })
        present(alert, animated: true)
    }
}

extension ODRResourceViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .base:          return baseResources.count
        case .languagePacks: return languagePacks.count
        case .cache:         return 1
        case nil:            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let r = resource(at: indexPath) else {
            return cacheCell(tableView, indexPath: indexPath)
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ODRResourceCell.reuseID,
            for: indexPath) as! ODRResourceCell
        cell.configure(
            icon: IconRender.shared.settingsIcon(
                symbol: iconSymbol(for: r),
                background: iconColor(for: r),
                size: CGSize(width: 28, height: 28)),
            title: title(for: r),
            desc: Bundle.localizedString(forKey: r.descKey),
            status: statusString(for: r),
            accessory: accessoryKind(for: r))
        return cell
    }

    private func cacheCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let hasCache = (coverCacheSize ?? 0) > 0
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ODRResourceCell.reuseID,
            for: indexPath) as! ODRResourceCell
        cell.configure(
            icon: IconRender.shared.settingsIcon(
                symbol: "photo.fill",
                background: .systemPurple,
                size: CGSize(width: 28, height: 28)),
            title: Bundle.localizedString(forKey: "odr_cache_cover_title"),
            desc: Bundle.localizedString(forKey: "odr_cache_cover_desc"),
            status: coverCacheStatusString(),
            accessory: hasCache ? .delete : .none)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let r = resource(at: indexPath) else {
            guard (coverCacheSize ?? 0) > 0 else { return }
            Vibration.selection.vibrate()
            confirmClearCoverCache()
            return
        }
        switch loader.state(for: r) {
        case .notDownloaded, .outdated:
            Vibration.selection.vibrate()
            download(r)
        default:
            break
        }
    }

    /// Swipe-to-delete for installed optional resources and the cover cache.
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard let r = resource(at: indexPath) else {
            guard (coverCacheSize ?? 0) > 0 else { return nil }
            let action = UIContextualAction(
                style: .destructive,
                title: Bundle.localizedString(forKey: "odr_action_delete")) { [weak self] _, _, done in
                    self?.confirmClearCoverCache()
                    done(true)
                }
            return UISwipeActionsConfiguration(actions: [action])
        }
        guard isDeletable(r) else { return nil }
        let action = UIContextualAction(
            style: .destructive,
            title: Bundle.localizedString(forKey: "odr_action_delete")) { [weak self] _, _, done in
                self?.confirmDelete(r)
                done(true)
            }
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let key: String
        switch Section(rawValue: section) {
        case .base:          key = "odr_section_base"
        case .languagePacks: key = "odr_section_langpack"
        case .cache:         key = "odr_section_cache"
        case nil:            return nil
        }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as? RGSectionHeaderView
            ?? RGSectionHeaderView(reuseIdentifier: RGSectionHeaderView.className)
        view.text = Bundle.localizedString(forKey: key)
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let key: String
        switch Section(rawValue: section) {
        case .base:          key = "odr_page_footer"
        case .languagePacks: key = "odr_langpack_footer"
        case .cache:         key = "odr_cache_footer"
        case nil:            return nil
        }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as? RGSectionFooterView
            ?? RGSectionFooterView(reuseIdentifier: RGSectionFooterView.className)
        view.text = Bundle.localizedString(forKey: key)
        return view
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }
}

private final class ODRResourceCell: UITableViewCell {

    static let reuseID = "ODRResourceCell"

    private let resourceIconView = UIImageView()
    private let titleLabel = UILabel()
    private let descLabel = UILabel()
    private let statusLabel = UILabel()
    private let actionContainer = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        actionContainer.subviews.forEach { $0.removeFromSuperview() }
        selectionStyle = .default
    }

    private func setup() {
        resourceIconView.contentMode = .center

        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, descLabel, statusLabel])
        textStack.axis = .vertical
        textStack.spacing = 7
        textStack.alignment = .fill

        contentView.addSubview(resourceIconView)
        contentView.addSubview(textStack)
        contentView.addSubview(actionContainer)

        resourceIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }

        actionContainer.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(28)
        }

        textStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
            make.leading.equalTo(resourceIconView.snp.trailing).offset(20)
            make.trailing.equalTo(actionContainer.snp.leading).offset(-18)
        }
    }

    func configure(icon: UIImage?,
                   title: String,
                   desc: String,
                   status: String,
                   accessory: ODRAccessoryKind) {
        resourceIconView.image = icon
        titleLabel.text = title
        descLabel.text = desc
        statusLabel.text = status
        configureAccessory(accessory)
    }

    private func configureAccessory(_ accessory: ODRAccessoryKind) {
        actionContainer.subviews.forEach { $0.removeFromSuperview() }

        let view: UIView?
        switch accessory {
        case .none:
            view = nil
            selectionStyle = .none
        case .ready:
            let imageView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            imageView.tintColor = .systemGreen
            view = imageView
            selectionStyle = .none
        case .download:
            let imageView = UIImageView(image: UIImage(systemName: "arrow.down.circle"))
            imageView.tintColor = .mainColor
            view = imageView
            selectionStyle = .default
        case .delete:
            let imageView = UIImageView(image: UIImage(systemName: "trash.circle"))
            imageView.tintColor = .systemRed
            view = imageView
            selectionStyle = .default
        case .loading:
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            view = spinner
            selectionStyle = .none
        }

        guard let view else { return }
        actionContainer.addSubview(view)
        view.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
