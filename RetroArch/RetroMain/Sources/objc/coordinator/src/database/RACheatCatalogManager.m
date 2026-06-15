//
//  RACheatCatalogManager.m
//  RetroMain
//
//  Created by haharsw on 2026/6/11.
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

#import "RACheatCatalogManager.h"
#import <Foundation+Extensions.h>

#include <sqlite3.h>

static NSString * const kRACheatErrorDomain = @"com.retrogame.cheatcatalog";

static NSString * _Nullable p_colText(sqlite3_stmt *stmt, int col);
static NSString *p_groupNameFromGameName(NSString *name);
static NSString *p_cheatDescriptionLanguage(void);
static NSArray<NSString *> *p_regionPreferences(NSString *name);
static BOOL p_nameContainsRegion(NSString *name, NSString *region);
static BOOL p_isSpecialTemplateName(NSString *name);

@interface RAGameEntry(RACheatCatalogPrivate)
@property (nonatomic, assign, readwrite) NSInteger gameId;
@property (nonatomic, assign, readwrite) NSInteger platformId;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, nullable, readwrite) NSString *groupName;
@property (nonatomic, copy, nullable, readwrite) NSString *localizedName;
@property (nonatomic, assign, readwrite) NSInteger localizationSource;
@property (nonatomic, assign, readwrite, getter=isLocalizationReference) BOOL localizationReference;
@property (nonatomic, assign, readwrite) NSInteger cheatCount;
@end

@interface RACheatCatalogManager()
@property (nonatomic, assign, readwrite) NSInteger currentDBUserVersion;
@property (nonatomic, assign, readwrite, getter=isDatabaseReady) BOOL databaseReady;
@end

@implementation RACheatCatalogManager
{
    NSString *d_cheatPath;
    NSString *d_localizationPath;
    sqlite3 *d_db;
    BOOL d_hasLocalization;
    dispatch_queue_t d_dbQueue;
}

+ (instancetype)shared {
    static RACheatCatalogManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        d_dbQueue = dispatch_queue_create("com.retrogame.cheatcatalog", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)initializeWithCheatPath:(NSString *)cheatPath
               localizationPath:(nullable NSString *)localizationPath
                     completion:(nullable void (^)(void))completion {
    NSString *nextCheatPath = [cheatPath copy];
    NSString *nextLocalizationPath = [localizationPath copy];
    dispatch_async(d_dbQueue, ^{
        BOOL samePath = d_db &&
            ((d_cheatPath == nextCheatPath) || [d_cheatPath isEqualToString:nextCheatPath]) &&
            ((d_localizationPath == nextLocalizationPath) ||
             (!d_localizationPath.length && !nextLocalizationPath.length) ||
             [d_localizationPath isEqualToString:nextLocalizationPath]);
        if (!samePath) {
            d_cheatPath = nextCheatPath;
            d_localizationPath = nextLocalizationPath;
            [self p_open];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

- (void)dealloc {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
}

- (void)fetchGamesForPlatformId:(NSInteger)platformId
                          offset:(NSInteger)offset
                           limit:(NSInteger)limit
                 knownTotalCount:(NSInteger)knownTotalCount
                      completion:(void (^)(NSArray<RAGameEntry *> *games,
                                           NSInteger totalCount,
                                           NSError * _Nullable error))completion {
    [self fetchGamesForPlatformIds:@[@(platformId)]
                            keyword:@""
                             offset:offset
                              limit:limit
                    knownTotalCount:knownTotalCount
                         completion:completion];
}

- (void)fetchGamesForPlatformIds:(NSArray<NSNumber *> *)platformIds
                          keyword:(NSString *)keyword
                           offset:(NSInteger)offset
                            limit:(NSInteger)limit
                  knownTotalCount:(NSInteger)knownTotalCount
                       completion:(void (^)(NSArray<RAGameEntry *> *games,
                                            NSInteger totalCount,
                                            NSError * _Nullable error))completion {
    if (platformIds.count == 0) {
        completion(@[], 0, nil);
        return;
    }
    NSArray<NSNumber *> *ids = [platformIds copy];
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSInteger totalCount = knownTotalCount;
        NSMutableString *placeholders = [NSMutableString string];
        for (NSUInteger i = 0; i < ids.count; i++) {
            if (i > 0) { [placeholders appendString:@","]; }
            [placeholders appendString:@"?"];
        }

        BOOL hasKeyword = trimmed.length > 0;
        NSString *wherePlain = [NSString stringWithFormat:@"g.platform_id IN (%@)", placeholders];
        NSString *whereLoc = wherePlain;
        if (hasKeyword) {
            wherePlain = [wherePlain stringByAppendingString:
                          @" AND (g.game_name LIKE ? COLLATE NOCASE OR g.group_name LIKE ? COLLATE NOCASE)"];
            whereLoc = [whereLoc stringByAppendingString:
                        @" AND (g.game_name LIKE ? COLLATE NOCASE OR g.group_name LIKE ? COLLATE NOCASE OR l.name LIKE ?)"];
        }

        if (totalCount <= 0) {
            NSString *countPlain = [NSString stringWithFormat:
                @"SELECT COUNT(*) FROM ("
                @"  SELECT 1 FROM game g "
                @"  WHERE %@ "
                @"  GROUP BY g.id"
                @");", wherePlain];
            NSString *countLoc = [NSString stringWithFormat:
                @"SELECT COUNT(*) FROM ("
                @"  SELECT 1 FROM game g "
                @"  LEFT JOIN loc.name_loc l ON l.platform_id = g.platform_id "
                @"                         AND l.group_name = g.group_name "
                @"                         AND l.lang = 'zh' AND l.is_primary = 1 "
                @"  WHERE %@ "
                @"  GROUP BY g.id"
                @");", whereLoc];
            sqlite3_stmt *stmt = NULL;
            const char *countSQL = (d_hasLocalization ? countLoc : countPlain).UTF8String;
            if (d_db && sqlite3_prepare_v2(d_db, countSQL, -1, &stmt, NULL) == SQLITE_OK) {
                int bind = 1;
                for (NSNumber *pid in ids) {
                    sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)pid.integerValue);
                }
                if (hasKeyword) {
                    NSString *like = [NSString stringWithFormat:@"%%%@%%", trimmed];
                    sqlite3_bind_text(stmt, bind++, like.UTF8String, -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(stmt, bind++, like.UTF8String, -1, SQLITE_TRANSIENT);
                    if (d_hasLocalization) {
                        sqlite3_bind_text(stmt, bind++, like.UTF8String, -1, SQLITE_TRANSIENT);
                    }
                }
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    totalCount = (NSInteger)sqlite3_column_int64(stmt, 0);
                }
            } else {
                error = [self p_error:@"cheat game count prepare failed"];
            }
            sqlite3_finalize(stmt);
        }

        NSMutableArray<RAGameEntry *> *games = [NSMutableArray array];
        if (!error) {
            NSString *sqlPlain = [NSString stringWithFormat:
                @"SELECT g.id, g.platform_id, g.platform, g.game_name, g.group_name, "
                @"       NULL AS loc_name, 0 AS loc_source, COUNT(ch.id) AS cheat_count "
                @"FROM game g "
                @"JOIN cheat ch ON ch.game_id = g.id "
                @"WHERE %@ "
                @"GROUP BY g.id "
                @"ORDER BY g.platform_id ASC, g.group_name COLLATE NOCASE ASC, g.game_name COLLATE NOCASE ASC "
                @"LIMIT ? OFFSET ?;", wherePlain];
            NSString *sqlLoc = [NSString stringWithFormat:
                @"SELECT g.id, g.platform_id, g.platform, g.game_name, g.group_name, "
                @"       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source, COUNT(ch.id) AS cheat_count "
                @"FROM game g "
                @"JOIN cheat ch ON ch.game_id = g.id "
                @"LEFT JOIN loc.name_loc l ON l.platform_id = g.platform_id "
                @"                         AND l.group_name = g.group_name "
                @"                         AND l.lang = 'zh' AND l.is_primary = 1 "
                @"WHERE %@ "
                @"GROUP BY g.id "
                @"ORDER BY g.platform_id ASC, g.group_name COLLATE NOCASE ASC, g.game_name COLLATE NOCASE ASC "
                @"LIMIT ? OFFSET ?;", whereLoc];
            sqlite3_stmt *stmt = NULL;
            const char *sql = (d_hasLocalization ? sqlLoc : sqlPlain).UTF8String;
            if (d_db && sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                int bind = 1;
                for (NSNumber *pid in ids) {
                    sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)pid.integerValue);
                }
                if (hasKeyword) {
                    NSString *like = [NSString stringWithFormat:@"%%%@%%", trimmed];
                    sqlite3_bind_text(stmt, bind++, like.UTF8String, -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(stmt, bind++, like.UTF8String, -1, SQLITE_TRANSIENT);
                    if (d_hasLocalization) {
                        sqlite3_bind_text(stmt, bind++, like.UTF8String, -1, SQLITE_TRANSIENT);
                    }
                }
                sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)limit);
                sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)offset);
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    [games addObject:[self p_gameFromStmt:stmt]];
                }
            } else {
                error = [self p_error:@"cheat game page prepare failed"];
            }
            sqlite3_finalize(stmt);
        }

        NSArray *copy = [games copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, totalCount, error);
        });
    });
}

- (void)fetchCheatsForPlatformId:(NSInteger)platformId
                       groupName:(NSString *)groupName
                      completion:(void (^)(NSArray<RACheatItem *> *cheats,
                                           NSError * _Nullable error))completion {
    if (groupName.length == 0) {
        completion(@[], nil);
        return;
    }
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSMutableArray<RACheatItem *> *cheats = [NSMutableArray array];
        NSString *descriptionLanguage = p_cheatDescriptionLanguage();
        const char *sql =
            "SELECT ch.id, ch.game_id, ch.cheat_index, COALESCE(ch.desc_id, 0), "
            "       ds.text AS desc_en, COALESCE(di.text, ds.text) AS desc_show, COALESCE(di.source, 0), "
            "       ch.code, ch.handler, ch.enable, ch.memory_search_size, ch.cheat_type, "
            "       ch.value, ch.address, ch.address_mask, ch.big_endian, "
            "       ch.repeat_count, ch.repeat_add_to_value, ch.repeat_add_to_address, "
            "       ch.rumble_type, ch.rumble_value, ch.rumble_port, "
            "       ch.rumble_primary_strength, ch.rumble_primary_duration, "
            "       ch.rumble_secondary_strength, ch.rumble_secondary_duration "
            "FROM cheat ch "
            "JOIN game g ON g.id = ch.game_id "
            "LEFT JOIN desc_string ds ON ds.id = ch.desc_id "
            "LEFT JOIN desc_i18n di ON di.desc_id = ch.desc_id AND di.lang = ? "
            "WHERE g.platform_id = ? AND g.group_name = ? "
            "ORDER BY ch.cheat_index ASC;";
        sqlite3_stmt *stmt = NULL;
        if (d_db && sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, descriptionLanguage.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, (sqlite3_int64)platformId);
            sqlite3_bind_text(stmt, 3, groupName.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                [cheats addObject:[self p_cheatFromStmt:stmt]];
            }
        } else {
            error = [self p_error:@"fetch cheats prepare failed"];
        }
        sqlite3_finalize(stmt);

        NSArray *copy = [cheats copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, error);
        });
    });
}

- (void)fetchCheatsForGameId:(NSInteger)gameId
                  completion:(void (^)(NSArray<RACheatItem *> *cheats,
                                       NSError * _Nullable error))completion {
    if (gameId <= 0) {
        completion(@[], nil);
        return;
    }
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSMutableArray<RACheatItem *> *cheats = [NSMutableArray array];
        NSString *descriptionLanguage = p_cheatDescriptionLanguage();
        const char *sql =
            "SELECT ch.id, ch.game_id, ch.cheat_index, COALESCE(ch.desc_id, 0), "
            "       ds.text AS desc_en, COALESCE(di.text, ds.text) AS desc_show, COALESCE(di.source, 0), "
            "       ch.code, ch.handler, ch.enable, ch.memory_search_size, ch.cheat_type, "
            "       ch.value, ch.address, ch.address_mask, ch.big_endian, "
            "       ch.repeat_count, ch.repeat_add_to_value, ch.repeat_add_to_address, "
            "       ch.rumble_type, ch.rumble_value, ch.rumble_port, "
            "       ch.rumble_primary_strength, ch.rumble_primary_duration, "
            "       ch.rumble_secondary_strength, ch.rumble_secondary_duration "
            "FROM cheat ch "
            "LEFT JOIN desc_string ds ON ds.id = ch.desc_id "
            "LEFT JOIN desc_i18n di ON di.desc_id = ch.desc_id AND di.lang = ? "
            "WHERE ch.game_id = ? "
            "ORDER BY ch.cheat_index ASC;";
        sqlite3_stmt *stmt = NULL;
        if (d_db && sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, descriptionLanguage.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(stmt, 2, (sqlite3_int64)gameId);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                [cheats addObject:[self p_cheatFromStmt:stmt]];
            }
        } else {
            error = [self p_error:@"fetch cheats by game id prepare failed"];
        }
        sqlite3_finalize(stmt);

        NSArray *copy = [cheats copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, error);
        });
    });
}

- (nullable RAGameEntry *)findGameForPlatformIds:(NSArray<NSNumber *> *)platformIds
                                     englishName:(NSString *)englishName {
    if (platformIds.count == 0 || englishName.length == 0) {
        return nil;
    }

    NSArray<NSNumber *> *ids = [platformIds copy];
    NSString *name = [englishName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (name.length == 0) {
        return nil;
    }

    __block RAGameEntry *result = nil;
    dispatch_sync(d_dbQueue, ^{
        if (!d_db) {
            return;
        }

        NSMutableString *placeholders = [NSMutableString string];
        for (NSUInteger i = 0; i < ids.count; i++) {
            if (i > 0) { [placeholders appendString:@","]; }
            [placeholders appendString:@"?"];
        }

        NSString *exactSQL = [NSString stringWithFormat:
            @"SELECT g.id, g.platform_id, g.platform, g.game_name, g.group_name, "
            @"       NULL AS loc_name, 0 AS loc_source, COUNT(ch.id) AS cheat_count "
            @"FROM game g "
            @"JOIN cheat ch ON ch.game_id = g.id "
            @"WHERE g.platform_id IN (%@) "
            @"  AND g.game_name = ? COLLATE NOCASE "
            @"GROUP BY g.id "
            @"ORDER BY g.platform_id ASC, g.game_name COLLATE NOCASE ASC "
            @"LIMIT 2;", placeholders];

        sqlite3_stmt *stmt = NULL;
        NSMutableArray<RAGameEntry *> *matches = [NSMutableArray arrayWithCapacity:2];
        if (sqlite3_prepare_v2(d_db, exactSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
            int bind = 1;
            for (NSNumber *pid in ids) {
                sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)pid.integerValue);
            }
            sqlite3_bind_text(stmt, bind++, name.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW && matches.count < 2) {
                [matches addObject:[self p_gameFromStmt:stmt]];
            }
        }
        sqlite3_finalize(stmt);
        if (matches.count == 1) {
            result = matches.firstObject;
            return;
        }

        NSString *groupName = p_groupNameFromGameName(name);
        if (groupName.length == 0) {
            return;
        }

        NSString *groupSQL = [NSString stringWithFormat:
            @"SELECT g.id, g.platform_id, g.platform, g.game_name, g.group_name, "
            @"       NULL AS loc_name, 0 AS loc_source, COUNT(ch.id) AS cheat_count "
            @"FROM game g "
            @"JOIN cheat ch ON ch.game_id = g.id "
            @"WHERE g.platform_id IN (%@) "
            @"  AND g.group_name = ? COLLATE NOCASE "
            @"GROUP BY g.id "
            @"ORDER BY g.platform_id ASC, g.game_name COLLATE NOCASE ASC "
            @"LIMIT 20;", placeholders];

        [matches removeAllObjects];
        if (sqlite3_prepare_v2(d_db, groupSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
            int bind = 1;
            for (NSNumber *pid in ids) {
                sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)pid.integerValue);
            }
            sqlite3_bind_text(stmt, bind++, groupName.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                RAGameEntry *candidate = [self p_gameFromStmt:stmt];
                if (!p_isSpecialTemplateName(name) && p_isSpecialTemplateName(candidate.name)) {
                    continue;
                }
                [matches addObject:candidate];
            }
        }
        sqlite3_finalize(stmt);

        if (matches.count == 1) {
            result = matches.firstObject;
            return;
        }

        // Region-aware fallback keeps auto-bind useful without returning a whole
        // group: USA may map to a World template, Europe maps to Europe, etc. If
        // a preference still has multiple candidates, leave it to manual search.
        for (NSString *region in p_regionPreferences(name)) {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(RAGameEntry *candidate, NSDictionary *bindings) {
                return p_nameContainsRegion(candidate.name, region);
            }];
            NSArray<RAGameEntry *> *regionMatches = [matches filteredArrayUsingPredicate:predicate];
            if (regionMatches.count == 1) {
                result = regionMatches.firstObject;
                return;
            }
        }
    });
    return result;
}

- (nullable RAGameEntry *)findGameForPlatformId:(NSInteger)platformId
                                      groupName:(NSString *)groupName {
    if (platformId <= 0 || groupName.length == 0) {
        return nil;
    }

    NSString *name = [groupName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (name.length == 0) {
        return nil;
    }

    __block RAGameEntry *result = nil;
    dispatch_sync(d_dbQueue, ^{
        if (!d_db) {
            return;
        }

        const char *sql =
            "SELECT g.id, g.platform_id, g.platform, g.game_name, g.group_name, "
            "       NULL AS loc_name, 0 AS loc_source, COUNT(ch.id) AS cheat_count "
            "FROM game g "
            "JOIN cheat ch ON ch.game_id = g.id "
            "WHERE g.platform_id = ? AND g.group_name = ? "
            "GROUP BY g.id "
            "ORDER BY g.game_name COLLATE NOCASE ASC "
            "LIMIT 2;";
        sqlite3_stmt *stmt = NULL;
        NSMutableArray<RAGameEntry *> *matches = [NSMutableArray arrayWithCapacity:2];
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
            sqlite3_bind_text(stmt, 2, name.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW && matches.count < 2) {
                [matches addObject:[self p_gameFromStmt:stmt]];
            }
        }
        sqlite3_finalize(stmt);
        if (matches.count == 1) {
            result = matches.firstObject;
        }
    });
    return result;
}

- (nullable RAGameEntry *)findGameForGameId:(NSInteger)gameId {
    if (gameId <= 0) {
        return nil;
    }

    __block RAGameEntry *result = nil;
    dispatch_sync(d_dbQueue, ^{
        if (!d_db) {
            return;
        }

        const char *sql =
            "SELECT g.id, g.platform_id, g.platform, g.game_name, g.group_name, "
            "       NULL AS loc_name, 0 AS loc_source, COUNT(ch.id) AS cheat_count "
            "FROM game g "
            "JOIN cheat ch ON ch.game_id = g.id "
            "WHERE g.id = ? "
            "GROUP BY g.id "
            "LIMIT 1;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (sqlite3_int64)gameId);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                result = [self p_gameFromStmt:stmt];
            }
        }
        sqlite3_finalize(stmt);
    });
    return result;
}

- (BOOL)p_open {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
    d_hasLocalization = NO;
    self.currentDBUserVersion = 0;
    self.databaseReady = NO;
    NSString *uri = [[[NSURL fileURLWithPath:d_cheatPath] absoluteString]
                     stringByAppendingString:@"?immutable=1"];
    int rc = sqlite3_open_v2(uri.UTF8String, &d_db,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL);
    if (rc != SQLITE_OK) {
        NSLog(@"[RACheatCatalogManager] SQLite open failed(%d): %@", rc, d_cheatPath);
        if (d_db) {
            sqlite3_close(d_db);
            d_db = NULL;
        }
        return NO;
    }
    self.databaseReady = YES;
    // Each manager owns its SQLite connection. gameloc.sqlite is attached here
    // as read-only lookup data instead of sharing RAGameRDBManager's handle.
    if (d_localizationPath.length > 0 &&
        [NSFileManager.defaultManager fileExistsAtPath:d_localizationPath]) {
        NSString *escaped = [d_localizationPath stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
        NSString *sql = [NSString stringWithFormat:@"ATTACH DATABASE '%@' AS loc;", escaped];
        if (sqlite3_exec(d_db, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK) {
            d_hasLocalization = YES;
        } else {
            NSLog(@"[RACheatCatalogManager] attach gameloc failed: %@", d_localizationPath);
        }
    }
    sqlite3_stmt *versionStmt = NULL;
    if (sqlite3_prepare_v2(d_db, "PRAGMA user_version;", -1, &versionStmt, NULL) == SQLITE_OK &&
        sqlite3_step(versionStmt) == SQLITE_ROW) {
        self.currentDBUserVersion = (NSInteger)sqlite3_column_int64(versionStmt, 0);
    }
    sqlite3_finalize(versionStmt);
    return YES;
}

- (RAGameEntry *)p_gameFromStmt:(sqlite3_stmt *)stmt {
    RAGameEntry *game = [[RAGameEntry alloc] init];
    game.gameId = (NSInteger)sqlite3_column_int64(stmt, 0);
    game.platformId = (NSInteger)sqlite3_column_int64(stmt, 1);
    NSString *groupName = p_colText(stmt, 4);
    NSString *gameName = p_colText(stmt, 3);
    game.name = gameName ?: (groupName ?: @"");
    game.groupName = groupName;
    game.localizedName = p_colText(stmt, 5);
    game.localizationSource = (NSInteger)sqlite3_column_int64(stmt, 6);
    game.localizationReference = game.localizationSource == 5;
    game.cheatCount = (NSInteger)sqlite3_column_int64(stmt, 7);
    return game;
}

- (RACheatItem *)p_cheatFromStmt:(sqlite3_stmt *)stmt {
    RACheatItem *item = [[RACheatItem alloc] init];
    item.catalogId = (NSInteger)sqlite3_column_int64(stmt, 0);
    item.catalogGameId = (NSInteger)sqlite3_column_int64(stmt, 1);
    item.catalogIndex = (NSInteger)sqlite3_column_int64(stmt, 2);
    item.catalogDescId = (NSInteger)sqlite3_column_int64(stmt, 3);
    item.descEnglish = p_colText(stmt, 4);
    // RACheatItem.desc is the UI/apply-facing text. Non-zh languages bind a
    // missing i18n language and naturally fall back to descEnglish.
    item.desc = p_colText(stmt, 5) ?: @"";
    item.descSource = (NSInteger)sqlite3_column_int64(stmt, 6);
    item.code = p_colText(stmt, 7) ?: @"";
    item.handler = (RACheatHandler)sqlite3_column_int64(stmt, 8);
    item.enabled = sqlite3_column_int64(stmt, 9) != 0;
    item.memorySearchSize = (NSInteger)sqlite3_column_int64(stmt, 10);
    item.cheatType = (NSInteger)sqlite3_column_int64(stmt, 11);
    item.value = (NSInteger)sqlite3_column_int64(stmt, 12);
    item.address = (NSInteger)sqlite3_column_int64(stmt, 13);
    item.addressMask = (NSInteger)sqlite3_column_int64(stmt, 14);
    item.bigEndian = (NSInteger)sqlite3_column_int64(stmt, 15);
    item.repeatCount = (NSInteger)sqlite3_column_int64(stmt, 16);
    item.repeatAddToValue = (NSInteger)sqlite3_column_int64(stmt, 17);
    item.repeatAddToAddress = (NSInteger)sqlite3_column_int64(stmt, 18);
    item.rumbleType = (NSInteger)sqlite3_column_int64(stmt, 19);
    item.rumbleValue = (NSInteger)sqlite3_column_int64(stmt, 20);
    item.rumblePort = (NSInteger)sqlite3_column_int64(stmt, 21);
    item.rumblePrimaryStrength = (NSInteger)sqlite3_column_int64(stmt, 22);
    item.rumblePrimaryDuration = (NSInteger)sqlite3_column_int64(stmt, 23);
    item.rumbleSecondaryStrength = (NSInteger)sqlite3_column_int64(stmt, 24);
    item.rumbleSecondaryDuration = (NSInteger)sqlite3_column_int64(stmt, 25);
    return item;
}

- (NSError *)p_error:(NSString *)reason {
    return [NSError errorWithDomain:kRACheatErrorDomain
                               code:1001
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

static NSString * _Nullable p_colText(sqlite3_stmt *stmt, int col) {
    const unsigned char *text = sqlite3_column_text(stmt, col);
    return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

static NSString *p_groupNameFromGameName(NSString *name) {
    if (name.length == 0) {
        return @"";
    }
    NSRange range = [name rangeOfCharacterFromSet:
                     [NSCharacterSet characterSetWithCharactersInString:@"(["]];
    NSString *base = range.location != NSNotFound ? [name substringToIndex:range.location] : name;
    base = [base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return base.length > 0 ? base : name;
}

static NSString *p_cheatDescriptionLanguage(void) {
    NSString *key = [NSBundle currentSimpleLanguageKey];
    return [key isEqualToString:@"zh"] ? @"zh" : @"en";
}

static NSArray<NSString *> *p_regionPreferences(NSString *name) {
    NSString *lower = name.lowercaseString ?: @"";
    NSMutableArray<NSString *> *regions = [NSMutableArray arrayWithCapacity:3];
    void (^add)(NSString *) = ^(NSString *region) {
        if (![regions containsObject:region]) {
            [regions addObject:region];
        }
    };

    BOOL hasUSA = [lower containsString:@"usa"] || [lower containsString:@"u)"] || [lower containsString:@"u]"];
    BOOL hasEurope = [lower containsString:@"europe"] || [lower containsString:@"e)"] || [lower containsString:@"e]"];
    BOOL hasWorld = [lower containsString:@"world"] || [lower containsString:@"w)"] || [lower containsString:@"w]"];

    if (hasUSA && hasEurope) {
        add(@"world");
        add(@"usa");
        add(@"europe");
    } else if (hasUSA) {
        add(@"usa");
        add(@"world");
    } else if (hasEurope) {
        add(@"europe");
        add(@"world");
    } else if (hasWorld) {
        add(@"world");
        add(@"usa");
        add(@"europe");
    }

    if ([lower containsString:@"japan"] || [lower containsString:@"j)"] || [lower containsString:@"j]"]) {
        add(@"japan");
    }
    if ([lower containsString:@"korea"]) {
        add(@"korea");
    }
    if ([lower containsString:@"asia"]) {
        add(@"asia");
        add(@"world");
    }
    return regions;
}

static BOOL p_nameContainsRegion(NSString *name, NSString *region) {
    NSString *lowerName = name.lowercaseString ?: @"";
    NSString *lowerRegion = region.lowercaseString ?: @"";
    if (lowerRegion.length == 0) {
        return NO;
    }
    return [lowerName containsString:[NSString stringWithFormat:@"(%@", lowerRegion]] ||
           [lowerName containsString:[NSString stringWithFormat:@"[%@", lowerRegion]] ||
           [lowerName containsString:[NSString stringWithFormat:@", %@", lowerRegion]] ||
           [lowerName containsString:[NSString stringWithFormat:@" %@", lowerRegion]];
}

static BOOL p_isSpecialTemplateName(NSString *name) {
    NSString *lower = name.lowercaseString ?: @"";
    return [lower containsString:@"game genie"] ||
           [lower containsString:@"action replay"] ||
           [lower containsString:@"code breaker"] ||
           [lower containsString:@"xploder"] ||
           [lower containsString:@"rumbles"];
}

@end
