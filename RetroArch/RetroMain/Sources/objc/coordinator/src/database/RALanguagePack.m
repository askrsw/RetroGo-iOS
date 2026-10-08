//
//  RALanguagePack.m
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

#import "RALanguagePack.h"

#include <utils/retrogo_log.h>

const int RALanguagePackSchemaVersion = 1;

NSString * _Nullable RALanguagePackLanguage(sqlite3 *db, const char *schemaName) {
    NSString *language = nil;
    int schema = -1;
    sqlite3_stmt *stmt = NULL;
    NSString *versionSQL = [NSString stringWithFormat:@"PRAGMA %s.user_version;", schemaName];
    if (sqlite3_prepare_v2(db, versionSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK &&
        sqlite3_step(stmt) == SQLITE_ROW) {
        schema = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    if (schema != RALanguagePackSchemaVersion) {
        RETROGO_LOGN(DATABASE, "Ignoring language pack with schema %d (expected %d)", schema, RALanguagePackSchemaVersion);
        return nil;
    }
    stmt = NULL;
    NSString *langSQL = [NSString stringWithFormat:@"SELECT value FROM %s.meta WHERE key = 'lang';", schemaName];
    if (sqlite3_prepare_v2(db, langSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK &&
        sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *text = sqlite3_column_text(stmt, 0);
        if (text) {
            language = [NSString stringWithUTF8String:(const char *)text];
        }
    }
    sqlite3_finalize(stmt);
    if (language.length == 0) {
        RETROGO_LOGN(DATABASE, "Ignoring language pack without a language in meta");
        return nil;
    }
    return language;
}

NSString *RALanguagePackSearchNorm(NSString *text) {
    static NSCharacterSet *keep = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // L* + M* + N*, the same categories build_langpack.py keeps.
        keep = NSCharacterSet.alphanumericCharacterSet;
    });
    NSString *lower = text.lowercaseString ?: @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    NSUInteger length = lower.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [lower characterAtIndex:i];
        UTF32Char codePoint = c;
        NSUInteger units = 1;
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < length) {
            unichar low = [lower characterAtIndex:i + 1];
            if (CFStringIsSurrogateLowCharacter(low)) {
                codePoint = CFStringGetLongCharacterForSurrogatePair(c, low);
                units = 2;
            }
        }
        if ([keep longCharacterIsMember:codePoint]) {
            [out appendString:[lower substringWithRange:NSMakeRange(i, units)]];
        }
        i += units - 1;
    }
    return out;
}
