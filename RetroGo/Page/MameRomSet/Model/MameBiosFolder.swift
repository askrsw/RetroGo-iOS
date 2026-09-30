//
//  MameBiosFolder.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/26.
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
import RACoordinator

/// The MAME system folder, whose files are all linked into every MAME session.
/// Archives there are named after their set ("neogeo.zip"), in zip or 7z.
struct MameBiosFolder {
    static let archiveExtensions = ["zip", "7z"]

    let path: String

    /// `core` must be the MAME core. Nil when its system folder cannot be created.
    init?(core: EmuCoreInfoItem) {
        guard let path = core.systemDirectoryPath() else { return nil }
        self.path = path
    }

    /// Archives of this set present in the folder, e.g. ["neogeo.zip"].
    func installedFileNames(ofSet setName: String) -> [String] {
        Self.archiveExtensions.map { "\(setName).\($0)" }.filter {
            FileManager.default.fileExists(atPath: filePath($0))
        }
    }

    func filePath(_ fileName: String) -> String {
        (path as NSString).appendingPathComponent(fileName)
    }

    /// CRC/size keys of an archive in the folder: from the romset index, or read directly
    /// when the file got there without being indexed (e.g. imported by hand).
    func entryKeys(fileName: String) -> Set<MameRomKey> {
        if let keys = MameRomSetPersistence.shared.archiveEntryKeys(owner: .bios(fileName: fileName)) {
            return keys
        }
        guard let entries = try? RAArchiveReader.entriesOfArchive(atPath: filePath(fileName)) else { return [] }
        return Set(entries.filter(\.hasCRC).map { MameRomKey(crc: $0.crc32, size: Int64(clamping: $0.size)) })
    }

    /// Union of the keys of every installed archive of this set.
    func entryKeys(ofSet setName: String) -> Set<MameRomKey> {
        installedFileNames(ofSet: setName).reduce(into: Set<MameRomKey>()) { keys, fileName in
            keys.formUnion(entryKeys(fileName: fileName))
        }
    }
}
