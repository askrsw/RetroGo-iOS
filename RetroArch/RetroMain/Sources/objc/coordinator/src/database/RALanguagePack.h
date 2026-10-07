//
//  RALanguagePack.h
//  RetroGo
//
//  Created by haharsw on 2026/10/7.
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

#import <Foundation/Foundation.h>
#include <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

/// Schema (PRAGMA user_version) of the language pack files this code reads.
/// A pack holds game_name, cheat_desc and mame_cheat_text; later translations
/// arrive as new tables, so the version only changes if an existing table does.
extern const int RALanguagePackSchemaVersion;

/// BCP-47 language of the pack attached to `db` under `schemaName`, or nil
/// (logged) when it is not a language pack of RALanguagePackSchemaVersion.
NSString * _Nullable RALanguagePackLanguage(sqlite3 *db, const char *schemaName);

/// Search form of a name: lowercased, keeping only code points of Unicode
/// categories L, M and N. Same rule as name_norm in build_langpack.py.
NSString *RALanguagePackSearchNorm(NSString *text);

NS_ASSUME_NONNULL_END
