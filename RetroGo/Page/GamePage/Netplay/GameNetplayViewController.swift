//
//  GameNetplayViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/17.
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

/// In-game netplay room. Two states driven by the live session:
///   - idle: pick a nickname, host a room, or scan the LAN and tap a host to join;
///   - in-session: see the player roster (name / role / ping), toggle play/watch,
///     and leave. Disconnecting (here or by a peer) returns to the idle state, so
///     re-scanning is also the manual-reconnect path.
final class GameNetplayViewController: UIViewController {

    // RARCH_DEFAULT_PORT (55435) is occupied on iOS at process start and collides
    // with RARCH_DISCOVERY_PORT, so host on a free port. Clients use the host's
    // advertised port, so the exact value isn't interop-critical.
    private static let defaultPort: UInt16 = 55556
    private static let nicknameKey = "netplay_nickname"

    // Idle controls
    private let nicknameValueLabel = UILabel()
    private lazy var nicknameCard = makeNicknameCard()
    private var currentNickname = ""
    private let hostButton = UIButton(configuration: .filled())
    private let scanButton = UIButton(configuration: .filled())
    private let idleStack = UIStackView()

    // In-session controls
    private let leaveButton = UIButton(configuration: .filled())
    private let sessionStack = UIStackView()

    private let statusLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var hosts: [RANetplayHost] = []
    private var players: [RANetplayPlayer] = []
    private var scanning = false
    private var refreshTimer: Timer?
    private var joinPollsLeft = 0

    private var isSession: Bool { RANetplayCoordinator.shared.isNetplayEnabled }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = L("gamepage_toolbar_netplay")
        let titleIcon = IconRender.shared.settingsIcon(
            symbol: "network",
            background: .systemGreen,
            size: CGSize(width: 28, height: 28)
        )
        navigationItem.titleView = Self.makeIconTitleView(Bundle.localizedString(forKey: "gamepage_toolbar_netplay"), icon: titleIcon)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped))

        configureControls()
        configureLayout()
        loadNickname()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
        // While in a session, peers/ping change over time and a peer may leave.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLiveState()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Setup

    private func configureControls() {
        // Only Host is a solid accent CTA; the rest are calm gray buttons with
        // bright text (red reserved for the destructive Leave).
        style(hostButton, title: L("netplay_host"), kind: .primary)
        hostButton.addTarget(self, action: #selector(hostTapped), for: .touchUpInside)

        style(scanButton, title: L("netplay_scan"), kind: .neutral)
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)

        style(leaveButton, title: L("netplay_leave"), kind: .destructive)
        leaveButton.addTarget(self, action: #selector(leaveTapped), for: .touchUpInside)

        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        idleStack.axis = .vertical
        idleStack.spacing = 16
        idleStack.setCustomSpacing(24, after: nicknameCard)
        [nicknameCard, hostButton, scanButton].forEach { idleStack.addArrangedSubview($0) }

        sessionStack.axis = .vertical
        sessionStack.spacing = 12
        sessionStack.addArrangedSubview(leaveButton)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
    }

    private func configureLayout() {
        let header = UIStackView(arrangedSubviews: [idleStack, sessionStack, statusLabel])
        header.axis = .vertical
        header.spacing = 12

        view.addSubview(header)
        view.addSubview(tableView)
        header.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    // MARK: - State

    /// Full rebuild: swaps idle/session controls and reloads the list.
    private func refresh() {
        let session = isSession
        idleStack.isHidden = session
        sessionStack.isHidden = !session

        let coord = RANetplayCoordinator.shared
        if session {
            players = coord.players()
            statusLabel.text = coord.isServer
                ? String(format: L("netplay_status_hosting_fmt"), Int(Self.defaultPort))
                : L("netplay_in_session_client")
        } else if !scanning {
            statusLabel.text = L("netplay_status_idle")
        }
        tableView.reloadData()
    }

    /// Lightweight tick used by the timer: refresh the roster/state without
    /// clobbering a transient status message (e.g. while scanning).
    private func refreshLiveState() {
        if isSession {
            refresh()
        }
    }

    // MARK: - Nickname

    /// A tappable card: squircle icon + "昵称" caption + the current value + a pencil.
    /// Tapping anywhere (card or pencil) opens an alert to edit it.
    private func makeNicknameCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 12

        let iconView = UIImageView(image: IconRender.shared.settingsIcon(
            symbol: "person.crop.circle.fill", background: .mainColor, size: CGSize(width: 30, height: 30)))
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let caption = UILabel()
        caption.text = L("netplay_nickname")
        caption.font = .preferredFont(forTextStyle: .footnote)
        caption.textColor = .secondaryLabel

        nicknameValueLabel.font = .preferredFont(forTextStyle: .body)
        nicknameValueLabel.textColor = .label
        nicknameValueLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [caption, nicknameValueLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        // Only this control opens the editor (not the whole card). A small tinted
        // capsule reads as tappable better than a bare pencil glyph.
        var editConfig = UIButton.Configuration.tinted()
        editConfig.image = UIImage(systemName: "square.and.pencil")
        editConfig.baseBackgroundColor = .mainColor
        editConfig.baseForegroundColor = .mainColor
        editConfig.cornerStyle = .capsule
        editConfig.buttonSize = .small
        let editButton = UIButton(configuration: editConfig)
        editButton.setContentHuggingPriority(.required, for: .horizontal)
        editButton.addTarget(self, action: #selector(editNicknameTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [iconView, textStack, editButton])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        card.addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        }
        return card
    }

    private func loadNickname() {
        let saved = UserDefaults.standard.string(forKey: Self.nicknameKey)
        applyNickname((saved?.isEmpty == false) ? saved! : UIDevice.current.name)
    }

    @objc private func editNicknameTapped() {
        let alert = UIAlertController(title: L("netplay_nickname"), message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.text = self?.currentNickname
            tf.placeholder = self?.L("netplay_nickname_placeholder")
            tf.autocorrectionType = .no
            tf.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: L("cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("ok"), style: .default) { [weak self, weak alert] _ in
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard let self, !name.isEmpty else { return }
            self.applyNickname(name)
        })
        present(alert, animated: true)
    }

    private func applyNickname(_ name: String) {
        currentNickname = name
        nicknameValueLabel.text = name
        UserDefaults.standard.set(name, forKey: Self.nicknameKey)
        RANetplayCoordinator.shared.nickname = name
    }

    // MARK: - Actions

    @objc private func hostTapped() {
        let ok = RANetplayCoordinator.shared.startHost(onPort: Self.defaultPort)
        if !ok { statusLabel.text = L("netplay_status_host_failed") }
        refresh()
    }

    @objc private func scanTapped() {
        scanning = true
        statusLabel.text = L("netplay_status_scanning")
        RANetplayCoordinator.shared.scanForHosts(withTimeout: 2.0) { [weak self] found in
            guard let self else { return }
            self.scanning = false
            self.hosts = found
            self.statusLabel.text = found.isEmpty
                ? self.L("netplay_status_scan_none")
                : String(format: self.L("netplay_status_scan_found_fmt"), found.count)
            self.tableView.reloadData()
        }
    }

    @objc private func leaveTapped() {
        RANetplayCoordinator.shared.disconnect()
        refresh()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    /// Join-compatibility: the engine only *warns* on RetroGo-version, core-version
    /// or content-CRC mismatch, so the UI must hard-block them.
    private enum HostCompat { case ok, versionMismatch, gameMismatch }

    private func compatibility(of host: RANetplayHost) -> HostCompat {
        let coord = RANetplayCoordinator.shared
        if host.appIdentity != coord.localAppIdentity { return .versionMismatch }
        let localCRC = coord.localContentCRC
        if localCRC != 0, host.contentCRC != 0, host.contentCRC != localCRC { return .gameMismatch }
        return .ok
    }

    private func join(_ host: RANetplayHost, from sourceView: UIView) {
        let coord = RANetplayCoordinator.shared
        switch compatibility(of: host) {
        case .versionMismatch:
            let other = host.appIdentity.isEmpty ? L("netplay_unknown_version") : host.appIdentity
            presentBlockAlert(title: L("netplay_version_mismatch"),
                              message: String(format: L("netplay_version_mismatch_msg_fmt"), coord.localAppIdentity, other))
            return
        case .gameMismatch:
            presentBlockAlert(title: L("netplay_game_mismatch"), message: L("netplay_game_mismatch_msg"))
            return
        case .ok:
            break
        }
        // Role is chosen here and fixed for the session (no mid-session toggle).
        let sheet = UIAlertController(
            title: host.nickname.isEmpty ? host.address : host.nickname,
            message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L("netplay_join_as_player"), style: .default) { [weak self] _ in
            self?.connect(host, asSpectator: false)
        })
        sheet.addAction(UIAlertAction(title: L("netplay_join_as_spectator"), style: .default) { [weak self] _ in
            self?.connect(host, asSpectator: true)
        })
        sheet.addAction(UIAlertAction(title: L("cancel"), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sourceView
            pop.sourceRect = sourceView.bounds
        }
        present(sheet, animated: true)
    }

    private func connect(_ host: RANetplayHost, asSpectator: Bool) {
        let coord = RANetplayCoordinator.shared
        coord.setRemoteHostNick(host.nickname)
        guard coord.joinHostAddress(host.address, port: host.port, asSpectator: asSpectator) else {
            statusLabel.text = L("netplay_status_join_no_game")
            return
        }
        statusLabel.text = String(format: L("netplay_status_joining_fmt"), "\(host.address):\(host.port)")
        refresh()
        // Joining as a player but the game's controller slots are all taken means
        // the server drops you to spectator. Detect that and tell the user.
        if !asSpectator {
            joinPollsLeft = 12
            pollPlayerJoinOutcome()
        }
    }

    private func pollPlayerJoinOutcome() {
        let coord = RANetplayCoordinator.shared
        guard coord.isNetplayEnabled else { return }   // disconnected/failed; monitor shows status
        if coord.isConnected {
            // Let the play/spectate mode settle after the handshake, then check.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, RANetplayCoordinator.shared.isNetplayEnabled else { return }
                if RANetplayCoordinator.shared.isSpectating {
                    self.presentBlockAlert(title: self.L("netplay_room_full_title"),
                                           message: self.L("netplay_room_full_msg"))
                }
                self.refresh()
            }
            return
        }
        joinPollsLeft -= 1
        guard joinPollsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pollPlayerJoinOutcome()
        }
    }

    // MARK: - Helpers

    private func L(_ key: String) -> String { Bundle.localizedString(forKey: key) }

    private func presentBlockAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("ok"), style: .default))
        present(alert, animated: true)
    }

    private enum ButtonStyle { case primary, neutral, destructive }

    /// primary = solid accent CTA; neutral = gray with bright label text;
    /// destructive = gray with bright red text. Text stays high-contrast (the
    /// tinted style rendered dim, low-contrast text on the dark background).
    private func style(_ button: UIButton, title: String, kind: ButtonStyle) {
        var config: UIButton.Configuration
        switch kind {
        case .primary:
            config = .filled()
            config.baseBackgroundColor = .mainColor
        case .neutral:
            config = .gray()
            config.baseForegroundColor = .label
        case .destructive:
            config = .gray()
            config.baseForegroundColor = .systemRed
        }
        config.title = title
        config.cornerStyle = .large
        config.buttonSize = .large
        button.configuration = config
    }
}

// MARK: - List (discovered hosts when idle, player roster when in-session)

extension GameNetplayViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isSession ? players.count : hosts.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isSession { return players.isEmpty ? nil : L("netplay_players") }
        return hosts.isEmpty ? nil : L("netplay_discovered_hosts")
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if isSession {
            configurePlayerCell(&content, player: players[indexPath.row])
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let compatible = configureHostCell(&content, host: hosts[indexPath.row])
            cell.accessoryType = compatible ? .disclosureIndicator : .none
            cell.selectionStyle = compatible ? .default : .none
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isSession else { return }
        let sourceView = tableView.cellForRow(at: indexPath) ?? tableView
        join(hosts[indexPath.row], from: sourceView)
    }

    private func configurePlayerCell(_ content: inout UIListContentConfiguration, player: RANetplayPlayer) {
        content.text = player.name.isEmpty ? "—" : player.name
        var parts: [String] = []
        if player.isSelf { parts.append(L("netplay_role_you")) }
        if player.isHost { parts.append(L("netplay_role_host")) }
        if player.spectating { parts.append(L("netplay_role_spectating")) }
        if player.pingMs >= 0 { parts.append(String(format: L("netplay_ping_fmt"), player.pingMs)) }
        content.secondaryText = parts.joined(separator: "  ·  ")
        content.secondaryTextProperties.color = .secondaryLabel
    }

    /// Returns whether the host is join-compatible (same build AND same game).
    @discardableResult
    private func configureHostCell(_ content: inout UIListContentConfiguration, host: RANetplayHost) -> Bool {
        content.text = host.nickname.isEmpty ? host.address : host.nickname
        let compat = compatibility(of: host)
        let shownVersion = host.appIdentity.isEmpty ? L("netplay_unknown_version") : host.appIdentity
        let note: String
        switch compat {
        case .ok:              note = shownVersion
        case .versionMismatch: note = "\(shownVersion) · \(L("netplay_version_mismatch"))"
        case .gameMismatch:    note = "\(shownVersion) · \(L("netplay_game_mismatch"))"
        }
        content.secondaryText = "\(host.address):\(host.port)  ·  \(host.coreName)\n\(note)"
        content.secondaryTextProperties.color = (compat == .ok) ? .secondaryLabel : .systemRed
        return compat == .ok
    }
}
