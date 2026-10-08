//
//  RetroRomMdsCueSheet.swift
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

import Foundation
import RACoordinator
import os

/// Lets cores that read cue sheets but not Alcohol 120% images (Beetle Saturn,
/// for example) open an mds/mdf game: the mds track table is turned into a cue
/// sheet that points at the mdf by absolute path. The sheet lives in Caches and is
/// rebuilt on every launch, so the user's game folder is never touched. It keeps
/// the mds base name, so the core names its save files as it would for a cue/bin
/// copy of the same game.
enum RetroRomMdsCueSheet {
    /// Whether launching `entryPath` with `core` should go through a generated cue.
    static func isNeeded(entryPath: String, core: EmuCoreInfoItem) -> Bool {
        guard (entryPath as NSString).pathExtension.lowercased() == "mds" else { return false }
        let extensions = Set((core.extensions ?? []).map { $0.lowercased() })
        return !extensions.contains("mds") && extensions.contains("cue")
    }

    /// Writes the cue sheet for `mdsPath` under `key` and returns its path, or nil
    /// when the image has a layout a cue sheet cannot describe.
    static func make(mdsPath: String, key: String) -> String? {
        do {
            let mdfPath = try imagePath(for: mdsPath)
            let mdfSize = try FileManager.default.attributesOfItem(atPath: mdfPath)[.size] as? Int ?? 0
            let tracks = try parseTracks(Data(contentsOf: URL(fileURLWithPath: mdsPath)), imageSize: mdfSize)
            guard !mdfPath.contains("\"") else { throw ConversionError.unsupported("quote in image path") }

            var lines = ["FILE \"\(mdfPath)\" BINARY"]
            for track in tracks {
                lines.append(String(format: "  TRACK %02d %@", track.number, track.mode))
                if let pregapIndex = track.pregapIndex {
                    lines.append("    INDEX 00 \(msf(pregapIndex))")
                } else if track.number > 1 && track.pregap > 0 {
                    lines.append("    PREGAP \(msf(track.pregap))")
                }
                lines.append("    INDEX 01 \(msf(track.index))")
            }

            let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = caches.appendingPathComponent("GeneratedCue", isDirectory: true).appendingPathComponent(key, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let baseName = ((mdsPath as NSString).lastPathComponent as NSString).deletingPathExtension
            let cueURL = folder.appendingPathComponent(baseName + ".cue")
            try (lines.joined(separator: "\r\n") + "\r\n").write(to: cueURL, atomically: true, encoding: .utf8)
            RetroGoLogger.game.info("Generated a cue sheet with \(tracks.count, privacy: .public) tracks for an mds image")
            return cueURL.path
        } catch {
            RetroGoLogger.game.notice("Cannot generate a cue sheet for \(mdsPath): \(String(describing: error))")
            return nil
        }
    }

    private enum ConversionError: Error {
        case missingImage
        case unsupported(String)
    }

    private struct Track {
        let number: Int
        let mode: String
        let pregap: Int
        /// File sector of INDEX 00 when the pregap is stored in the image.
        let pregapIndex: Int?
        /// File sector of INDEX 01.
        let index: Int
    }

    private static func imagePath(for mdsPath: String) throws -> String {
        let folder = (mdsPath as NSString).deletingLastPathComponent
        let baseName = ((mdsPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let names = try FileManager.default.contentsOfDirectory(atPath: folder)
        guard let name = names.first(where: {
            ($0 as NSString).pathExtension.lowercased() == "mdf" && ($0 as NSString).deletingPathExtension == baseName
        }) else {
            throw ConversionError.missingImage
        }
        return (folder as NSString).appendingPathComponent(name)
    }

    /// Reads the single-session track table of an MDS v1 file. Only images whose
    /// tracks all use one sector size without subchannel data are accepted.
    private static func parseTracks(_ data: Data, imageSize: Int) throws -> [Track] {
        let bytes = [UInt8](data)
        func u8(_ offset: Int) throws -> Int {
            guard offset >= 0, offset < bytes.count else { throw ConversionError.unsupported("truncated mds") }
            return Int(bytes[offset])
        }
        func u16(_ offset: Int) throws -> Int {
            let low = try u8(offset), high = try u8(offset + 1)
            return low | high << 8
        }
        func u32(_ offset: Int) throws -> Int {
            let low = try u16(offset), high = try u16(offset + 2)
            return low | high << 16
        }
        func u64(_ offset: Int) throws -> Int {
            let low = try u32(offset), high = try u32(offset + 4)
            return low | high << 32
        }

        guard bytes.count >= 0x58, String(decoding: bytes[0..<16], as: UTF8.self) == "MEDIA DESCRIPTOR" else {
            throw ConversionError.unsupported("not an mds file")
        }
        // 0-2 are CD-ROM/CD-R/CD-RW; DVD images have no cue equivalent.
        guard try u16(0x12) <= 2 else { throw ConversionError.unsupported("not a CD image") }
        guard try u16(0x14) == 1 else { throw ConversionError.unsupported("multi-session image") }

        let session = try u32(0x50)
        let blockCount = try u8(session + 0x0A)
        let blocks = try u32(session + 0x14)

        struct Entry { let number: Int; let mode: Int; let sectorSize: Int; let offset: Int; let pregap: Int; let length: Int }
        var entries: [Entry] = []
        for i in 0..<blockCount {
            let block = blocks + i * 80
            let point = try u8(block + 4)
            guard point >= 1, point <= 99 else { continue }
            let extra = try u32(block + 0x0C)
            guard extra > 0 else { throw ConversionError.unsupported("track without extra block") }
            entries.append(Entry(number: point,
                                 mode: try u8(block) & 0x0F,
                                 sectorSize: try u16(block + 0x10),
                                 offset: try u64(block + 0x28),
                                 pregap: try u32(extra),
                                 length: try u32(extra + 4)))
        }
        entries.sort { $0.number < $1.number }

        guard let sectorSize = entries.first?.sectorSize, entries.allSatisfy({ $0.sectorSize == sectorSize }) else {
            throw ConversionError.unsupported("no tracks or mixed sector sizes")
        }
        // 2448-byte sectors carry interleaved subchannel data, which a cue cannot describe.
        guard sectorSize == 2352 || sectorSize == 2048 else {
            throw ConversionError.unsupported("sector size \(sectorSize)")
        }

        var tracks: [Track] = []
        for (i, entry) in entries.enumerated() {
            let mode: String
            switch (entry.mode, sectorSize) {
            case (0x9, 2352): mode = "AUDIO"
            case (0xA, _): mode = "MODE1/\(sectorSize)"
            case (0xB...0xD, 2352): mode = "MODE2/2352"
            default: throw ConversionError.unsupported("track mode \(entry.mode) with \(sectorSize)-byte sectors")
            }
            guard entry.offset % sectorSize == 0 else { throw ConversionError.unsupported("unaligned track offset") }
            let start = entry.offset / sectorSize
            let end = (i + 1 < entries.count ? entries[i + 1].offset : imageSize) / sectorSize
            guard end > start else { throw ConversionError.unsupported("tracks out of order") }

            // Alcohol usually leaves the pregap out of the image; when the track's
            // file span is the pregap plus its length, the pregap is stored.
            let storesPregap = entry.number > 1 && entry.pregap > 0 && end - start == entry.pregap + entry.length
            tracks.append(Track(number: entry.number,
                                mode: mode,
                                pregap: entry.pregap,
                                pregapIndex: storesPregap ? start : nil,
                                index: storesPregap ? start + entry.pregap : start))
        }
        return tracks
    }

    private static func msf(_ sectors: Int) -> String {
        String(format: "%02d:%02d:%02d", sectors / 4500, sectors / 75 % 60, sectors % 75)
    }
}
