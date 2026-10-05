//
//  MameCatalogBuilder.swift
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

import MachO
import Foundation
import ObjcHelper
import RACoordinator
import os

enum MameCatalogBuilderError: LocalizedError {
    case coreNotFound
    case coreBinaryMissing
    /// Exporting runs code inside the MAME image, which must not overlap a running game.
    case gameRunning

    var errorDescription: String? {
        switch self {
            case .coreNotFound:
                return "MAME core not found"
            case .coreBinaryMissing:
                return "MAME core binary not found"
            case .gameRunning:
                return "A game is running; the MAME catalog will be built after it closes"
        }
    }
}

/// Keeps the catalog in mame_romset.db in sync with the bundled MAME core. The catalog
/// is never shipped with the app: it is exported from the core itself (-listxml) and
/// rebuilt whenever the core build changes (see `coreFingerprint`).
final class MameCatalogBuilder {
    static let shared = MameCatalogBuilder()
    private init() { }

    enum Outcome {
        case upToDate
        case rebuilt(MameCatalogSummary)
    }

    /// Serializes rebuilds; concurrent requests simply find the catalog up to date.
    private let queue = DispatchQueue(label: "com.retrogame.mamecatalog", qos: .utility)
    /// The binary cannot change while the app runs, so fingerprint it once per process.
    /// Only touched on `queue`.
    private var cachedFingerprint: (path: String, value: String)?
    /// Whether the last update left a catalog matching the core. Only touched on `queue`.
    private var catalogReady = false

    /// Call on the main thread (reads RetroArchX state); completion runs on the main thread.
    func updateIfNeeded(completion: ((Result<Outcome, Error>) -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))

        let ra = RetroArchX.shared()
        guard let core = ra.allCores.first(where: { $0.coreId == "mame" }) else {
            RetroGoLogger.mame.notice("MAME core not found among \(ra.allCores.count) cores")
            completion?(.failure(MameCatalogBuilderError.coreNotFound))
            return
        }
        let gameRunning = ra.currentCoreItem != nil && !ra.dummyCoreRunning
        RetroGoLogger.mame.info("Catalog update requested (game running: \(gameRunning ? "yes" : "no", privacy: .public))")

        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let result = Result { try self.update(core: core, gameRunning: gameRunning) }
            let seconds = CFAbsoluteTimeGetCurrent() - start
            switch result {
                case .success(.upToDate):
                    RetroGoLogger.mame.info("Catalog update finished: catalog up to date (\(seconds, format: .fixed(precision: 2))s)")
                case .success(.rebuilt):
                    RetroGoLogger.mame.info("Catalog update finished: catalog rebuilt (total \(seconds, format: .fixed(precision: 2))s)")
                case .failure(let error):
                    RetroGoLogger.mame.error("Catalog update failed after \(seconds, format: .fixed(precision: 2))s: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion?(result)
            }
        }
    }

    /// Blocks until pending catalog work has finished and reports whether a catalog
    /// matching the current core is available. For background work such as imports and
    /// launch checks; never call on the main thread.
    ///
    /// `queue.sync` (rather than a semaphore) lets GCD raise the queue to the caller's QoS,
    /// avoiding a priority inversion. The longest queued job is a rebuild (~3.5 s on device).
    func waitUntilReady() -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync { catalogReady }
    }

    private func update(core: EmuCoreInfoItem, gameRunning: Bool) throws -> Outcome {
        catalogReady = false
        let outcome = try updateCatalog(core: core, gameRunning: gameRunning)
        catalogReady = true
        // Still on the catalog queue, so imports and launch checks wait for the index too.
        MameLibraryScanner.scanIfNeeded(coreFingerprint: try coreFingerprint(core))
        return outcome
    }

    private func updateCatalog(core: EmuCoreInfoItem, gameRunning: Bool) throws -> Outcome {
        let persistence = MameRomSetPersistence.shared
        let fingerprint = try coreFingerprint(core)
        if persistence.hasCatalog(coreFingerprint: fingerprint) {
            RetroGoLogger.mame.info("Catalog matches core (build \(persistence.metaValue(.catalogBuild) ?? "unknown", privacy: .public))")
            return .upToDate
        }
        RetroGoLogger.mame.notice("Catalog missing or outdated (stored core fingerprint: \(persistence.metaValue(.catalogCoreFingerprint) ?? "none", privacy: .public))")
        guard !gameRunning else {
            throw MameCatalogBuilderError.gameRunning
        }

        let xmlURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mame-listxml-\(UUID().uuidString).xml")
        defer {
            try? FileManager.default.removeItem(at: xmlURL)
        }

        // 1. Export -listxml from the core.
        Self.logMemory("before export")
        let exportStart = CFAbsoluteTimeGetCurrent()
        try core.exportMameListXML(toPath: xmlURL.path)
        let exportSeconds = CFAbsoluteTimeGetCurrent() - exportStart
        RetroGoLogger.mame.debug("listxml export: \(exportSeconds, format: .fixed(precision: 2))s, XML \(Self.formatBytes(Self.fileSize(xmlURL.path)), privacy: .public)")
        Self.logMemory("after export")

        // 2. Parse and write in one transaction. Insert time is measured separately so the
        //    remainder of the fill phase is the XML parsing itself.
        let importStart = CFAbsoluteTimeGetCurrent()
        var insertSeconds: CFAbsoluteTime = 0
        var fillSeconds: CFAbsoluteTime = 0
        let summary = try persistence.replaceCatalog(coreFingerprint: fingerprint) { writer in
            let fillStart = CFAbsoluteTimeGetCurrent()
            let parser = MameListXMLParser { machine in
                let insertStart = CFAbsoluteTimeGetCurrent()
                try writer.insert(machine)
                insertSeconds += CFAbsoluteTimeGetCurrent() - insertStart
            }
            try parser.parse(contentsOf: xmlURL)
            fillSeconds = CFAbsoluteTimeGetCurrent() - fillStart
            return parser.build
        }
        let importSeconds = CFAbsoluteTimeGetCurrent() - importStart

        RetroGoLogger.mame.debug("Catalog import: \(importSeconds, format: .fixed(precision: 2))s total (XML parse \(fillSeconds - insertSeconds, format: .fixed(precision: 2))s, row inserts \(insertSeconds, format: .fixed(precision: 2))s, other \(importSeconds - fillSeconds, format: .fixed(precision: 2))s)")
        RetroGoLogger.mame.info("Catalog rebuilt: \(summary.machineCount) machines, \(summary.romCount) roms, \(summary.diskCount) disks, \(summary.deviceRefCount) device refs")
        let dbPath = AppConfig.shared.mameRomSetDatabasePath
        RetroGoLogger.mame.debug("Catalog database size: \(Self.formatBytes(Self.fileSize(dbPath)), privacy: .public) (+ WAL \(Self.formatBytes(Self.fileSize(dbPath + "-wal")), privacy: .public))")
        Self.logMemory("after import")
        return .rebuilt(summary)
    }

    // MARK: - Core binary

    /// Identifies the core build by its Mach-O LC_UUID. The linker derives the UUID from
    /// the linked output, so it changes with any code or driver change, while the
    /// re-signing (and stripping) done when the app is packaged leaves it intact. A plain
    /// file SHA-256 changed on every app build for that reason and forced a rebuild.
    /// Falls back to the file's SHA-256 when the binary has no readable UUID.
    private func coreFingerprint(_ core: EmuCoreInfoItem) throws -> String {
        let path = Self.coreBinaryPath(core)
        if let cachedFingerprint, cachedFingerprint.path == path {
            return cachedFingerprint.value
        }
        guard FileManager.default.fileExists(atPath: path) else {
            RetroGoLogger.mame.error("MAME core binary missing at \(path)")
            throw MameCatalogBuilderError.coreBinaryMissing
        }

        let start = CFAbsoluteTimeGetCurrent()
        let fingerprint: String
        if let uuid = Self.machOUUID(atPath: path) {
            fingerprint = "uuid:" + uuid
        } else {
            RetroGoLogger.mame.notice("No LC_UUID in core binary, falling back to SHA-256")
            fingerprint = "sha256:" + (try (URL(fileURLWithPath: path) as NSURL).computeSHA256String())
        }
        RetroGoLogger.mame.debug("MAME core fingerprint \(fingerprint, privacy: .public) (\(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 3))s): \(path)")
        cachedFingerprint = (path, fingerprint)
        return fingerprint
    }

    /// Reads LC_UUID from a 64-bit Mach-O, or from the arm64 slice of a universal binary
    /// (some prebuilt cores are universal binaries with a single slice). Nil otherwise.
    private static func machOUUID(atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        guard let sliceOffset = arm64SliceOffset(handle) else { return nil }
        let headerSize = MemoryLayout<mach_header_64>.size
        guard (try? handle.seek(toOffset: sliceOffset)) != nil,
              let headerData = try? handle.read(upToCount: headerSize), headerData.count == headerSize else {
            return nil
        }
        let header = headerData.withUnsafeBytes { $0.loadUnaligned(as: mach_header_64.self) }
        guard header.magic == MH_MAGIC_64,
              let commands = try? handle.read(upToCount: Int(header.sizeofcmds)),
              commands.count == Int(header.sizeofcmds) else {
            return nil
        }

        return commands.withUnsafeBytes { raw -> String? in
            var offset = 0
            for _ in 0..<header.ncmds {
                guard offset + MemoryLayout<load_command>.size <= raw.count else { return nil }
                let command = raw.loadUnaligned(fromByteOffset: offset, as: load_command.self)
                let size = Int(command.cmdsize)
                guard size >= MemoryLayout<load_command>.size, offset + size <= raw.count else { return nil }
                if command.cmd == LC_UUID, size >= MemoryLayout<uuid_command>.size {
                    let uuid = raw.loadUnaligned(fromByteOffset: offset, as: uuid_command.self).uuid
                    return UUID(uuid: uuid).uuidString
                }
                offset += size
            }
            return nil
        }
    }

    /// File offset of the Mach-O to read: 0 for a thin binary, the arm64 slice's offset
    /// for a universal binary. Fat headers are big-endian.
    private static func arm64SliceOffset(_ handle: FileHandle) -> UInt64? {
        guard let magicData = try? handle.read(upToCount: 4), magicData.count == 4 else { return nil }
        let magic = magicData.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard magic == FAT_MAGIC else {
            return 0
        }
        guard let countData = try? handle.read(upToCount: 4), countData.count == 4 else { return nil }
        let count = Int(countData.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) })
        let archSize = MemoryLayout<fat_arch>.size
        guard count > 0, count < 32,
              let archData = try? handle.read(upToCount: count * archSize), archData.count == count * archSize else {
            return nil
        }
        return archData.withUnsafeBytes { raw -> UInt64? in
            for index in 0..<count {
                let arch = raw.loadUnaligned(fromByteOffset: index * archSize, as: fat_arch.self)
                if cpu_type_t(bigEndian: arch.cputype) == CPU_TYPE_ARM64 {
                    return UInt64(UInt32(bigEndian: arch.offset))
                }
            }
            return nil
        }
    }

    /// corePath may point at the framework bundle or directly at its executable.
    private static func coreBinaryPath(_ core: EmuCoreInfoItem) -> String {
        let corePath = core.corePath
        guard corePath.hasSuffix(".framework") else {
            return corePath
        }
        if let executable = Bundle(path: corePath)?.executablePath {
            return executable
        }
        let name = ((corePath as NSString).lastPathComponent as NSString).deletingPathExtension
        return (corePath as NSString).appendingPathComponent(name)
    }

    // MARK: - Diagnostics

    private static func fileSize(_ path: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// Logs the process memory footprint (what jetsam limits count) and its peak so far.
    private static func logMemory(_ stage: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        RetroGoLogger.mame.debug("Memory \(stage, privacy: .public): footprint \(formatBytes(Int64(info.phys_footprint)), privacy: .public), peak \(formatBytes(info.ledger_phys_footprint_peak), privacy: .public)")
    }
}
