//
//  CoreBiosLaunchCheck.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/8.
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
import os

/// Runs before a game starts in a core whose core.info lists required BIOS files.
/// When none of them is in the core's BIOS folder, the user is told and can still
/// launch. Cores such as Beetle PSX and Beetle Saturn mark one BIOS per region as
/// required while a game only needs its own region's, so having any of them counts
/// as ready. MAME checks its sets in MameLaunchCheck instead.
enum CoreBiosLaunchCheck {
    /// Call on the main thread; `launch` runs on the main thread.
    static func run(core: EmuCoreInfoItem, launch: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard core.coreId != MameImportScreener.mameCoreId else {
            launch()
            return
        }
        let required = (core.firmwares ?? []).filter { !$0.optional }
        guard !required.isEmpty, !required.contains(where: \.fileExists) else {
            launch()
            return
        }

        RetroGoLogger.game.notice("Launch check: \(core.coreId, privacy: .public) has none of its \(required.count, privacy: .public) required BIOS files")
        let files = required.map { firmware -> String in
            let desc = firmware.desc.flatMap(description(from:))
            return "• " + firmware.name + (desc.map { " (\($0))" } ?? "")
        }
        var paragraphs = [String(format: Bundle.localizedString(forKey: "bios_check_message"),
                                 core.displayName, files.joined(separator: "\n"))]
        if required.count > 1 {
            paragraphs.append(Bundle.localizedString(forKey: "bios_check_region_hint"))
        }
        paragraphs.append(Bundle.localizedString(forKey: "bios_check_add_hint"))
        let message = paragraphs.joined(separator: "\n\n")
        let alert = UIAlertController(title: Bundle.localizedString(forKey: "bios_check_title"),
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "bios_check_launch_anyway"), style: .default) { _ in
            launch()
        })
        UIViewController.currentActive()?.present(alert, animated: true)
    }

    /// core.info descriptions repeat the file name ("sega_101.bin (Saturn JP BIOS)");
    /// keep only the part in parentheses.
    private static func description(from desc: String) -> String? {
        guard let open = desc.firstIndex(of: "("), desc.hasSuffix(")") else { return nil }
        let text = desc[desc.index(after: open)..<desc.index(before: desc.endIndex)]
        return text.isEmpty ? nil : String(text)
    }
}
