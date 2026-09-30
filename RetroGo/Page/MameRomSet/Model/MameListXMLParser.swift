//
//  MameListXMLParser.swift
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
import libxml2

enum MameListXMLParserError: LocalizedError {
    case unreadable(URL)
    case malformed(String)

    var errorDescription: String? {
        switch self {
            case .unreadable(let url):
                return "Cannot read \(url.lastPathComponent)"
            case .malformed(let reason):
                return "Malformed MAME listxml: \(reason)"
        }
    }
}

/// Streams a MAME -listxml file and hands each `<machine>` to a callback, so the
/// whole catalog (70+ MB of XML) is never held in memory.
///
/// Uses libxml2's SAX2 push parser rather than Foundation's XMLParser: about two
/// thirds of the ~1.4M elements (dipswitches, ports, chips...) are irrelevant, and
/// XMLParser builds an attribute dictionary for every one of them, which made parsing
/// take over 10 s on an iPhone 15 Pro Max. Here element names are compared as C
/// strings and Swift strings are created only for the attributes actually read.
final class MameListXMLParser {
    /// `build` attribute of the root `<mame>` element, e.g. "0.289 (9069f39340f)".
    /// Available once the first machine has been delivered.
    private(set) var build: String?

    private let onMachine: (MameCatalogMachine) throws -> Void

    private enum TextField {
        case description, year, manufacturer
    }

    private var machine: MameCatalogMachine?
    private var seenRoms = Set<MameCatalogMachine.Rom>()
    private var seenDisks = Set<MameCatalogMachine.Disk>()
    private var seenDevices = Set<String>()
    private var firstBios: String?
    /// Element depth below the current `<machine>`; only direct children (1) are read.
    private var machineDepth = 0
    private var textField: TextField?
    private var text: [UInt8] = []
    private var failure: Error?
    private var context: xmlParserCtxtPtr?

    private static let chunkSize = 256 * 1024

    init(onMachine: @escaping (MameCatalogMachine) throws -> Void) {
        self.onMachine = onMachine
    }

    /// Parses synchronously on the calling thread. Errors thrown by `onMachine` stop
    /// parsing and are rethrown as is.
    func parse(contentsOf url: URL) throws {
        guard let file = fopen(url.path, "rb") else {
            throw MameListXMLParserError.unreadable(url)
        }
        defer { fclose(file) }

        var handler = xmlSAXHandler()
        handler.initialized = UInt32(XML_SAX2_MAGIC)
        handler.startElementNs = { userData, localName, _, _, _, _, attributeCount, _, attributes in
            guard let userData, let localName else { return }
            Unmanaged<MameListXMLParser>.fromOpaque(userData).takeUnretainedValue()
                .didStartElement(localName, attributes: Attributes(count: Int(attributeCount), base: attributes))
        }
        handler.endElementNs = { userData, _, _, _ in
            guard let userData else { return }
            Unmanaged<MameListXMLParser>.fromOpaque(userData).takeUnretainedValue().didEndElement()
        }
        handler.characters = { userData, characters, length in
            guard let userData, let characters else { return }
            Unmanaged<MameListXMLParser>.fromOpaque(userData).takeUnretainedValue()
                .didFindCharacters(UnsafeBufferPointer(start: characters, count: Int(length)))
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard let context = xmlCreatePushParserCtxt(&handler, userData, nil, 0, url.path) else {
            throw MameListXMLParserError.unreadable(url)
        }
        self.context = context
        defer {
            xmlFreeParserCtxt(context)
            self.context = nil
        }
        // NOENT: deliver attribute values with entities decoded ("&amp;" -> "&").
        // NONET: never fetch anything referenced by the document.
        xmlCtxtUseOptions(context, Int32(XML_PARSE_NOENT.rawValue | XML_PARSE_NONET.rawValue))

        var buffer = [CChar](repeating: 0, count: Self.chunkSize)
        while true {
            let count = fread(&buffer, 1, buffer.count, file)
            if count == 0 && ferror(file) != 0 {
                throw MameListXMLParserError.unreadable(url)
            }
            let result = xmlParseChunk(context, buffer, Int32(count), count == 0 ? 1 : 0)
            if let failure {
                throw failure
            }
            if result != 0 {
                throw MameListXMLParserError.malformed(Self.describeError(context, code: result))
            }
            if count == 0 {
                break
            }
        }
    }

    private static func describeError(_ context: xmlParserCtxtPtr, code: Int32) -> String {
        guard let error = xmlCtxtGetLastError(context) else {
            return "libxml2 error \(code)"
        }
        let message = error.pointee.message.map { String(cString: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "error \(code)"
        return "line \(error.pointee.line): \(message)"
    }

    private func fail(_ error: Error) {
        if failure == nil {
            failure = error
        }
        if let context {
            xmlStopParser(context)
        }
    }

    private var lineNumber: Int {
        context.map { Int(xmlSAX2GetLineNumber($0)) } ?? 0
    }

    // MARK: - SAX events

    private func didStartElement(_ name: UnsafePointer<xmlChar>, attributes: Attributes) {
        if machine != nil {
            machineDepth += 1
            if machineDepth == 1 {
                readChild(name, attributes)
            }
            return
        }
        if Self.equals(name, "machine") {
            beginMachine(attributes)
        } else if Self.equals(name, "mame") {
            build = attributes["build"]
        }
    }

    private func didEndElement() {
        guard machine != nil else { return }
        if machineDepth == 0 {
            // Closing </machine> itself.
            endMachine()
            return
        }
        if machineDepth == 1, let textField {
            let value = String(decoding: text, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            switch textField {
                case .description: machine?.description = value
                case .year: machine?.year = value
                case .manufacturer: machine?.manufacturer = value
            }
            self.textField = nil
            text.removeAll(keepingCapacity: true)
        }
        machineDepth -= 1
    }

    private func didFindCharacters(_ characters: UnsafeBufferPointer<xmlChar>) {
        if textField != nil {
            text.append(contentsOf: characters)
        }
    }

    // MARK: - Element handlers

    private func beginMachine(_ attributes: Attributes) {
        guard let name = attributes["name"], !name.isEmpty else {
            fail(MameListXMLParserError.malformed("machine without a name at line \(lineNumber)"))
            return
        }
        var machine = MameCatalogMachine(name: name)
        machine.cloneOf = attributes["cloneof"]
        machine.romOf = attributes["romof"]
        machine.isBios = attributes.isYes("isbios")
        machine.isDevice = attributes.isYes("isdevice")
        machine.runnable = attributes["runnable"] != "no"
        self.machine = machine
        seenRoms.removeAll(keepingCapacity: true)
        seenDisks.removeAll(keepingCapacity: true)
        seenDevices.removeAll(keepingCapacity: true)
        firstBios = nil
        machineDepth = 0
    }

    private func endMachine() {
        guard var machine else { return }
        self.machine = nil
        if machine.defaultBios == nil {
            machine.defaultBios = firstBios
        }
        do {
            try onMachine(machine)
        } catch {
            fail(error)
        }
    }

    /// Ordered by frequency in real listxml output.
    private func readChild(_ name: UnsafePointer<xmlChar>, _ attributes: Attributes) {
        if Self.equals(name, "rom") {
            readRom(attributes)
        } else if Self.equals(name, "device_ref") {
            if let device = attributes["name"], seenDevices.insert(device).inserted {
                machine?.devices.append(device)
            }
        } else if Self.equals(name, "biosset") {
            guard let bios = attributes["name"] else { return }
            if firstBios == nil {
                firstBios = bios
            }
            if attributes.isYes("default") {
                machine?.defaultBios = bios
            }
        } else if Self.equals(name, "description") {
            textField = .description
        } else if Self.equals(name, "year") {
            textField = .year
        } else if Self.equals(name, "manufacturer") {
            textField = .manufacturer
        } else if Self.equals(name, "driver") {
            machine?.driverStatus = attributes["status"]
        } else if Self.equals(name, "disk") {
            guard let diskName = attributes["name"] else { return }
            let disk = MameCatalogMachine.Disk(
                name: diskName,
                sha1: attributes["sha1"],
                merge: attributes["merge"],
                status: attributes["status"] ?? "good",
                optional: attributes.isYes("optional")
            )
            if seenDisks.insert(disk).inserted {
                machine?.disks.append(disk)
            }
        }
    }

    private func readRom(_ attributes: Attributes) {
        guard let name = attributes["name"], let size = attributes["size"].flatMap({ Int64($0) }) else {
            fail(MameListXMLParserError.malformed("rom without name/size at line \(lineNumber)"))
            return
        }
        var crc: UInt32?
        if let crcText = attributes["crc"] {
            guard let value = UInt32(crcText, radix: 16) else {
                fail(MameListXMLParserError.malformed("bad crc \(crcText) at line \(lineNumber)"))
                return
            }
            crc = value
        }
        let rom = MameCatalogMachine.Rom(
            name: name,
            size: size,
            crc: crc,
            sha1: attributes["sha1"],
            merge: attributes["merge"],
            bios: attributes["bios"],
            status: attributes["status"] ?? "good",
            optional: attributes.isYes("optional")
        )
        if seenRoms.insert(rom).inserted {
            machine?.roms.append(rom)
        }
    }

    // MARK: - libxml2 helpers

    private static func equals(_ name: UnsafePointer<xmlChar>, _ literal: StaticString) -> Bool {
        strcmp(UnsafeRawPointer(name).assumingMemoryBound(to: CChar.self),
               UnsafeRawPointer(literal.utf8Start).assumingMemoryBound(to: CChar.self)) == 0
    }

    /// SAX2 attributes: `count` quintuples of (localname, prefix, URI, valueStart, valueEnd).
    /// Values are not NUL-terminated.
    private struct Attributes {
        let count: Int
        let base: UnsafeMutablePointer<UnsafePointer<xmlChar>?>?

        subscript(name: StaticString) -> String? {
            guard let base else { return nil }
            for index in 0..<count {
                let attribute = base + index * 5
                guard let localName = attribute[0], MameListXMLParser.equals(localName, name),
                      let start = attribute[3], let end = attribute[4] else {
                    continue
                }
                return String(decoding: UnsafeBufferPointer(start: start, count: end - start), as: UTF8.self)
            }
            return nil
        }

        func isYes(_ name: StaticString) -> Bool {
            self[name] == "yes"
        }
    }
}
