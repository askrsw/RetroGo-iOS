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
import os

/// RetroGo's translations of the texts in Pugsy's MAME cheats: the on-demand resource
/// "mamecheat-i18n" (`text(en, lang, text)`, every language in one file), looked up by the
/// exact English text. Only the UI uses them; the engine and the index/description checks
/// always use the English original. Falls back to English while the resource is missing.
final class MameCheatTexts {
    static let shared = MameCheatTexts()

    private let lock = NSLock()
    private var db: Connection?
    private var cache: [String: String] = [:]
    private var loggedMissing = false

    private init() {
        NotificationCenter.default.addObserver(forName: .odrResourceStateDidChange, object: nil, queue: nil) { [weak self] note in
            guard (note.object as? String) == Self.resourceId, let self else { return }
            self.lock.lock()
            self.db = nil
            self.cache = [:]
            self.lock.unlock()
        }
    }

    private static let resourceId = "mamecheat-i18n"

    /// The text in the app language when translated, otherwise `english`.
    func localized(_ english: String) -> String {
        let lang = Bundle.currentSimpleLanguageKey()
        guard !english.isEmpty, lang != "en" else { return english }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[english] { return hit }
        guard let db = openIfNeeded() else { return english }
        let text = ((try? db.scalar("SELECT text FROM text WHERE en = ? AND lang = ?", english, lang)) as? String) ?? english
        cache[english] = text
        return text
    }

    private func openIfNeeded() -> Connection? {
        if let db { return db }
        guard let resource = OnDemandResourceLoader.resource(id: Self.resourceId) else { return nil }
        let path = OnDemandResourceLoader.shared.targetPath(resource)
        guard FileManager.default.fileExists(atPath: path), let db = try? Connection(path, readonly: true) else {
            if !loggedMissing {
                loggedMissing = true
                RetroGoLogger.mame.info("Cheat translations not installed yet (\(path))")
            }
            return nil
        }
        let count = (try? db.scalar("SELECT count(*) FROM text")) as? Int64 ?? 0
        RetroGoLogger.mame.info("Cheat translations opened: \(count) texts, app language \(Bundle.currentSimpleLanguageKey(), privacy: .public)")
        self.db = db
        return db
    }
}
