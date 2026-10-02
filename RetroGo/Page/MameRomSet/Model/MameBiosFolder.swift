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

    /// CRC/size keys of an archive in the folder, read from the archive itself. Files in
    /// this folder can be replaced or edited outside RetroGo (e.g. via the Files app),
    /// and the romset index records no modification state, so it is only a fallback
    /// when the archive can't be read. Listing entries reads the directory, not the data.
    func entryKeys(fileName: String) -> Set<MameRomKey> {
        if let entries = try? RAArchiveReader.entriesOfArchive(atPath: filePath(fileName)) {
            return Set(entries.filter(\.hasCRC).map { MameRomKey(crc: $0.crc32, size: Int64(clamping: $0.size)) })
        }
        return MameRomSetPersistence.shared.archiveEntryKeys(owner: .bios(fileName: fileName)) ?? []
    }

    /// Required files of a BIOS/device set (for its default BIOS option) that no installed
    /// archive of the set holds, by the names MAME lists. Empty when complete; nil when
    /// the set is not a BIOS/device set in the catalog. Reads archive directories only.
    func missingFiles(ofSet setName: String) -> [String]? {
        let persistence = MameRomSetPersistence.shared
        guard let machine = persistence.machine(named: setName), machine.isSupportSet else { return nil }
        let present = entryKeys(ofSet: machine.name)
        return persistence.requiredRoms(of: machine.name, biosOption: machine.defaultBios)
            .filter { !present.contains($0.key) }
            .map(\.name)
    }

    /// Union of the keys of every installed archive of this set.
    func entryKeys(ofSet setName: String) -> Set<MameRomKey> {
        installedFileNames(ofSet: setName).reduce(into: Set<MameRomKey>()) { keys, fileName in
            keys.formUnion(entryKeys(fileName: fileName))
        }
    }
}
