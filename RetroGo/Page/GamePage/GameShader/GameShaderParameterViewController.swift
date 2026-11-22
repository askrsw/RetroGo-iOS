//
//  GameShaderParameterViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/19.
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

final class GameShaderParameterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let session: GameShaderSession
    private var tableView: UITableView!
    private weak var hiddenOverlay: UIView?
    private var overlayAlpha: CGFloat = 1

    init(session: GameShaderSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = session.title
        view.backgroundColor = GameShaderAppearance.background
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = GameShaderAppearance.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor), tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: shaderText("done"), style: .plain, target: self, action: #selector(doneTapped))
        GameShaderAppearance.registerSections(in: tableView)
        tableView.register(GameShaderParameterCell.self, forCellReuseIdentifier: "parameter")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
        tableView.tintColor = .mainColor
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard session.isLive, hiddenOverlay == nil,
              let overlay = GamePageViewController.instance?.myOverlayView else { return }
        hiddenOverlay = overlay
        overlayAlpha = overlay.alpha
        UIView.animate(withDuration: 0.15) { overlay.alpha = 0 }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Restore the exact view and opacity, never the overlay of a subsequently opened game.
        guard let overlay = hiddenOverlay else { return }
        let alpha = overlayAlpha
        hiddenOverlay = nil
        UIView.animate(withDuration: 0.15) { overlay.alpha = alpha }
    }

    override func viewWillDisappear(_ animated: Bool) {
        flushSliderEdits()
        super.viewWillDisappear(animated)
    }

    private func flushSliderEdits() {
        tableView.visibleCells.compactMap { $0 as? GameShaderParameterCell }.forEach { $0.finishEditing() }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? GameShaderParameterCell)?.finishEditing()
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? .leastNormalMagnitude : 12
    }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { 28 }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { nil }
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { nil }

    func numberOfSections(in tableView: UITableView) -> Int { session.definitions.isEmpty ? 1 : 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? max(1, session.definitions.count) : 1
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0, !session.definitions.isEmpty {
            let parameter = session.definitions[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "parameter", for: indexPath) as! GameShaderParameterCell
            cell.backgroundColor = GameShaderAppearance.card
            cell.configure(parameter, value: session.value(for: parameter),
                           displayTitle: parameter.displayTitle(for: try? session.selected.preset))
            cell.onChange = { [weak self, weak cell] value in
                guard let self else { return }
                do { try session.setValue(value, parameter: parameter) }
                catch { cell?.setValue(session.value(for: parameter)); showError(error) }
            }
            return cell
        }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = GameShaderAppearance.card
        cell.textLabel?.numberOfLines = 0
        switch indexPath.section {
        case 0:
            cell.textLabel?.text = shaderText("no_parameters")
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
        default:
            cell.textLabel?.text = shaderText("reset_parameters")
            cell.textLabel?.textColor = .systemRed
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section != 0 else { return }
        Vibration.selection.vibrate()
        flushSliderEdits()
        do { try session.resetParameters(); tableView.reloadData() }
        catch { showError(error) }
    }

    @objc private func doneTapped() { Vibration.selection.vibrate(); done() }
    private func done() {
        flushSliderEdits()
        navigationController?.popViewController(animated: true)
    }
    private func showError(_ error: Error) { showMessage(error.localizedDescription) }
    private func showMessage(_ message: String) {
        if let presented = presentedViewController {
            presented.dismiss(animated: true) { [weak self] in self?.showMessage(message) }
            return
        }
        let alert = UIAlertController(title: shaderText("title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: shaderText("ok"), style: .default) { _ in Vibration.selection.vibrate() })
        present(alert, animated: true)
    }
}
