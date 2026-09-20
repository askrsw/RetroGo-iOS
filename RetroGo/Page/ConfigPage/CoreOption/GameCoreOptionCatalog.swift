//
//  GameCoreOptionCatalog.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/19.
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
import ObjcHelper

struct GameCoreOptionCatalog: Decodable {
    let schemaVersion: Int
    /// Data version of the bundled catalog; raw exports are archived per version in Tools/option/raw.
    let version: Int?
    let coreId: String
    let format: String?
    let source: Source?
    let groups: [Group]

    struct Source: Decodable {
        let generator: String?
        let coreName: String?
        let coreVersion: String?
        let languages: [String]?
    }

    struct Group: Decodable {
        let id: String
        let title: [String: String]
        let description: [String: String]
        let options: [Option]
    }

    struct Option: Decodable {
        let key: String
        let title: [String: String]
        let description: [String: String]
        let categoryId: String?
        let type: String
        let defaultValue: String
        let restartRequired: Bool
        /// Unique values in core order. Runtime exports may repeat a value
        /// (e.g. one entry per network interface), so duplicates are dropped.
        let values: [String]
        /// Localized display label per value, keyed by value then language.
        let valueLabels: [String: [String: String]]
        /// Values that need a user-supplied file in the core's BIOS folder.
        let valueFiles: [String: ValueFile]
        /// Shown only when any alternative matches; each alternative requires every
        /// listed option to currently hold one of the given values. Empty = always visible.
        let visibleWhen: [[String: [String]]]

        private enum CodingKeys: String, CodingKey {
            case key, title, description, categoryId, type, defaultValue, restartRequired, values, valueLabels, valueFiles, visibleWhen
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            title = try c.decodeIfPresent([String: String].self, forKey: .title) ?? [:]
            description = try c.decodeIfPresent([String: String].self, forKey: .description) ?? [:]
            categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
            type = try c.decode(String.self, forKey: .type)
            defaultValue = try c.decode(String.self, forKey: .defaultValue)
            restartRequired = try c.decodeIfPresent(Bool.self, forKey: .restartRequired) ?? true
            var seen = Set<String>()
            values = try c.decode([String].self, forKey: .values).filter { seen.insert($0).inserted }
            valueLabels = try c.decodeIfPresent([String: [String: String]].self, forKey: .valueLabels) ?? [:]
            valueFiles = try c.decodeIfPresent([String: ValueFile].self, forKey: .valueFiles) ?? [:]
            visibleWhen = try c.decodeIfPresent([[String: [String]]].self, forKey: .visibleWhen) ?? []
        }

        struct ValueFile: Decodable {
            /// Name the imported file must take inside the core's BIOS folder.
            let fileName: String
            let extensions: [String]
            /// Whether the core may only pick the file up when a game loads. It depends
            /// on when the file was imported, so the hint says a restart *may* be needed.
            let restartRequired: Bool

            private enum CodingKeys: String, CodingKey { case fileName, extensions, restartRequired }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                fileName = try c.decode(String.self, forKey: .fileName)
                extensions = try c.decode([String].self, forKey: .extensions)
                restartRequired = try c.decodeIfPresent(Bool.self, forKey: .restartRequired) ?? false
            }
        }

        var isSwitch: Bool {
            type == "bool" && Set(values) == Set(["disabled", "enabled"])
        }

        func isVisible(_ value: (String) -> String?) -> Bool {
            visibleWhen.isEmpty || visibleWhen.contains { alternative in
                alternative.allSatisfy { key, values in value(key).map(values.contains) ?? false }
            }
        }

        func label(for value: String) -> String {
            GameCoreOptionCatalog.text(valueLabels[value] ?? [:], fallback: value)
        }
    }

    static func resourceURL(coreId: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: coreId + "_core_options", withExtension: "json", subdirectory: "Data/jsons/option")
    }

    static func load(coreId: String, bundle: Bundle = .main) throws -> GameCoreOptionCatalog {
        guard let url = resourceURL(coreId: coreId, bundle: bundle) else {
            throw CatalogError.invalidCatalog
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try catalog.validate(expectedCoreId: coreId)
        return catalog
    }

    func validate(expectedCoreId: String) throws {
        guard schemaVersion == 1, coreId == expectedCoreId,
              Set(groups.map(\.id)).count == groups.count else { throw CatalogError.invalidCatalog }
        var keys = Set<String>()
        for group in groups {
            for option in group.options {
                let values = option.values
                guard !option.key.isEmpty, keys.insert(option.key).inserted,
                      !values.isEmpty,
                      values.contains(option.defaultValue),
                      (option.categoryId ?? "general") == group.id else { throw CatalogError.invalidCatalog }
            }
        }
        for option in groups.flatMap(\.options) {
            guard Set(option.valueFiles.keys).isSubset(of: Set(option.values)),
                  option.valueFiles.values.allSatisfy({ !$0.fileName.isEmpty && !$0.extensions.isEmpty })
            else { throw CatalogError.invalidCatalog }
        }
        let options = Dictionary(uniqueKeysWithValues: groups.flatMap(\.options).map { ($0.key, $0) })
        for option in options.values {
            for alternative in option.visibleWhen {
                for (key, values) in alternative {
                    guard let target = options[key], key != option.key,
                          Set(values).isSubset(of: target.values) else { throw CatalogError.invalidCatalog }
                }
            }
        }
    }

    enum CatalogError: Error { case invalidCatalog }

    /// Localized text for the language the user picked inside the app, which is
    /// not necessarily the system language, so `preferredLocalizations` must not
    /// be used here. Catalog keys match the `.lproj` names (`en`, `zh-Hans`).
    static func text(_ translations: [String: String], fallback: String = "") -> String {
        let language = Bundle.currentLanguage()
        var candidates = [language]
        // `currentLanguage()` falls back to a bare language code when no bundle
        // was picked, e.g. `zh` for the `zh-Hans` catalogs.
        if language.hasPrefix("zh") { candidates.append("zh-Hans") }
        candidates.append(String(language.split(separator: "-").first ?? ""))

        for candidate in candidates {
            if let value = translations[candidate], !value.isEmpty { return value }
        }
        return translations["en"].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    }
}

struct GameCoreOptionOverrides: Codable {
    var version = 1
    var cores: [String: [String: String]] = [:]

    static func decode(_ data: Data?) throws -> Self {
        guard let data else { return Self() }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1 else { throw GameCoreOptionCatalog.CatalogError.invalidCatalog }
        return result
    }
}

final class GameCoreOptionSession {
    let catalog: GameCoreOptionCatalog
    private var selections: [String: String]
    private let inherited: [String: String]
    private let save: ([String: String]) throws -> Void
    var onSaveError: ((Error) -> Void)?
    /// Set only for the running game's own config session: pushes the resolved
    /// value of changed live options (restartRequired == false) to the core.
    var liveApply: ((_ key: String, _ value: String) -> Void)?

    init(catalog: GameCoreOptionCatalog, overrides: [String: String], inherited: [String: String],
         save: @escaping ([String: String]) throws -> Void) {
        self.catalog = catalog
        self.selections = overrides
        self.inherited = inherited
        self.save = save
    }

    func value(for option: GameCoreOptionCatalog.Option) -> String {
        for value in [selections[option.key], inherited[option.key]].compactMap({ $0 }) {
            if option.values.contains(where: { $0 == value }) { return value }
        }
        return option.defaultValue
    }

    func isOverridden(_ option: GameCoreOptionCatalog.Option) -> Bool {
        selections[option.key].map { value in option.values.contains { $0 == value } } ?? false
    }

    @discardableResult
    func select(_ value: String, for option: GameCoreOptionCatalog.Option) -> Bool {
        guard option.values.contains(where: { $0 == value }) else { return false }
        var updated = selections
        updated[option.key] = value
        return persist(updated, affected: [option])
    }

    @discardableResult
    func reset(_ options: [GameCoreOptionCatalog.Option]) -> Bool {
        var updated = selections
        for option in options { updated.removeValue(forKey: option.key) }
        return persist(updated, affected: options)
    }

    @discardableResult
    func resetAll() -> Bool { persist([:], affected: catalog.groups.flatMap(\.options)) }

    private func persist(_ updated: [String: String], affected: [GameCoreOptionCatalog.Option]) -> Bool {
        do {
            try save(updated)
            selections = updated
            if let liveApply {
                for option in affected where !option.restartRequired {
                    liveApply(option.key, value(for: option))
                }
            }
            return true
        } catch {
            onSaveError?(error)
            return false
        }
    }
}
