//
//  GameCheatCollectionViewCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/6/6.
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

/// One cheat row, as a list cell: name over the raw code, a switch accessory to
/// toggle it, and — for user cheats — the system `.reorder()` accessory (the
/// 3-line grip) to drag-reorder without an edit mode. The switch reports through
/// `onToggle`; the row tap (handled by the list) opens the editor for user cheats.
final class GameCheatCollectionViewCell: UICollectionViewListCell {
    static let reuseId = "GameCheatCollectionViewCell"

    private let enableSwitch = UISwitch(frame: .zero)

    /// New switch value.
    var onToggle: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        enableSwitch.onTintColor = .mainColor
        enableSwitch.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: GameCheatItem) {
        configure(
            title: item.desc,
            subtitle: Self.subtitle(for: item),
            enabled: item.enabled,
            showsReorder: true,
            showsDisclosure: false)
    }

    func configure(with item: RACheatItem) {
        configure(
            title: item.desc,
            subtitle: Self.subtitle(for: item),
            enabled: item.enabled,
            showsReorder: false,
            showsDisclosure: true)
    }

    private func configure(title: String,
                           subtitle: String,
                           enabled: Bool,
                           showsReorder: Bool,
                           showsDisclosure: Bool) {
        var content = UIListContentConfiguration.subtitleCell()
        content.text = title
        content.textProperties.font = .boldSystemFont(ofSize: UIFont.labelFontSize)
        content.secondaryText = subtitle
        content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: UIFont.labelFontSize - 3, weight: .regular)
        content.secondaryTextProperties.color = .secondaryLabel
        // Default subtitle spacing is tight; give the name and code more breathing room.
        content.textToSecondaryTextVerticalPadding = 5
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        contentConfiguration = content

        enableSwitch.isOn = enabled

        let switchAccessory = UICellAccessory.customView(
            configuration: .init(customView: enableSwitch, placement: .trailing(displayed: .always))
        )
        var rowAccessories: [UICellAccessory] = [switchAccessory]
        if showsDisclosure {
            rowAccessories.append(.disclosureIndicator(displayed: .always))
        }
        if showsReorder {
            rowAccessories.append(.reorder(displayed: .always))
        }
        accessories = rowAccessories
    }

    /// EMU rows show the raw code; RETRO rows show a compact `地址 05C6  值 02`
    /// (value width follows the memory size), matching the reference NES app.
    static func subtitle(for item: GameCheatItem) -> String {
        switch item.handler {
        case .emu:
            return item.code
        case .retro:
            let valueWidth: Int
            switch item.memorySize {
            case .byte4: valueWidth = 8
            case .byte2: valueWidth = 4
            default:     valueWidth = 2
            }
            let addr = String(format: "%04X", item.address)
            let val  = String(format: "%0\(valueWidth)X", item.value)
            return String(format: Bundle.localizedString(forKey: "cheat_retro_subtitle_format"), addr, val)
        }
    }

    static func subtitle(for item: RACheatItem) -> String {
        if item.handler == .RETRO {
            return String(
                format: Bundle.localizedString(forKey: "cheat_retro_subtitle_format"),
                String(format: "%04X", item.address),
                String(format: "%X", item.value))
        }
        return item.code
    }

    @objc
    private func switchChanged(_ sender: UISwitch) {
        onToggle?(sender.isOn)
    }
}
