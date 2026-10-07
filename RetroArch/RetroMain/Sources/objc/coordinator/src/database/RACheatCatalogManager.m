//
//  RACheatCatalogManager.m
//  RetroGo
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
#import "RALanguagePack.h"

#include <sqlite3.h>
#include <utils/retrogo_log.h>

static NSString * const kRACheatErrorDomain = @"com.retrogame.cheatcatalog";

/// Schema (PRAGMA user_version) of the cheat.sqlite files this code reads.
/// v5: English only, game.first_cheat_id/cheat_count, sparse cheat_ext,
/// desc_string.text_key. Older files are refused and must be downloaded again.
static const int kRACheatSchemaVersion = 5;

/// Identity (inode/size/mtime) of the last cheat.sqlite that passed
/// quick_check, so the full check runs once per installed file.
static NSString * const kRACheatVerifiedFileKey = @"RACheatCatalogVerifiedFile";

// Game columns of every catalog game query, in p_gameFromStmt order.
#define RA_CHEAT_GAME_COLUMNS "g.id, g.platform_id, g.game_name, g.group_name, g.cheat_count"
#define RA_CHEAT_GAME_COLUMNS_LOC RA_CHEAT_GAME_COLUMNS ", l.name, COALESCE(l.source, 0)"
#define RA_CHEAT_GAME_COLUMNS_PLAIN RA_CHEAT_GAME_COLUMNS ", NULL, 0"
#define RA_CHEAT_LANG_JOIN "LEFT JOIN lang.game_name l ON l.platform_id = g.platform_id AND l.group_name = g.group_name "

// Cheat columns, in p_cheatFromStmt order. A game's cheats are the id range
// first_cheat_id .. first_cheat_id + cheat_count - 1. cheat_ext only has the
// rows whose RETRO/rumble fields differ from RetroArch's defaults; for the
// others the e.* columns are NULL and p_cheatFromStmt applies the defaults.
#define RA_CHEAT_COLUMNS_HEAD "ch.id, g.id, ch.cheat_index, COALESCE(ch.desc_id, 0), ds.text, "
#define RA_CHEAT_COLUMNS_TAIL ", ch.code, ch.handler, e.cheat_id, e.enable, e.memory_search_size, e.cheat_type, " \
    "e.value, e.address, e.address_mask, e.big_endian, e.repeat_count, e.repeat_add_to_value, " \
    "e.repeat_add_to_address, e.rumble_type, e.rumble_value, e.rumble_port, " \
    "e.rumble_primary_strength, e.rumble_primary_duration, e.rumble_secondary_strength, " \
    "e.rumble_secondary_duration "
#define RA_CHEAT_FROM "FROM game g " \
    "JOIN cheat ch ON ch.id BETWEEN g.first_cheat_id AND g.first_cheat_id + g.cheat_count - 1 " \
    "LEFT JOIN cheat_ext e ON e.cheat_id = ch.id " \
    "LEFT JOIN desc_string ds ON ds.id = ch.desc_id "

static NSString * _Nullable p_colText(sqlite3_stmt *stmt, int col);
static NSString *p_groupNameFromGameName(NSString *name);
static NSArray<NSString *> *p_regionPreferences(NSString *name);
static BOOL p_nameContainsRegion(NSString *name, NSString *region);
static BOOL p_isSpecialTemplateName(NSString *name);
static NSString * _Nullable p_fileIdentity(NSString *path);
static NSString *p_placeholders(NSUInteger count);

@interface RAGameEntry(RACheatCatalogPrivate)
@property (nonatomic, assign, readwrite) NSInteger gameId;
@property (nonatomic, assign, readwrite) NSInteger platformId;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, nullable, readwrite) NSString *groupName;
@property (nonatomic, copy, nullable, readwrite) NSString *localizedName;
@property (nonatomic, copy, nullable, readwrite) NSString *localizationLanguage;
@property (nonatomic, assign, readwrite) NSInteger localizationSource;
@property (nonatomic, assign, readwrite, getter=isLocalizationReference) BOOL localizationReference;
@property (nonatomic, assign, readwrite) NSInteger cheatCount;
@end

@interface RACheatCatalogManager()
@property (nonatomic, assign, readwrite) NSInteger currentDBVersion;
@property (nonatomic, assign, readwrite, getter=isDatabaseReady) BOOL databaseReady;
@end

@implementation RACheatCatalogManager
{
    NSString *d_cheatPath;
    NSString *d_languagePackPath;
    sqlite3 *d_db;
    // The language pack attached as `lang`; nil language = English only.
    BOOL d_hasLanguagePack;
    NSString *d_languagePackLanguage;
    NSString *d_openedFileIdentity;
    NSString *d_openedPackIdentity;
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
               languagePackPath:(nullable NSString *)languagePackPath
                     completion:(nullable void (^)(void))completion {
    NSString *nextCheatPath = [cheatPath copy];
    NSString *nextPackPath = languagePackPath.length > 0 ? [languagePackPath copy] : nil;
    dispatch_async(d_dbQueue, ^{
        BOOL samePaths = d_db &&
            [d_cheatPath isEqualToString:nextCheatPath] &&
            ((d_languagePackPath == nil && nextPackPath == nil) || [d_languagePackPath isEqualToString:nextPackPath]);
        // The same path may now hold a different file (re-downloaded or
        // deleted); an immutable handle would keep reading the old one.
        BOOL sameFiles = samePaths &&
            [d_openedFileIdentity isEqualToString:p_fileIdentity(nextCheatPath) ?: @""] &&
            [(d_openedPackIdentity ?: @"") isEqualToString:(nextPackPath ? p_fileIdentity(nextPackPath) : nil) ?: @""];
        if (!sameFiles) {
            d_cheatPath = nextCheatPath;
            d_languagePackPath = nextPackPath;
            [self p_open];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

- (void)closeDatabase {
    dispatch_async(d_dbQueue, ^{
        [self p_close];
    });
}

- (void)dealloc {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
}

// MARK: - Catalog games

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
        BOOL hasKeyword = trimmed.length > 0;
        BOOL loc = d_hasLanguagePack;
        NSMutableString *where = [NSMutableString stringWithFormat:@"g.platform_id IN (%@)", p_placeholders(ids.count)];
        if (hasKeyword) {
            [where appendString:loc
                ? @" AND (g.game_name LIKE ? OR g.group_name LIKE ? OR l.name LIKE ?)"
                : @" AND (g.game_name LIKE ? OR g.group_name LIKE ?)"];
        }
        NSString *join = loc ? @RA_CHEAT_LANG_JOIN : @"";
        NSString *like = [NSString stringWithFormat:@"%%%@%%", trimmed];
        void (^bindFilter)(sqlite3_stmt *, int *) = ^(sqlite3_stmt *stmt, int *bind) {
            for (NSNumber *pid in ids) {
                sqlite3_bind_int64(stmt, (*bind)++, (sqlite3_int64)pid.integerValue);
            }
            if (hasKeyword) {
                for (int i = 0; i < (loc ? 3 : 2); i++) {
                    sqlite3_bind_text(stmt, (*bind)++, like.UTF8String, -1, SQLITE_TRANSIENT);
                }
            }
        };

        if (totalCount <= 0) {
            NSString *countSQL = [NSString stringWithFormat:@"SELECT COUNT(*) FROM game g %@WHERE %@;", join, where];
            sqlite3_stmt *stmt = NULL;
            if (d_db && sqlite3_prepare_v2(d_db, countSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
                int bind = 1;
                bindFilter(stmt, &bind);
                int rc = sqlite3_step(stmt);
                if (rc == SQLITE_ROW) {
                    totalCount = (NSInteger)sqlite3_column_int64(stmt, 0);
                } else {
                    error = [self p_stepFailed:rc context:"cheat game count"];
                }
            } else {
                error = [self p_prepareFailed:"cheat game count"];
            }
            sqlite3_finalize(stmt);
        }

        NSMutableArray<RAGameEntry *> *games = [NSMutableArray array];
        if (!error) {
            NSString *sql = [NSString stringWithFormat:
                @"SELECT %s FROM game g %@WHERE %@ "
                @"ORDER BY g.platform_id ASC, g.group_name COLLATE NOCASE ASC, g.game_name COLLATE NOCASE ASC "
                @"LIMIT ? OFFSET ?;",
                loc ? RA_CHEAT_GAME_COLUMNS_LOC : RA_CHEAT_GAME_COLUMNS_PLAIN, join, where];
            sqlite3_stmt *stmt = NULL;
            if (d_db && sqlite3_prepare_v2(d_db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
                int bind = 1;
                bindFilter(stmt, &bind);
                sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)limit);
                sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)offset);
                int rc;
                while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
                    [games addObject:[self p_gameFromStmt:stmt]];
                }
                if (rc != SQLITE_DONE) {
                    error = [self p_stepFailed:rc context:"cheat game page"];
                }
            } else {
                error = [self p_prepareFailed:"cheat game page"];
            }
            sqlite3_finalize(stmt);
        }

        NSArray *copy = [games copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, totalCount, error);
        });
    });
}

- (void)fetchFeaturedGamesForPlatformIds:(NSArray<NSNumber *> *)platformIds
                               gameNames:(NSArray<NSString *> *)gameNames
                              completion:(void (^)(NSArray<RAGameEntry *> *games,
                                                   NSError * _Nullable error))completion {
    if (platformIds.count == 0 || gameNames.count == 0) {
        completion(@[], nil);
        return;
    }
    NSArray<NSNumber *> *ids = [platformIds copy];
    NSArray<NSString *> *names = [gameNames copy];
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        BOOL loc = d_hasLanguagePack;
        // game_name is unique within the featured set, so look results up by
        // name and re-emit in the caller's order (SQL IN(...) loses order).
        NSMutableDictionary<NSString *, RAGameEntry *> *byName =
            [NSMutableDictionary dictionaryWithCapacity:names.count];
        NSString *sql = [NSString stringWithFormat:
            @"SELECT %s FROM game g %@WHERE g.platform_id IN (%@) AND g.game_name IN (%@);",
            loc ? RA_CHEAT_GAME_COLUMNS_LOC : RA_CHEAT_GAME_COLUMNS_PLAIN,
            loc ? @RA_CHEAT_LANG_JOIN : @"", p_placeholders(ids.count), p_placeholders(names.count)];
        sqlite3_stmt *stmt = NULL;
        if (d_db && sqlite3_prepare_v2(d_db, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
            int bind = 1;
            for (NSNumber *pid in ids) {
                sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)pid.integerValue);
            }
            for (NSString *name in names) {
                sqlite3_bind_text(stmt, bind++, name.UTF8String, -1, SQLITE_TRANSIENT);
            }
            int rc;
            while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
                RAGameEntry *entry = [self p_gameFromStmt:stmt];
                if (entry.name.length > 0) {
                    byName[entry.name] = entry;
                }
            }
            if (rc != SQLITE_DONE) {
                error = [self p_stepFailed:rc context:"cheat featured games"];
            }
        } else {
            error = [self p_prepareFailed:"cheat featured games"];
        }
        sqlite3_finalize(stmt);

        NSMutableArray<RAGameEntry *> *games = [NSMutableArray arrayWithCapacity:names.count];
        if (!error) {
            for (NSString *name in names) {
                RAGameEntry *entry = byName[name];
                if (entry) { [games addObject:entry]; }
            }
        }
        NSArray *copy = [games copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, error);
        });
    });
}

// MARK: - Cheats

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
        // RACheatItem.desc is the UI/apply-facing text: the pack's translation
        // when there is one, else the English original (also in descEnglish).
        const char *sql = d_hasLanguagePack
            ? "SELECT " RA_CHEAT_COLUMNS_HEAD "COALESCE(lc.text, ds.text), COALESCE(lc.source, 0)" RA_CHEAT_COLUMNS_TAIL
              RA_CHEAT_FROM "LEFT JOIN lang.cheat_desc lc ON lc.text_key = ds.text_key "
              "WHERE g.id = ? ORDER BY ch.cheat_index ASC;"
            : "SELECT " RA_CHEAT_COLUMNS_HEAD "ds.text, 0" RA_CHEAT_COLUMNS_TAIL
              RA_CHEAT_FROM "WHERE g.id = ? ORDER BY ch.cheat_index ASC;";
        sqlite3_stmt *stmt = NULL;
        if (d_db && sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (sqlite3_int64)gameId);
            int rc;
            while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
                [cheats addObject:[self p_cheatFromStmt:stmt]];
            }
            if (rc != SQLITE_DONE) {
                error = [self p_stepFailed:rc context:"fetch cheats by game id"];
            }
        } else {
            error = [self p_prepareFailed:"fetch cheats by game id"];
        }
        sqlite3_finalize(stmt);

        NSArray *copy = [cheats copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, error);
        });
    });
}

- (nullable NSDictionary<NSNumber *, NSNumber *> *)cheatIndexesForCheatIds:(NSArray<NSNumber *> *)cheatIds
                                                                    gameId:(NSInteger)gameId
                                                                     error:(NSError **)error {
    __block NSMutableDictionary<NSNumber *, NSNumber *> *result = [NSMutableDictionary dictionary];
    __block NSError *failure = nil;
    if (cheatIds.count == 0 || gameId <= 0) {
        return result;
    }
    NSArray<NSNumber *> *ids = [cheatIds copy];
    dispatch_sync(d_dbQueue, ^{
        if (!d_db) {
            failure = [self p_error:@"cheat catalog is not open"];
            return;
        }
        NSString *sql = [NSString stringWithFormat:
            @"SELECT ch.id, ch.cheat_index FROM game g "
            @"JOIN cheat ch ON ch.id BETWEEN g.first_cheat_id AND g.first_cheat_id + g.cheat_count - 1 "
            @"WHERE g.id = ? AND ch.id IN (%@);", p_placeholders(ids.count)];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            failure = [self p_prepareFailed:"cheat indexes"];
            return;
        }
        int bind = 1;
        sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)gameId);
        for (NSNumber *cheatId in ids) {
            sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)cheatId.integerValue);
        }
        int rc;
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            result[@(sqlite3_column_int64(stmt, 0))] = @(sqlite3_column_int64(stmt, 1));
        }
        if (rc != SQLITE_DONE) {
            failure = [self p_stepFailed:rc context:"cheat indexes"];
        }
        sqlite3_finalize(stmt);
    });
    if (failure) {
        if (error) { *error = failure; }
        return nil;
    }
    return result;
}

// MARK: - Lookups (auto-binding)

- (BOOL)lookupGameForPlatformIds:(NSArray<NSNumber *> *)platformIds
                     englishName:(NSString *)englishName
                            game:(RAGameEntry * _Nullable * _Nonnull)game
                           error:(NSError **)error {
    *game = nil;
    if (platformIds.count == 0 || englishName.length == 0) {
        return YES;
    }

    NSArray<NSNumber *> *ids = [platformIds copy];
    NSString *name = [englishName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (name.length == 0) {
        return YES;
    }

    __block RAGameEntry *result = nil;
    __block NSError *failure = nil;
    dispatch_sync(d_dbQueue, ^{
        if (!d_db) {
            failure = [self p_error:@"cheat catalog is not open"];
            return;
        }

        NSMutableString *placeholders = [NSMutableString string];
        for (NSUInteger i = 0; i < ids.count; i++) {
            if (i > 0) { [placeholders appendString:@","]; }
            [placeholders appendString:@"?"];
        }

        NSString *exactSQL = [NSString stringWithFormat:
            @"SELECT " RA_CHEAT_GAME_COLUMNS_PLAIN " "
            @"FROM game g "
            @"WHERE g.platform_id IN (%@) "
            @"  AND g.game_name = ? COLLATE NOCASE "
            @"ORDER BY g.platform_id ASC, g.game_name COLLATE NOCASE ASC "
            @"LIMIT 2;", placeholders];

        sqlite3_stmt *stmt = NULL;
        NSMutableArray<RAGameEntry *> *matches = [NSMutableArray arrayWithCapacity:2];
        if (sqlite3_prepare_v2(d_db, exactSQL.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            failure = [self p_prepareFailed:"find game by name"];
            return;
        }
        int bind = 1;
        for (NSNumber *pid in ids) {
            sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)pid.integerValue);
        }
        sqlite3_bind_text(stmt, bind++, name.UTF8String, -1, SQLITE_TRANSIENT);
        int rc = SQLITE_DONE;
        while (matches.count < 2 && (rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            [matches addObject:[self p_gameFromStmt:stmt]];
        }
        if (matches.count < 2 && rc != SQLITE_DONE) {
            failure = [self p_stepFailed:rc context:"find game by name"];
        }
        sqlite3_finalize(stmt);
        if (failure) {
            return;
        }
        if (matches.count == 1) {
            result = matches.firstObject;
            return;
        }

        NSString *groupName = p_groupNameFromGameName(name);
        if (groupName.length == 0) {
            return;
        }

        NSString *groupSQL = [NSString stringWithFormat:
            @"SELECT " RA_CHEAT_GAME_COLUMNS_PLAIN " "
            @"FROM game g "
            @"WHERE g.platform_id IN (%@) "
            @"  AND g.group_name = ? COLLATE NOCASE "
            @"ORDER BY g.platform_id ASC, g.game_name COLLATE NOCASE ASC "
            @"LIMIT 20;", placeholders];

        [matches removeAllObjects];
        stmt = NULL;
        if (sqlite3_prepare_v2(d_db, groupSQL.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            failure = [self p_prepareFailed:"find game by group"];
            return;
        }
        bind = 1;
        for (NSNumber *pid in ids) {
            sqlite3_bind_int64(stmt, bind++, (sqlite3_int64)pid.integerValue);
        }
        sqlite3_bind_text(stmt, bind++, groupName.UTF8String, -1, SQLITE_TRANSIENT);
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            RAGameEntry *candidate = [self p_gameFromStmt:stmt];
            if (!p_isSpecialTemplateName(name) && p_isSpecialTemplateName(candidate.name)) {
                continue;
            }
            [matches addObject:candidate];
        }
        if (rc != SQLITE_DONE) {
            failure = [self p_stepFailed:rc context:"find game by group"];
        }
        sqlite3_finalize(stmt);
        if (failure) {
            return;
        }

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
        // Some cht sets (e.g. Dreamcast) name the USA release without a region
        // tag and only tag the others ("(Japanese)", "(European)"). For a USA or
        // World ROM, take the single untagged template of the group.
        NSArray<NSString *> *preferences = p_regionPreferences(name);
        if ([preferences containsObject:@"usa"] || [preferences containsObject:@"world"]) {
            NSPredicate *untagged = [NSPredicate predicateWithBlock:^BOOL(RAGameEntry *candidate, NSDictionary *bindings) {
                return [candidate.name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"(["]].location == NSNotFound;
            }];
            NSArray<RAGameEntry *> *untaggedMatches = [matches filteredArrayUsingPredicate:untagged];
            if (untaggedMatches.count == 1) {
                result = untaggedMatches.firstObject;
                return;
            }
        }
    });
    if (failure) {
        if (error) { *error = failure; }
        return NO;
    }
    *game = result;
    return YES;
}

- (BOOL)lookupGameForGameId:(NSInteger)gameId
                       game:(RAGameEntry * _Nullable * _Nonnull)game
                      error:(NSError **)error {
    *game = nil;
    if (gameId <= 0) {
        return YES;
    }
    return [self p_lookupSingleGame:"SELECT " RA_CHEAT_GAME_COLUMNS_PLAIN " FROM game g WHERE g.id = ? LIMIT 1;"
                            context:"find game by id"
                               bind:^(sqlite3_stmt *stmt) {
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)gameId);
    } game:game error:error];
}

- (BOOL)lookupGameForPlatformId:(NSInteger)platformId
                      exactName:(NSString *)gameName
                           game:(RAGameEntry * _Nullable * _Nonnull)game
                          error:(NSError **)error {
    *game = nil;
    if (platformId <= 0 || gameName.length == 0) {
        return YES;
    }
    NSString *name = [gameName copy];
    return [self p_lookupSingleGame:"SELECT " RA_CHEAT_GAME_COLUMNS_PLAIN " FROM game g "
                                    "WHERE g.platform_id = ? AND g.game_name = ? ORDER BY g.id ASC LIMIT 1;"
                            context:"find game by exact name"
                               bind:^(sqlite3_stmt *stmt) {
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
        sqlite3_bind_text(stmt, 2, name.UTF8String, -1, SQLITE_TRANSIENT);
    } game:game error:error];
}

/// Runs a query expected to return at most one game row. Returns NO only when
/// the query itself failed; "no such game" is YES with *game left nil.
- (BOOL)p_lookupSingleGame:(const char *)sql
                   context:(const char *)context
                      bind:(void (^)(sqlite3_stmt *stmt))bind
                      game:(RAGameEntry * _Nullable * _Nonnull)game
                     error:(NSError **)error {
    __block RAGameEntry *result = nil;
    __block NSError *failure = nil;
    dispatch_sync(d_dbQueue, ^{
        if (!d_db) {
            failure = [self p_error:@"cheat catalog is not open"];
            return;
        }
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            failure = [self p_prepareFailed:context];
            return;
        }
        bind(stmt);
        int rc = sqlite3_step(stmt);
        if (rc == SQLITE_ROW) {
            result = [self p_gameFromStmt:stmt];
        } else if (rc != SQLITE_DONE) {
            failure = [self p_stepFailed:rc context:context];
        }
        sqlite3_finalize(stmt);
    });
    if (failure) {
        if (error) { *error = failure; }
        return NO;
    }
    *game = result;
    return YES;
}

// MARK: - Open / verify

- (void)p_close {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
    d_hasLanguagePack = NO;
    d_languagePackLanguage = nil;
    d_openedFileIdentity = nil;
    d_openedPackIdentity = nil;
    self.currentDBVersion = 0;
    self.databaseReady = NO;
}

- (BOOL)p_open {
    [self p_close];
    NSString *identity = p_fileIdentity(d_cheatPath);
    if (!identity) {
        RETROGO_LOGI(CHEAT, "Cheat catalog not installed");
        return NO;
    }
    NSString *uri = [[[NSURL fileURLWithPath:d_cheatPath] absoluteString]
                     stringByAppendingString:@"?immutable=1"];
    int rc = sqlite3_open_v2(uri.UTF8String, &d_db,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL);
    if (rc != SQLITE_OK) {
        RETROGO_LOGE(CHEAT, "Failed to open cheat catalog database (%d): %@", rc, d_cheatPath);
        [self p_close];
        return NO;
    }
    int schema = -1;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(d_db, "PRAGMA user_version;", -1, &stmt, NULL) == SQLITE_OK &&
        sqlite3_step(stmt) == SQLITE_ROW) {
        schema = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    if (schema != kRACheatSchemaVersion) {
        // A catalog from an older App: the queries below don't fit it.
        RETROGO_LOGN(CHEAT, "Cheat catalog has schema %d, expected %d; it needs to be downloaded again", schema, kRACheatSchemaVersion);
        [self p_close];
        return NO;
    }
    stmt = NULL;
    if (sqlite3_prepare_v2(d_db, "SELECT value FROM meta WHERE key = 'db_version';", -1, &stmt, NULL) == SQLITE_OK &&
        sqlite3_step(stmt) == SQLITE_ROW) {
        self.currentDBVersion = (NSInteger)sqlite3_column_int64(stmt, 0);
    }
    sqlite3_finalize(stmt);
    if (![self p_verifyOpenedDatabase:identity]) {
        [self p_close];
        return NO;
    }
    [self p_attachLanguagePack];
    d_openedFileIdentity = identity;
    self.databaseReady = YES;
    return YES;
}

/// Each manager owns its connection; the pack is attached here as read-only
/// lookup data instead of sharing RAGameRDBManager's handle.
- (void)p_attachLanguagePack {
    NSString *path = d_languagePackPath;
    NSString *identity = path ? p_fileIdentity(path) : nil;
    if (!identity) {
        return;
    }
    NSString *uri = [[[NSURL fileURLWithPath:path] absoluteString] stringByAppendingString:@"?mode=ro&immutable=1"];
    NSString *escaped = [uri stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
    NSString *sql = [NSString stringWithFormat:@"ATTACH DATABASE '%@' AS lang;", escaped];
    if (sqlite3_exec(d_db, sql.UTF8String, NULL, NULL, NULL) != SQLITE_OK) {
        RETROGO_LOGE(CHEAT, "Failed to attach language pack to cheat catalog: %{public}s", sqlite3_errmsg(d_db));
        return;
    }
    NSString *language = RALanguagePackLanguage(d_db, "lang");
    if (!language) {
        sqlite3_exec(d_db, "DETACH DATABASE lang;", NULL, NULL, NULL);
        return;
    }
    d_hasLanguagePack = YES;
    d_languagePackLanguage = language;
    d_openedPackIdentity = identity;
}

/// Cheap health check of a freshly opened catalog. A file that cannot be read
/// must not look like an empty catalog: callers would show no templates and
/// the auto-binder would record "no match". The full page scan (quick_check)
/// is done once per file by +verifyCatalogFileAtPath:, off the UI path.
- (BOOL)p_verifyOpenedDatabase:(NSString *)identity {
    long long gameCount = -1, cheatCount = -1;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(d_db, "SELECT (SELECT COUNT(*) FROM game), (SELECT COUNT(*) FROM cheat);", -1, &stmt, NULL) != SQLITE_OK) {
        [self p_prepareFailed:"row count"];
        return NO;
    }
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        gameCount = sqlite3_column_int64(stmt, 0);
        cheatCount = sqlite3_column_int64(stmt, 1);
    } else {
        [self p_stepFailed:rc context:"row count"];
    }
    sqlite3_finalize(stmt);
    if (gameCount <= 0 || cheatCount <= 0) {
        RETROGO_LOGE(CHEAT, "Cheat catalog is empty or unreadable (%lld games, %lld cheats)", gameCount, cheatCount);
        return NO;
    }
    RETROGO_LOGI(CHEAT, "Opened cheat catalog: db_version %ld, %lld games, %lld cheats, verified %d",
                 (long)self.currentDBVersion, gameCount, cheatCount,
                 [[NSUserDefaults.standardUserDefaults stringForKey:kRACheatVerifiedFileKey] isEqualToString:identity]);
    return YES;
}

+ (BOOL)isCatalogFileVerifiedAtPath:(NSString *)path {
    NSString *identity = p_fileIdentity(path);
    return identity && [[NSUserDefaults.standardUserDefaults stringForKey:kRACheatVerifiedFileKey] isEqualToString:identity];
}

+ (BOOL)verifyCatalogFileAtPath:(NSString *)path {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *identity = p_fileIdentity(path);
    if (!identity) {
        return NO;
    }
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSString *uri = [[[NSURL fileURLWithPath:path] absoluteString] stringByAppendingString:@"?immutable=1"];
    sqlite3 *db = NULL;
    BOOL ok = NO;
    if (sqlite3_open_v2(uri.UTF8String, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL) == SQLITE_OK) {
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, "PRAGMA quick_check(5);", -1, &stmt, NULL) == SQLITE_OK) {
            ok = YES;
            int rc;
            while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
                const char *result = (const char *)sqlite3_column_text(stmt, 0);
                if (!result || strcmp(result, "ok") != 0) {
                    RETROGO_LOGE(CHEAT, "Cheat catalog quick_check: %{public}s", result ? result : "(null)");
                    ok = NO;
                }
            }
            if (rc != SQLITE_DONE) {
                RETROGO_LOGE(CHEAT, "Cheat catalog quick_check step failed (%d): %{public}s", rc, sqlite3_errmsg(db));
                ok = NO;
            }
        } else {
            RETROGO_LOGE(CHEAT, "Cheat catalog quick_check prepare failed: %{public}s", sqlite3_errmsg(db));
        }
        sqlite3_finalize(stmt);
        if (ok) {
            stmt = NULL;
            ok = NO;
            if (sqlite3_prepare_v2(db, "SELECT (SELECT COUNT(*) FROM game) > 0 AND (SELECT COUNT(*) FROM cheat) > 0;", -1, &stmt, NULL) == SQLITE_OK &&
                sqlite3_step(stmt) == SQLITE_ROW) {
                ok = sqlite3_column_int(stmt, 0) != 0;
            }
            sqlite3_finalize(stmt);
            if (!ok) {
                RETROGO_LOGE(CHEAT, "Cheat catalog has no games or cheats");
            }
        }
    } else {
        RETROGO_LOGE(CHEAT, "Failed to open cheat catalog for verification: %{public}s", db ? sqlite3_errmsg(db) : "out of memory");
    }
    if (db) {
        sqlite3_close(db);
    }
    if (ok) {
        [defaults setObject:identity forKey:kRACheatVerifiedFileKey];
        RETROGO_LOGI(CHEAT, "Cheat catalog verified in %.2fs", CFAbsoluteTimeGetCurrent() - start);
    } else {
        [defaults removeObjectForKey:kRACheatVerifiedFileKey];
    }
    return ok;
}

- (NSError *)p_prepareFailed:(const char *)context {
    const char *message = d_db ? sqlite3_errmsg(d_db) : "no database";
    RETROGO_LOGE(CHEAT, "Cheat catalog %{public}s prepare failed: %{public}s", context, message);
    return [self p_error:[NSString stringWithFormat:@"%s prepare failed: %s", context, message]];
}

/// sqlite3_step failures used to end the row loop silently and look like an
/// empty result. Log them and turn them into an error for the caller.
- (NSError *)p_stepFailed:(int)rc context:(const char *)context {
    const char *message = d_db ? sqlite3_errmsg(d_db) : "no database";
    RETROGO_LOGE(CHEAT, "Cheat catalog %{public}s step failed (%d): %{public}s", context, rc, message);
    return [self p_error:[NSString stringWithFormat:@"%s failed: %s", context, message]];
}

// MARK: - Rows

- (RAGameEntry *)p_gameFromStmt:(sqlite3_stmt *)stmt {
    RAGameEntry *game = [[RAGameEntry alloc] init];
    game.gameId = (NSInteger)sqlite3_column_int64(stmt, 0);
    game.platformId = (NSInteger)sqlite3_column_int64(stmt, 1);
    NSString *gameName = p_colText(stmt, 2);
    NSString *groupName = p_colText(stmt, 3);
    game.name = gameName ?: (groupName ?: @"");
    game.groupName = groupName;
    game.cheatCount = (NSInteger)sqlite3_column_int64(stmt, 4);
    game.localizedName = p_colText(stmt, 5);
    if (game.localizedName) {
        game.localizationLanguage = d_languagePackLanguage;
    }
    game.localizationSource = (NSInteger)sqlite3_column_int64(stmt, 6);
    game.localizationReference = game.localizationSource == 5;
    return game;
}

- (RACheatItem *)p_cheatFromStmt:(sqlite3_stmt *)stmt {
    RACheatItem *item = [[RACheatItem alloc] init];
    item.catalogId = (NSInteger)sqlite3_column_int64(stmt, 0);
    item.catalogGameId = (NSInteger)sqlite3_column_int64(stmt, 1);
    item.catalogIndex = (NSInteger)sqlite3_column_int64(stmt, 2);
    item.catalogDescId = (NSInteger)sqlite3_column_int64(stmt, 3);
    item.descEnglish = p_colText(stmt, 4);
    item.desc = p_colText(stmt, 5) ?: @"";
    item.descSource = (NSInteger)sqlite3_column_int64(stmt, 6);
    item.code = p_colText(stmt, 7) ?: @"";
    item.handler = (RACheatHandler)sqlite3_column_int64(stmt, 8);
    if (sqlite3_column_type(stmt, 9) == SQLITE_NULL) {
        // No cheat_ext row: every field is at the cheat_manager.c default.
        item.enabled = NO;
        item.memorySearchSize = 3;
        item.cheatType = 1;
        item.value = 0;
        item.address = 0;
        item.addressMask = 0;
        item.bigEndian = 0;
        item.repeatCount = 1;
        item.repeatAddToValue = 0;
        item.repeatAddToAddress = 1;
        item.rumbleType = 0;
        item.rumbleValue = 0;
        item.rumblePort = 0;
        item.rumblePrimaryStrength = 0;
        item.rumblePrimaryDuration = 0;
        item.rumbleSecondaryStrength = 0;
        item.rumbleSecondaryDuration = 0;
        return item;
    }
    item.enabled = sqlite3_column_int64(stmt, 10) != 0;
    item.memorySearchSize = (NSInteger)sqlite3_column_int64(stmt, 11);
    item.cheatType = (NSInteger)sqlite3_column_int64(stmt, 12);
    item.value = (NSInteger)sqlite3_column_int64(stmt, 13);
    item.address = (NSInteger)sqlite3_column_int64(stmt, 14);
    item.addressMask = (NSInteger)sqlite3_column_int64(stmt, 15);
    item.bigEndian = (NSInteger)sqlite3_column_int64(stmt, 16);
    item.repeatCount = (NSInteger)sqlite3_column_int64(stmt, 17);
    item.repeatAddToValue = (NSInteger)sqlite3_column_int64(stmt, 18);
    item.repeatAddToAddress = (NSInteger)sqlite3_column_int64(stmt, 19);
    item.rumbleType = (NSInteger)sqlite3_column_int64(stmt, 20);
    item.rumbleValue = (NSInteger)sqlite3_column_int64(stmt, 21);
    item.rumblePort = (NSInteger)sqlite3_column_int64(stmt, 22);
    item.rumblePrimaryStrength = (NSInteger)sqlite3_column_int64(stmt, 23);
    item.rumblePrimaryDuration = (NSInteger)sqlite3_column_int64(stmt, 24);
    item.rumbleSecondaryStrength = (NSInteger)sqlite3_column_int64(stmt, 25);
    item.rumbleSecondaryDuration = (NSInteger)sqlite3_column_int64(stmt, 26);
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

static NSString *p_placeholders(NSUInteger count) {
    NSMutableString *placeholders = [NSMutableString stringWithCapacity:count * 2];
    for (NSUInteger i = 0; i < count; i++) {
        [placeholders appendString:i > 0 ? @",?" : @"?"];
    }
    return placeholders;
}

static NSString * _Nullable p_fileIdentity(NSString *path) {
    if (path.length == 0) {
        return nil;
    }
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    if (!attrs) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@-%llu-%.3f",
            attrs[NSFileSystemFileNumber], attrs.fileSize,
            attrs.fileModificationDate.timeIntervalSince1970];
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
