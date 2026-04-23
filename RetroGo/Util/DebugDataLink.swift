//
//  DebugDataLink.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/21.
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

import Foundation

enum DebugDataLink {
    private static func symlinkDestination(at url: URL, fileManager: FileManager) -> String? {
        try? fileManager.destinationOfSymbolicLink(atPath: url.path)
    }

    static func sync() {
        let fm = FileManager.default

        guard
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("data", isDirectory: true),
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }

        let linkURL = documents.appendingPathComponent("retrogo_app_support_link", isDirectory: true)

        #if DEBUG
        do {
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

            if let target = symlinkDestination(at: linkURL, fileManager: fm) {
                let targetURL = URL(
                    fileURLWithPath: target,
                    relativeTo: linkURL.deletingLastPathComponent()
                ).standardizedFileURL
                if targetURL.path == appSupport.standardizedFileURL.path { return } // 已正确
                try fm.removeItem(at: linkURL)
            } else if fm.fileExists(atPath: linkURL.path) {
                try fm.removeItem(at: linkURL)
            }

            try fm.createSymbolicLink(atPath: linkURL.path, withDestinationPath: appSupport.path)
        } catch {
            print("Debug data symlink create failed: \(error)")
        }
        #else
        do {
            if symlinkDestination(at: linkURL, fileManager: fm) != nil {
                try fm.removeItem(at: linkURL) // Release 下删除
            }
        } catch {
            print("Release data symlink cleanup failed: \(error)")
        }
        #endif
    }
}
