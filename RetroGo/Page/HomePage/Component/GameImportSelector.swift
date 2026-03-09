//
//  GameImportSelector.swift
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
import PanModal
import ObjcHelper

final class GameImportSelector: UIViewController {
    enum FileType {
        case file, folder
    }

    private let headerView = GameImportSelectorHeaderView(frame: .zero)
    private let tableView = UITableView(frame: .zero)

    private let selectHandler: (FileType) -> Void

    init(selectHandler: @escaping (FileType) -> Void) {
        self.selectHandler = selectHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: GameImportSelectorHeaderView.headerHeight),
        ])

        tableView.rowHeight  = GameImportSelectorTableViewCell.cellHeight
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.separatorColor = UIColor.label.withAlphaComponent(0.2)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}

extension GameImportSelector: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = { () -> GameImportSelectorTableViewCell in
            let cellId = "GameImportSelectorTableViewCell"
            if let cell = tableView.dequeueReusableCell(withIdentifier: cellId) as? GameImportSelectorTableViewCell {
                return cell
            } else {
                return GameImportSelectorTableViewCell(style: .default, reuseIdentifier: cellId)
            }
        }()

        switch indexPath.row {
            case 0:
                cell.fileType = .file
            case 1:
                cell.fileType = .folder
            default:
                break
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()

        let fileType: FileType = indexPath.row == 0 ? .file : .folder

        dismiss(animated: true) { [weak self] in
            self?.selectHandler(fileType )
        }
    }
}

extension GameImportSelector: PanModalPresentable {
    var panScrollable: UIScrollView? {
        nil
    }

    var longFormHeight: PanModalHeight {
        let screenheight = DeviceConfig.screenAbsoluteHeight
        let sheetHeight  = view.safeAreaInsets.bottom + GameImportSelectorTableViewCell.cellHeight * 2 + GameImportSelectorHeaderView.headerHeight
        return .maxHeightWithTopInset(screenheight - sheetHeight - 120)
    }

    var anchorModalToLongForm: Bool {
        true
    }

    var isHapticFeedbackEnabled: Bool {
        false
    }
}

final class GameImportSelectorHeaderView: UIView {
    static let headerHeight: CGFloat = 60

    let titleLabel    = UILabel(frame: .zero)
    let seperatorView = UIView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)

        seperatorView.backgroundColor = UIColor.label.withAlphaComponent(0.2)
        seperatorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(seperatorView)
        NSLayoutConstraint.activate([
            seperatorView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 20),
            seperatorView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            seperatorView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -20),
            seperatorView.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 16.0)
        titleLabel.text = Bundle.localizedString(forKey: "homepage_import_game")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class GameImportSelectorTableViewCell: UITableViewCell {
    static let cellHeight: CGFloat = 10 + 30 + 10

    let iconView      = UIImageView(frame: .zero)
    let titleLabel    = UILabel(frame: .zero)
    let subtitleLabel = UILabel(frame: .zero)

    var fileType: GameImportSelector.FileType? {
        didSet {
            guard let fileType = fileType else {
                return
            }

            switch fileType {
                case .file:
                    iconView.image = UIImage(systemName: "doc.on.doc")
                    titleLabel.text = Bundle.localizedString(forKey: "homepage_import_rom_file")
                    subtitleLabel.text = Bundle.localizedString(forKey: "homepage_import_rom_file_desc")
                case .folder:
                    iconView.image = UIImage(systemName: "folder.badge.plus")
                    titleLabel.text = Bundle.localizedString(forKey: "homepage_import_rom_folder")
                    subtitleLabel.text = Bundle.localizedString(forKey: "homepage_import_rom_folder_desc")
            }
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let selectedView             = UIView(frame: .zero)
        selectedView.backgroundColor = UIColor.label.withAlphaComponent(0.11)
        self.selectedBackgroundView  = selectedView

        self.isAccessibilityElement = true

        configUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configUI() {
        iconView.tintColor = .label
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        contentView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12.5),
            iconView.widthAnchor.constraint(equalToConstant: 25),
            iconView.heightAnchor.constraint(equalToConstant: 25),
        ])

        titleLabel.font = UIFont.systemFont(ofSize: 16.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            titleLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -20 - 25 - 10 - 20),
            titleLabel.heightAnchor.constraint(equalToConstant: 20),
        ])

        subtitleLabel.font = UIFont.systemFont(ofSize: 12.0)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            subtitleLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -20 - 25 - 10 - 20),
            subtitleLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
}
