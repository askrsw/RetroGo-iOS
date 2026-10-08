//
//  MameCheatTexts.swift
//  RetroGo
//
//  Created by haharsw on 2026/9/28.
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

import SQLite
import Foundation
import ObjcHelper
import RACoordinator
import os

/// RetroGo's translations of the texts in Pugsy's MAME cheats: the mame_cheat_text table of
/// the language pack of the App language, keyed by RATextKey of the exact English text. Only
/// the UI uses them; the engine and the index/description checks always use the English
/// original. The user's cheat XML may be newer than the pack, and the App language may have
/// no pack at all: untranslated texts stay English.
final class MameCheatTexts {
    static let shared = MameCheatTexts()

    private let lock = NSLock()
    private var db: Connection?
    private var dbPath: String?
    private var cache: [String: String] = [:]

    private init() {
        NotificationCenter.default.addObserver(forName: .activeLanguagePackDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.db = nil
            self.dbPath = nil
            self.cache = [:]
            self.lock.unlock()
        }
    }

    /// The text in the app language when translated, otherwise `english`.
    func localized(_ english: String) -> String {
        guard !english.isEmpty, let packPath = OnDemandResourceLoader.shared.activeLanguagePackPath else { return english }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[english] { return hit }
        guard let db = openIfNeeded(packPath) else { return english }
        let key = RATextKey.key(for: english)
        let text = ((try? db.scalar("SELECT text FROM mame_cheat_text WHERE text_key = ?", key)) as? String) ?? english
        cache[english] = text
        return text
    }

    private func openIfNeeded(_ path: String) -> Connection? {
        if let db, dbPath == path { return db }
        db = nil
        cache = [:]
        guard let opened = try? Connection(path, readonly: true) else {
            RetroGoLogger.mame.error("Failed to open the language pack for cheat texts")
            return nil
        }
        let count = (try? opened.scalar("SELECT count(*) FROM mame_cheat_text")) as? Int64 ?? 0
        RetroGoLogger.mame.info("Cheat translations opened: \(count) texts, language \(OnDemandResourceLoader.shared.activeLanguage ?? "none", privacy: .public)")
        db = opened
        dbPath = path
        return opened
    }
}
