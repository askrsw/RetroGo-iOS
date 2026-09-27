//
//  MameCheatDefinition.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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

/// One `<cheat>` of a MAME cheat XML, as the list shows it. MAME's engine runs the XML
/// itself; this only carries what the UI needs, in engine order (MAME keeps duplicates).
struct MameCheatDefinition {
    enum Parameter {
        /// `<parameter><item value="…">text</item>…</parameter>`
        case items([String])
        /// `<parameter min="…" max="…" step="…"/>`
        case range(min: UInt64, max: UInt64, step: UInt64)

        var count: Int {
            switch self {
            case .items(let items):
                return items.count
            case .range(let min, let max, let step):
                guard max >= min, step > 0 else { return 1 }
                return Int(Swift.min(UInt64(Int.max), (max - min) / step + 1))
            }
        }

        /// Text for a 0-based position; ranges show the value MAME uses.
        func title(at position: Int) -> String {
            switch self {
            case .items(let items):
                return items.indices.contains(position) ? items[position] : "\(position)"
            case .range(let min, let max, let step):
                let value = Swift.min(max, min + step * UInt64(Swift.max(0, position)))
                return "\(value)"
            }
        }
    }

    let index: Int
    let kind: RAMameCheatKind
    let desc: String
    let comment: String?
    let parameter: Parameter?

    /// Separator rows (" ") and empty descriptions carry no text.
    var hasText: Bool { !desc.isEmpty }

    /// Parses a cheat XML. Returns nil when it is not a `<mamecheat>` document.
    static func parse(_ data: Data) -> [MameCheatDefinition]? {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.isMameCheat else {
            NSLog("[MameCheat] Failed to parse cheat XML: %@", parser.parserError.map { "\($0)" } ?? "not <mamecheat>")
            return nil
        }
        return delegate.definitions
    }

    /// MAME accepts decimal, `$hex` and `0xhex`.
    fileprivate static func parseNumber(_ text: String?) -> UInt64? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("$") { return UInt64(text.dropFirst(), radix: 16) }
        if text.lowercased().hasPrefix("0x") { return UInt64(text.dropFirst(2), radix: 16) }
        return UInt64(text)
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    private struct Pending {
        var desc = ""
        var comment: String?
        var hasParameter = false
        var range: (min: UInt64, max: UInt64, step: UInt64)?
        var items: [String] = []
        var states: Set<String> = []
    }

    private(set) var definitions: [MameCheatDefinition] = []
    private(set) var isMameCheat = false
    private var pending: Pending?
    private var text = ""
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        text = ""
        switch elementName {
        case "mamecheat" where depth == 1:
            isMameCheat = true
        case "cheat" where depth == 2:
            pending = Pending(desc: (attributes["desc"] ?? "").trimmingCharacters(in: .whitespaces))
        case "parameter":
            pending?.hasParameter = true
            if let min = MameCheatDefinition.parseNumber(attributes["min"]),
               let max = MameCheatDefinition.parseNumber(attributes["max"]) {
                pending?.range = (min, max, MameCheatDefinition.parseNumber(attributes["step"]) ?? 1)
            }
        case "script":
            pending?.states.insert(attributes["state"] ?? "run")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        defer { depth -= 1 }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "item":
            pending?.items.append(trimmed)
        case "comment":
            if !trimmed.isEmpty { pending?.comment = trimmed }
        case "cheat" where depth == 2:
            if let pending { definitions.append(makeDefinition(pending)) }
            pending = nil
        default:
            break
        }
        text = ""
    }

    /// Mirrors cheat_entry::is_* in MAME's cheat.cpp.
    private func makeDefinition(_ cheat: Pending) -> MameCheatDefinition {
        let states = cheat.states
        let kind: RAMameCheatKind
        var parameter: MameCheatDefinition.Parameter?
        if cheat.hasParameter {
            if !cheat.items.isEmpty {
                parameter = .items(cheat.items)
            } else if let range = cheat.range {
                parameter = .range(min: range.min, max: range.max, step: range.step)
            }
            let oneShot = !states.contains("run") && !states.contains("off") && states.contains("change")
            kind = oneShot ? .oneShotParameter : .parameter
        } else if states.contains("run") || (states.contains("on") && states.contains("off")) {
            kind = .onOff
        } else if states.contains("on") {
            kind = .oneShot
        } else {
            kind = .text
        }
        return MameCheatDefinition(index: definitions.count, kind: kind, desc: cheat.desc,
                                   comment: cheat.comment, parameter: parameter)
    }
}
