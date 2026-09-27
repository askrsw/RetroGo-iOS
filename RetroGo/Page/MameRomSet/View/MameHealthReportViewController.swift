//
//  MameHealthReportViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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
import RACoordinator

/// Overview of the arcade library: games that a repair can complete (with "Repair
/// All"), games grouped by what keeps them from running (problems first), the
/// BIOS/device files in the MAME BIOS folder, and the backups earlier repairs kept.
final class MameHealthReportViewController: UIViewController {
    private enum Section {
        case repairable
        case games(MameHealthReport.Status)
        case bios
        case backups
    }

    private let core: EmuCoreInfoItem
    private var report: MameHealthReport?
    private var sections: [Section] = []
    /// Complete games are the least interesting; they start collapsed.
    private var showsCompleteGames = false

    private lazy var tableView = configUI()
    private let loadingView = UIActivityIndicatorView(style: .medium)

    /// Pushes the report, or presents it in its own navigation controller when the
    /// caller is not in one.
    static func show(from viewController: UIViewController) {
        guard let core = RetroArchX.shared().allCores.first(where: { $0.coreId == MameImportScreener.mameCoreId }) else { return }
        let report = MameHealthReportViewController(core: core)
        if let navigationController = viewController.navigationController {
            navigationController.pushViewController(report, animated: true)
        } else {
            let navigation = UINavigationController(rootViewController: report)
            report.navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "xmark"), style: .plain, target: report, action: #selector(closeAction))
            viewController.present(navigation, animated: true)
        }
    }

    init(core: EmuCoreInfoItem) {
        self.core = core
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = Bundle.localizedString(forKey: "mame_health_title")
        navigationItem.title = title
        navigationItem.titleView = Self.makeIconTitleView(title, icon: IconRender.shared.settingsIcon(
            symbol: "stethoscope", background: .systemGreen, size: CGSize(width: 28, height: 28)))
        navigationItem.largeTitleDisplayMode = .never

        _ = tableView
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh

        loadingView.startAnimating()
        tableView.backgroundView = loadingView
        reload()
    }

    private func configUI() -> UITableView {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.tintColor = .mainColor
        table.estimatedRowHeight = 56
        table.rowHeight = UITableView.automaticDimension
        table.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        table.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        view.addSubview(table)
        table.snp.makeConstraints { $0.edges.equalToSuperview() }
        return table
    }

    @objc private func reload() {
        MameHealthReport.build(core: core) { [weak self] report in
            guard let self else { return }
            self.report = report
            self.sections = (report.repairable.isEmpty ? [] : [.repairable])
                + MameHealthReport.Status.allCases.compactMap { status in
                    (report.games[status]?.isEmpty ?? true) ? nil : .games(status)
                }
                + (report.bios.isEmpty ? [] : [.bios])
                + (report.backupFileCount == 0 ? [] : [.backups])
            self.tableView.refreshControl?.endRefreshing()
            self.tableView.backgroundView = self.sections.isEmpty ? self.makeEmptyView() : nil
            self.tableView.reloadData()
        }
    }

    // MARK: - Actions

    private func showDetail(_ game: MameHealthReport.Game) {
        let detail = MameHealthDetailViewController(game: game)
        detail.onRepaired = { [weak self] in
            self?.reload()
        }
        navigationController?.pushViewController(detail, animated: true)
    }

    private func confirmRepairAll(_ items: [MameHealthReport.Repairable]) {
        let message = String(format: Bundle.localizedString(forKey: "mame_repair_all_confirm"), items.count)
            + "\n\n" + Bundle.localizedString(forKey: "mame_repair_confirm_backup")
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "mame_repair_all"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "mame_repair_confirm_button"), style: .default) { [weak self] _ in
            self?.repairAll(items)
        })
        present(alert, animated: true)
    }

    /// Repairs one game after the other; a failure is reported and the rest continue.
    private func repairAll(_ items: [MameHealthReport.Repairable]) {
        let title = Bundle.localizedString(forKey: "mame_repair_all")
        let activity = RetroRomActivityView(mainTitle: title)
        activity.install()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failures: [String] = []
            for (index, item) in items.enumerated() {
                activity.activeMessage("\(index + 1)/\(items.count) \(item.game.name)", title: title)
                do {
                    // Re-plan: an earlier repair in this batch may have renamed a source archive.
                    if let plan = try MameSetRepairer.makePlan(romgameKey: item.game.key) {
                        try MameSetRepairer.repair(plan)
                    }
                } catch {
                    NSLog("[MameRepair] %@ failed: %@", item.game.name, error.localizedDescription)
                    failures.append("\(item.game.name): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                let done = items.count - failures.count
                if failures.isEmpty {
                    activity.successMessage(String(format: Bundle.localizedString(forKey: "mame_repair_all_done"), done),
                                            title: title, canDismiss: true)
                } else {
                    let message = String(format: Bundle.localizedString(forKey: "mame_repair_all_partial"), done, failures.count)
                        + "\n" + failures.joined(separator: "\n")
                    activity.errorMessage(message, title: title, canDismiss: true)
                }
                self?.reload()
            }
        }
    }

    private func confirmClearBackups() {
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "mame_backup_clear"),
                                      message: Bundle.localizedString(forKey: "mame_backup_clear_confirm"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "mame_backup_clear"), style: .destructive) { [weak self] _ in
            DispatchQueue.global(qos: .userInitiated).async {
                MameHealthReport.clearBackups()
                DispatchQueue.main.async { self?.reload() }
            }
        })
        present(alert, animated: true)
    }

    @objc private func closeAction() {
        dismiss(animated: true)
    }

    private func makeEmptyView() -> UIView {
        let label = UILabel()
        label.text = Bundle.localizedString(forKey: "mame_health_empty")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        return label
    }

    // MARK: - Content

    private func games(in status: MameHealthReport.Status) -> [MameHealthReport.Game] {
        report?.games[status] ?? []
    }

    private static func title(for status: MameHealthReport.Status) -> String {
        switch status {
            case .missingFiles: return Bundle.localizedString(forKey: "mame_health_section_missing")
            case .needsCHD: return Bundle.localizedString(forKey: "mame_health_section_chd")
            case .mayNotRun: return Bundle.localizedString(forKey: "mame_health_section_not_working")
            case .complete: return Bundle.localizedString(forKey: "mame_health_section_complete")
        }
    }

    private static func summary(for game: MameHealthReport.Game) -> String {
        let audit = game.audit
        var parts = [audit.machine.name]
        switch game.status {
            case .missingFiles:
                parts.append(String(format: Bundle.localizedString(forKey: "mame_health_missing_count"), audit.problems.count))
            case .needsCHD:
                parts.append(String(format: Bundle.localizedString(forKey: "mame_health_chd_list"),
                                    audit.requiredDisks.joined(separator: ", ")))
            case .mayNotRun:
                parts.append(Bundle.localizedString(forKey: "mame_health_not_working"))
            case .complete:
                break
        }
        if !audit.links.isEmpty || !audit.extractions.isEmpty || audit.gameStagedName != nil {
            parts.append(Bundle.localizedString(forKey: "mame_health_assembled"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - UITableView

extension MameHealthReportViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
            case .repairable:
                return 1 + (report?.repairable.count ?? 0)
            case .backups:
                return 1
            case .games(.complete):
                return showsCompleteGames ? games(in: .complete).count : 1
            case .games(let status):
                return games(in: status).count
            case .bios:
                return report?.bios.count ?? 0
        }
    }

    // Section titles use the app's header/footer views, aligned with the cells' leading edge.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let text = headerText(section) else { return nil }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as? RGSectionHeaderView
            ?? RGSectionHeaderView(reuseIdentifier: RGSectionHeaderView.className)
        view.text = text
        return view
    }

    /// Sections without a footer get a fixed gap so groups do not sit too close together.
    private static let sectionGap: CGFloat = 20

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        footerText(section) == nil ? Self.sectionGap : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let text = footerText(section) else {
            let spacer = UIView()
            spacer.backgroundColor = .clear
            return spacer
        }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as? RGSectionFooterView
            ?? RGSectionFooterView(reuseIdentifier: RGSectionFooterView.className)
        view.text = text
        return view
    }

    private func headerText(_ section: Int) -> String? {
        switch sections[section] {
            case .repairable:
                return "\(Bundle.localizedString(forKey: "mame_health_section_repairable")) (\(report?.repairable.count ?? 0))"
            case .backups:
                return Bundle.localizedString(forKey: "mame_health_section_backups")
            case .games(let status):
                return "\(Self.title(for: status)) (\(games(in: status).count))"
            case .bios:
                return Bundle.localizedString(forKey: "mame_health_section_bios")
        }
    }

    private func footerText(_ section: Int) -> String? {
        switch sections[section] {
            case .repairable: return Bundle.localizedString(forKey: "mame_health_repairable_footer")
            case .bios: return Bundle.localizedString(forKey: "mame_health_bios_footer")
            case .backups: return Bundle.localizedString(forKey: "mame_health_backups_footer")
            case .games: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2

        switch sections[indexPath.section] {
            case .repairable where indexPath.row == 0:
                cell.textLabel?.text = Bundle.localizedString(forKey: "mame_repair_all")
                cell.textLabel?.textColor = .mainColor
                cell.imageView?.image = UIImage(systemName: "wrench.and.screwdriver")
                cell.imageView?.tintColor = .mainColor
            case .repairable:
                guard let item = report?.repairable[indexPath.row - 1] else { break }
                cell.textLabel?.text = item.game.name
                cell.detailTextLabel?.text = item.game.audit.machine.name + " · "
                    + String(format: Bundle.localizedString(forKey: "mame_health_repair_adds"), item.plan.additions.count)
                cell.accessoryType = .disclosureIndicator
            case .backups:
                guard let report else { break }
                cell.textLabel?.text = Bundle.localizedString(forKey: "mame_backup_clear")
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = String(format: Bundle.localizedString(forKey: "mame_backup_usage"), report.backupFileCount,
                                                    ByteCountFormatter.string(fromByteCount: report.backupBytes, countStyle: .file))
            case .games(.complete) where !showsCompleteGames:
                cell.textLabel?.text = String(format: Bundle.localizedString(forKey: "mame_health_show_complete"),
                                              games(in: .complete).count)
                cell.textLabel?.textColor = .mainColor
            case .games(let status):
                let game = games(in: status)[indexPath.row]
                cell.textLabel?.text = game.name
                cell.detailTextLabel?.text = Self.summary(for: game)
                cell.accessoryType = .disclosureIndicator
            case .bios:
                guard let bios = report?.bios[indexPath.row] else { break }
                cell.textLabel?.text = bios.fileName
                let coverage = String(format: Bundle.localizedString(forKey: "mame_health_bios_coverage"),
                                      bios.covered, bios.required)
                cell.detailTextLabel?.text = [bios.description, coverage].compactMap { $0 }.joined(separator: " · ")
                cell.selectionStyle = .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
            case .repairable where indexPath.row == 0:
                if let items = report?.repairable {
                    confirmRepairAll(items)
                }
            case .repairable:
                if let item = report?.repairable[indexPath.row - 1] {
                    showDetail(item.game)
                }
            case .backups:
                confirmClearBackups()
            case .games(.complete) where !showsCompleteGames:
                showsCompleteGames = true
                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            case .games(let status):
                showDetail(games(in: status)[indexPath.row])
            case .bios:
                break
        }
    }
}

// MARK: - Detail

/// What one game needs and how its session will be assembled, with a repair action
/// when the archive can be rebuilt as a complete `<set>.zip`.
final class MameHealthDetailViewController: UITableViewController {
    private let game: MameHealthReport.Game
    private var sections: [(title: String, rows: [(String, String?)])] = []
    /// Non-nil once computed and the archive would change; adds the repair row.
    private var repairPlan: MameSetRepairer.Plan?

    var onRepaired: (() -> Void)?

    init(game: MameHealthReport.Game) {
        self.game = game
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = game.name
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(RGSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: RGSectionHeaderView.className)
        tableView.register(RGSectionFooterView.self, forHeaderFooterViewReuseIdentifier: RGSectionFooterView.className)
        sections = makeSections()

        let key = game.key
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let plan: MameSetRepairer.Plan?
            do {
                plan = try MameSetRepairer.makePlan(romgameKey: key)
            } catch {
                NSLog("[MameRepair] %@ cannot be repaired: %@", key, error.localizedDescription)
                plan = nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, let plan else { return }
                self.repairPlan = plan
                self.tableView.reloadData()
            }
        }
    }

    private var repairSection: Int? {
        repairPlan == nil ? nil : sections.count
    }

    private func confirmRepair(_ plan: MameSetRepairer.Plan) {
        var message = String(format: Bundle.localizedString(forKey: "mame_repair_confirm_target"), plan.targetFileName)
        if !plan.additions.isEmpty {
            message += "\n" + String(format: Bundle.localizedString(forKey: "mame_repair_confirm_added"), plan.additions.count,
                                     plan.additions.prefix(3).map(\.name).joined(separator: ", ") + (plan.additions.count > 3 ? ", …" : ""))
        }
        message += "\n\n" + Bundle.localizedString(forKey: "mame_repair_confirm_backup")

        let alert = UIAlertController(title: Bundle.localizedString(forKey: "mame_repair_action"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "mame_repair_confirm_button"), style: .default) { [weak self] _ in
            self?.runRepair(plan)
        })
        present(alert, animated: true)
    }

    private func runRepair(_ plan: MameSetRepairer.Plan) {
        let title = Bundle.localizedString(forKey: "mame_repair_action")
        let activity = RetroRomActivityView(mainTitle: title)
        activity.install()
        activity.activeMessage(plan.targetFileName, title: title)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try MameSetRepairer.repair(plan) }
            DispatchQueue.main.async { [weak self] in
                switch result {
                    case .success:
                        activity.successMessage(String(format: Bundle.localizedString(forKey: "mame_repair_done"), plan.targetFileName),
                                                title: title, canDismiss: true)
                        self?.onRepaired?()
                        self?.navigationController?.popViewController(animated: true)
                    case .failure(let error):
                        activity.errorMessage(error.localizedDescription, title: title, canDismiss: true)
                }
            }
        }
    }

    private func makeSections() -> [(title: String, rows: [(String, String?)])] {
        let audit = game.audit
        var result: [(title: String, rows: [(String, String?)])] = []

        result.append((Bundle.localizedString(forKey: "mame_health_detail_info"), [
            (Bundle.localizedString(forKey: "mame_health_detail_set"), audit.machine.name),
            (Bundle.localizedString(forKey: "mame_health_detail_file"), game.archiveFileName),
            (Bundle.localizedString(forKey: "mame_health_detail_driver"), audit.machine.driverStatus ?? "-"),
        ]))

        // Missing files, one section per part of the set, in report order.
        var order: [MameSetAudit.Source] = []
        var files: [MameSetAudit.Source: [String]] = [:]
        for problem in audit.problems {
            if files[problem.source] == nil {
                order.append(problem.source)
            }
            files[problem.source, default: []].append(problem.fileName)
        }
        for source in order {
            let title: String
            switch source {
                case .game: title = Bundle.localizedString(forKey: "mame_health_detail_missing_game")
                case .parent(let set): title = String(format: Bundle.localizedString(forKey: "mame_health_detail_missing_parent"), set)
                case .bios(let set): title = String(format: Bundle.localizedString(forKey: "mame_health_detail_missing_bios"), set)
                case .device(let set): title = String(format: Bundle.localizedString(forKey: "mame_health_detail_missing_device"), set)
            }
            result.append((title, (files[source] ?? []).map { ($0, nil) }))
        }

        if !audit.requiredDisks.isEmpty {
            result.append((Bundle.localizedString(forKey: "mame_health_detail_chd"), audit.requiredDisks.map { ("\($0).chd", nil) }))
        }

        // How the launch assembles the session.
        var session: [(String, String?)] = []
        if let staged = audit.gameStagedName {
            session.append((staged, Bundle.localizedString(forKey: "mame_health_detail_staged_game")))
        }
        for link in audit.links {
            session.append((link.stagedName, Bundle.localizedString(forKey: "mame_health_detail_linked_parent")))
        }
        for extraction in audit.extractions {
            let from: String
            switch extraction.source {
                case .game(let key): from = RetroRomFileManager.shared.fileItem(key: key)?.itemName ?? extraction.entryName
                case .bios(let fileName): from = fileName
            }
            session.append((extraction.stagedPath, String(format: Bundle.localizedString(forKey: "mame_health_detail_extracted"), from)))
        }
        if !session.isEmpty {
            result.append((Bundle.localizedString(forKey: "mame_health_detail_session"), session))
        }
        return result
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count + (repairPlan == nil ? 0 : 1)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == repairSection ? 1 : sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section != repairSection else { return nil }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionHeaderView.className) as? RGSectionHeaderView
            ?? RGSectionHeaderView(reuseIdentifier: RGSectionHeaderView.className)
        view.text = sections[section].title
        return view
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == repairSection else { return nil }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: RGSectionFooterView.className) as? RGSectionFooterView
            ?? RGSectionFooterView(reuseIdentifier: RGSectionFooterView.className)
        view.text = Bundle.localizedString(forKey: "mame_repair_footer")
        return view
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == repairSection, let repairPlan {
            confirmRepair(repairPlan)
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == repairSection {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = Bundle.localizedString(forKey: "mame_repair_action")
            cell.textLabel?.textColor = .mainColor
            cell.imageView?.image = UIImage(systemName: "wrench.and.screwdriver")
            cell.imageView?.tintColor = .mainColor
            return cell
        }
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: indexPath.section == 0 ? .value1 : .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = row.0
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = row.1
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        return cell
    }
}
