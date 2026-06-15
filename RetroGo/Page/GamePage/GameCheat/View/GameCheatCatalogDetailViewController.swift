//
//  GameCheatCatalogDetailViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/11.
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

final class GameCheatCatalogDetailViewController: UIViewController {

    private let cheat: RACheatItem
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(cheat: RACheatItem) {
        self.cheat = cheat
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = Bundle.localizedString(forKey: "cheat_catalog_detail_title")
        configureLayout()
        fillContent()
    }

    private func configureLayout() {
        stackView.axis = .vertical
        stackView.spacing = 18
        scrollView.addSubview(stackView)
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
            make.width.equalToSuperview().offset(-40)
        }
    }

    private func fillContent() {
        addTitle()
        addSection(rows: commonRows())
        if cheat.handler == .RETRO {
            addSection(rows: retroRows())
        } else {
            addSection(rows: [(Bundle.localizedString(forKey: "cheat_field_code"), cheat.code)])
        }
    }

    private func addTitle() {
        let title = UILabel()
        title.font = .boldSystemFont(ofSize: 24)
        title.textColor = .label
        title.numberOfLines = 0
        title.text = cheat.desc
        stackView.addArrangedSubview(title)
    }

    private func commonRows() -> [(String, String)] {
        var rows: [(String, String)] = [
            (Bundle.localizedString(forKey: "cheat_catalog_field_type"), cheat.handler == .RETRO ? "RETRO" : "EMU")
        ]
        if let english = cheat.descEnglish,
           !english.isEmpty,
           english != cheat.desc {
            rows.append((Bundle.localizedString(forKey: "cheat_catalog_field_english"), english))
        }
        rows.append((Bundle.localizedString(forKey: "cheat_catalog_field_source"), Bundle.localizedString(forKey: "cheat_catalog_source_builtin")))
        return rows
    }

    private func retroRows() -> [(String, String)] {
        [
            (Bundle.localizedString(forKey: "cheat_field_address"), hex(cheat.address)),
            (Bundle.localizedString(forKey: "cheat_field_value"), hex(cheat.value)),
            (Bundle.localizedString(forKey: "cheat_field_write_type"), writeTypeName(cheat.cheatType)),
            (Bundle.localizedString(forKey: "cheat_field_mem_size"), memorySizeName(cheat.memorySearchSize)),
            (Bundle.localizedString(forKey: "cheat_field_big_endian"), cheat.bigEndian ? Bundle.localizedString(forKey: "yes") : Bundle.localizedString(forKey: "no")),
            (Bundle.localizedString(forKey: "cheat_field_address_mask"), hex(cheat.addressMask)),
            (Bundle.localizedString(forKey: "cheat_field_repeat_count"), "\(cheat.repeatCount)"),
            (Bundle.localizedString(forKey: "cheat_field_repeat_value"), "\(cheat.repeatAddToValue)"),
            (Bundle.localizedString(forKey: "cheat_field_repeat_address"), "\(cheat.repeatAddToAddress)")
        ]
    }

    private func addSection(rows: [(String, String)]) {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 0
        card.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 8
        card.clipsToBounds = true

        for (index, row) in rows.enumerated() {
            if index > 0 { card.addArrangedSubview(separator()) }
            card.addArrangedSubview(rowView(title: row.0, value: row.1))
        }
        stackView.addArrangedSubview(card)
    }

    private func rowView(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 0

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 17)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 9
        stack.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        stack.isLayoutMarginsRelativeArrangement = true
        return stack
    }

    private func separator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.snp.makeConstraints { $0.height.equalTo(1.0 / UIScreen.main.scale) }
        return view
    }

    private func hex(_ value: UInt) -> String {
        String(format: "0x%X", value)
    }

    private func writeTypeName(_ raw: UInt) -> String {
        let key: String
        switch Int(raw) {
        case GameCheatType.increase.rawValue:     key = "cheat_write_increase"
        case GameCheatType.decrease.rawValue:     key = "cheat_write_decrease"
        case GameCheatType.runNextIfEq.rawValue:  key = "cheat_write_if_eq"
        case GameCheatType.runNextIfNeq.rawValue: key = "cheat_write_if_neq"
        case GameCheatType.runNextIfLt.rawValue:  key = "cheat_write_if_lt"
        case GameCheatType.runNextIfGt.rawValue:  key = "cheat_write_if_gt"
        default:                                  key = "cheat_write_set"
        }
        return Bundle.localizedString(forKey: key)
    }

    private func memorySizeName(_ raw: UInt) -> String {
        let key: String
        switch Int(raw) {
        case GameCheatMemorySize.bit1.rawValue:  key = "cheat_size_1bit"
        case GameCheatMemorySize.bit2.rawValue:  key = "cheat_size_2bit"
        case GameCheatMemorySize.bit4.rawValue:  key = "cheat_size_4bit"
        case GameCheatMemorySize.byte2.rawValue: key = "cheat_size_2byte"
        case GameCheatMemorySize.byte4.rawValue: key = "cheat_size_4byte"
        default:                                 key = "cheat_size_1byte"
        }
        return Bundle.localizedString(forKey: key)
    }
}
