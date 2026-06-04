//
//  RetroRomImportSheetViewController.swift
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
import ObjcHelper

/// Bottom-sheet chooser for the two ROM import modes (file / folder).
///
/// Replaces the PanModal-based `GameImportSelector` with a native
/// `UISheetPresentationController`. A single custom detent sizes the
/// sheet to exactly fit its two rows so it never occupies more screen
/// real estate than necessary.
final class RetroRomImportSheetViewController: UIViewController {

    // MARK: - Types

    enum FileType { case file, folder }

    // MARK: - Layout constants

    private enum Metrics {
        /// Height of the title header (including its bottom separator).
        static let headerHeight: CGFloat = 56
        /// Height of each import-option row.
        static let rowHeight:    CGFloat = 64
        /// Total sheet content height (header + 2 rows). Safe-area inset
        /// below is handled automatically by UISheetPresentationController.
        static let sheetHeight:  CGFloat = headerHeight + rowHeight * 2
    }

    // MARK: - Properties

    private let selectHandler: (FileType) -> Void

    private let titleLabel = UILabel()
    private let separator  = UIView()
    private let tableView  = UITableView(frame: .zero, style: .plain)

    // MARK: - Init

    init(selectHandler: @escaping (FileType) -> Void) {
        self.selectHandler = selectHandler
        super.init(nibName: nil, bundle: nil)
        configureSheet()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    /// Dismiss the sheet on any orientation change.
    ///
    /// `UISheetPresentationController` expands a custom detent to full-screen
    /// in landscape, which hides the grabber and leaves no way to close the
    /// sheet. Auto-dismissing on rotation avoids the stuck-full-screen state
    /// and the cell-highlight artifact that appears when rotating back.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        dismiss(animated: true)
    }
}

// MARK: - Sheet configuration

private extension RetroRomImportSheetViewController {

    func configureSheet() {
        modalPresentationStyle = .pageSheet
        guard let sheet = sheetPresentationController else { return }

        // Single fixed-height detent — the sheet cannot be dragged to expand.
        let detent = UISheetPresentationController.Detent.custom(
            identifier: .init("importSheet")
        ) { _ in
            Metrics.sheetHeight
        }

        sheet.detents                               = [detent]
        sheet.prefersGrabberVisible                 = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    }
}

// MARK: - UI construction

private extension RetroRomImportSheetViewController {

    func buildUI() {
        buildHeader()
        buildTableView()
    }

    func buildHeader() {
        titleLabel.text          = Bundle.localizedString(forKey: "homepage_import_game")
        titleLabel.font          = .boldSystemFont(ofSize: 16)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        separator.backgroundColor = UIColor.label.withAlphaComponent(0.15)
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            separator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    func buildTableView() {
        tableView.dataSource      = self
        tableView.delegate        = self
        tableView.rowHeight       = Metrics.rowHeight
        tableView.isScrollEnabled = false
        tableView.separatorColor  = UIColor.label.withAlphaComponent(0.15)
        tableView.separatorInset  = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0)
        // Hide the trailing separator that appears after the last cell.
        tableView.tableFooterView = UIView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension RetroRomImportSheetViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id   = "ImportCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) as? ImportCell
                   ?? ImportCell(reuseIdentifier: id)
        cell.configure(for: indexPath.row == 0 ? .file : .folder)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Vibration.selection.vibrate()
        let fileType: FileType = indexPath.row == 0 ? .file : .folder
        dismiss(animated: true) { [weak self] in
            self?.selectHandler(fileType)
        }
    }
}

// MARK: - ImportCell

/// Private table view cell for a single import option. Displays an SF Symbol
/// icon, a primary title, and a secondary description below it.
private final class ImportCell: UITableViewCell {

    private let iconView      = UIImageView()
    private let titleLabel    = UILabel()
    private let subtitleLabel = UILabel()

    init(reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(for type: RetroRomImportSheetViewController.FileType) {
        switch type {
        case .file:
            iconView.image     = UIImage(systemName: "doc.on.doc")
            titleLabel.text    = Bundle.localizedString(forKey: "homepage_import_rom_file")
            subtitleLabel.text = Bundle.localizedString(forKey: "homepage_import_rom_file_desc")
            accessibilityLabel = titleLabel.text
        case .folder:
            iconView.image     = UIImage(systemName: "folder.badge.plus")
            titleLabel.text    = Bundle.localizedString(forKey: "homepage_import_rom_folder")
            subtitleLabel.text = Bundle.localizedString(forKey: "homepage_import_rom_folder_desc")
            accessibilityLabel = titleLabel.text
        }
    }

    private func setup() {
        let selectedBg = UIView()
        selectedBg.backgroundColor = UIColor.label.withAlphaComponent(0.11)
        selectedBackgroundView = selectedBg

        iconView.tintColor   = .label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        subtitleLabel.font      = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -2),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 3),
        ])
    }
}
