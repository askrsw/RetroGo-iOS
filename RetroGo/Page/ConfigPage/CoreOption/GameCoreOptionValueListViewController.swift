//
//  GameCoreOptionValueListViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/20.
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
import RACoordinator
import UniformTypeIdentifiers

/// Scrollable picker listing every value of one option.
final class GameCoreOptionValueListViewController: UITableViewController {
    private let option: GameCoreOptionCatalog.Option
    private let session: GameCoreOptionSession
    private let core: EmuCoreInfoItem?
    private let resetTitle: String
    private let onChange: () -> Void
    /// Value waiting for the file the user is picking; cleared when they cancel.
    private var pendingFileValue: String?

    init(option: GameCoreOptionCatalog.Option, session: GameCoreOptionSession, core: EmuCoreInfoItem?, resetTitle: String, onChange: @escaping () -> Void) {
        self.option = option
        self.session = session
        self.core = core
        self.resetTitle = resetTitle
        self.onChange = onChange
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        navigationItem.title = GameCoreOptionCatalog.text(option.title, fallback: option.key)
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: resetTitle, style: .plain, target: self, action: #selector(resetValue))

        tableView.tintColor = .mainColor
        tableView.register(GameCoreOptionValueRowCell.self, forCellReuseIdentifier: "value")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let row = option.values.firstIndex(of: session.value(for: option)) {
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        option.values.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "value", for: indexPath) as! GameCoreOptionValueRowCell
        let value = option.values[indexPath.row]
        cell.configure(title: option.label(for: value), explanation: fileHint(for: value), selected: value == session.value(for: option))
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        Vibration.selection.vibrate()
        let value = option.values[indexPath.row]

        // Values such as a custom palette need a file in the core's BIOS folder first;
        // the value is only stored once the file has been imported.
        if let requirement = option.valueFiles[value] {
            presentFilePicker(for: value, requirement: requirement)
            return
        }

        apply(value)
    }
}

extension GameCoreOptionValueListViewController {
    /// Explains that this value imports a file, and when that file takes effect.
    private func fileHint(for value: String) -> String {
        guard let requirement = option.valueFiles[value] else { return "" }
        let extensions = requirement.extensions.map { "." + $0 }.joined(separator: " / ")
        var text = String(format: Bundle.localizedString(forKey: "coreoption_file_hint"), extensions, requirement.fileName)
        if requirement.restartRequired {
            text += "\n\n" + Bundle.localizedString(forKey: "coreoption_file_restart_hint")
        }
        return text
    }

    private func apply(_ value: String) {
        guard session.select(value, for: option) else { return }
        onChange()
        navigationController?.popViewController(animated: true)
    }

    private func presentFilePicker(for value: String, requirement: GameCoreOptionCatalog.Option.ValueFile) {
        guard core != nil else { return }

        let types = requirement.extensions.compactMap {
            UTType(filenameExtension: $0)
        }

        pendingFileValue = value

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types.isEmpty ? [.data] : types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func presentMessage(_ message: String, completion: (() -> Void)? = nil) {
        let title = GameCoreOptionCatalog.text(option.title, fallback: option.key)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "coreoption_ok"), style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }

    @objc
    private func resetValue() {
        session.reset([option])
        onChange()
        tableView.reloadData()
    }
}

extension GameCoreOptionValueListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {

        guard let value = pendingFileValue, let requirement = option.valueFiles[value], let url = urls.first, let core else {
            return
        }

        pendingFileValue = nil

        guard core.importSystemFile(at: url, fileName: requirement.fileName) else {
            presentMessage(Bundle.localizedString(forKey: "coreoption_file_import_error"))
            return
        }

        var message = String(format: Bundle.localizedString(forKey: "coreoption_file_import_success"), requirement.fileName)
        if requirement.restartRequired {
            message += "\n\n" + Bundle.localizedString(forKey: "coreoption_file_restart_hint")
        }
        presentMessage(message) { [weak self] in self?.apply(value) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Keep the previous selection when no file was chosen.
        pendingFileValue = nil
    }
}

/// Value row that can carry a help button, used by values that need a file import.
private final class GameCoreOptionValueRowCell: UITableViewCell {
    private let nameLabel = UILabel(frame: .zero)
    private let helpButton = UIButton(type: .system)
    private var explanation = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, explanation: String, selected: Bool) {
        nameLabel.text = title
        self.explanation = explanation
        helpButton.isHidden = explanation.isEmpty
        helpButton.accessibilityLabel = title
        accessoryType = selected ? .checkmark : .none
    }

    private func configUI() {
        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.numberOfLines = 0
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        helpButton.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
        helpButton.tintColor = .label
        helpButton.addTarget(self, action: #selector(showHelp), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [nameLabel, helpButton, UIView(frame: .zero)])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        let bottom = stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        bottom.priority = UILayoutPriority(999)

        // UIStackView imposes zero width when an arranged button is hidden.
        let helpWidth = helpButton.widthAnchor.constraint(equalToConstant: 32)
        helpWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            helpWidth,
            helpButton.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            bottom
        ])
    }

    @objc private func showHelp() {
        Vibration.selection.vibrate()
        GameConfigDescView(desc: explanation).install(source: helpButton)
    }
}
