//
//  RAGameRDBManager.m
//  RetroGo
//
//  Created by RetroGo on 2026/5/19.
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

#import "RAGameRDBManager.h"
#import "RALanguagePack.h"

#include <sqlite3.h>
#include <CoreFoundation/CoreFoundation.h>

#include <libretrodb.h>
#include <rmsgpack_dom.h>
#include <utils/retrogo_log.h>

// ---------------------------------------------------------------------------
// MARK: - Internal constants
// ---------------------------------------------------------------------------

static NSString * const kRARDBErrorDomain = @"com.retrogame.rardberror";

typedef NS_ENUM(NSInteger, RARDBErrorCode) {
    RARDBErrorCodeOpenFailed   = 1001,
    RARDBErrorCodeCreateFailed = 1002,
    RARDBErrorCodeImportFailed = 1003,
    RARDBErrorCodeQueryFailed  = 1004,
};

// ---------------------------------------------------------------------------
// MARK: - DDL
// ---------------------------------------------------------------------------

static const char * const kDDL_Platform =
    "CREATE TABLE IF NOT EXISTS platform ("
    "  id           INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  rdb_name     TEXT    NOT NULL UNIQUE,"
    "  display_name TEXT    NOT NULL,"
    "  manufacturer TEXT,"
    "  game_count   INTEGER NOT NULL DEFAULT 0,"   // Total number of games (variants) for this platform
    "  group_count  INTEGER NOT NULL DEFAULT 0,"   // Number of deduplicated groups for this platform (for list paging)
    "  imported_at  INTEGER NOT NULL"
    ");";

// The game table stores every ROM variant (CRC32/md5/sha1 match per variant, so never deduplicate).
// group_name is the "group key": the prefix of the game name before the first ( or [, computed at import.
static const char * const kDDL_Game =
    "CREATE TABLE IF NOT EXISTS game ("
    "  id            INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  platform_id   INTEGER NOT NULL REFERENCES platform(id) ON DELETE CASCADE,"
    "  name          TEXT    NOT NULL,"
    "  group_name    TEXT,"
    "  developer     TEXT,"
    "  publisher     TEXT,"
    "  release_year  INTEGER,"
    "  release_month INTEGER,"
    "  genre         TEXT,"
    "  region        TEXT,"
    "  franchise     TEXT,"
    "  description   TEXT,"
    "  serial        TEXT,"
    "  max_users     INTEGER,"
    "  rom_name      TEXT,"
    "  crc32         TEXT,"
    "  md5           TEXT,"
    "  sha1          TEXT,"
    "  file_size     INTEGER"
    ");";

// Materialized group table: one row per (platform_id, group_name), recording the representative variant and variant count.
// Lists/paging read this small table directly instead of running GROUP BY over 50k game rows.
static const char * const kDDL_GameGroup =
    "CREATE TABLE IF NOT EXISTS game_group ("
    "  id                     INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  platform_id            INTEGER NOT NULL,"
    "  group_name             TEXT    NOT NULL,"
    "  representative_game_id INTEGER NOT NULL,"
    "  variant_count          INTEGER NOT NULL"
    ");";

static const char * const kDDL_GameIndexPlatform =
    "CREATE INDEX IF NOT EXISTS idx_game_platform_id ON game(platform_id);";

static const char * const kDDL_GameIndexCRC32 =
    "CREATE INDEX IF NOT EXISTS idx_game_crc32 ON game(crc32);";

static const char * const kDDL_GameIndexName =
    "CREATE INDEX IF NOT EXISTS idx_game_name ON game(name COLLATE NOCASE);";

// Supports equality lookups of "all variants of a (platform_id, group_name) group" (BINARY comparison,
// so the index has no COLLATE NOCASE and group_name = ? can use it).
static const char * const kDDL_GameIndexGroup =
    "CREATE INDEX IF NOT EXISTS idx_game_group ON game(platform_id, group_name);";

// Supports sorting and paging the group list by group_name.
static const char * const kDDL_GroupIndexPlatform =
    "CREATE INDEX IF NOT EXISTS idx_group_platform ON game_group(platform_id, group_name COLLATE NOCASE);";

static const char * const kDDL_GameFTS =
    "CREATE VIRTUAL TABLE IF NOT EXISTS game_fts USING fts5("
    "  name,"
    "  developer,"
    "  publisher,"
    "  game_id  UNINDEXED,"
    "  tokenize = 'unicode61'"
    ");";

// ---------------------------------------------------------------------------
// MARK: - Group key
// ---------------------------------------------------------------------------

/// Computes the "group key" from a game name: the prefix before the first '(' or '[' with trailing whitespace removed.
/// Examples:
///   "1 on 1 Government (Japan)"              → "1 on 1 Government"
///   "10 X 10 (Barcrest) (MPU4) (N25 0.3 AD)" → "10 X 10"
///   "005"                                    → "005"
/// When the prefix is empty (the name starts with a bracket), falls back to the full name so the group key is never empty.
static NSString *p_groupName(NSString *name) {
    if (name.length == 0) return name;
    NSRange r = [name rangeOfCharacterFromSet:
                 [NSCharacterSet characterSetWithCharactersInString:@"(["]];
    NSString *base = (r.location != NSNotFound)
                   ? [name substringToIndex:r.location]
                   : name;
    base = [base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return base.length > 0 ? base : name;
}

static NSString *p_locNorm(NSString *s);

// ---------------------------------------------------------------------------
// MARK: - RAPlatformItem
// ---------------------------------------------------------------------------

@interface RAPlatformItem()
@property (nonatomic, assign, readwrite) NSInteger  platformId;
@property (nonatomic, copy, readwrite)   NSString  *rdbName;
@property (nonatomic, copy, readwrite)   NSString  *displayName;
@property (nonatomic, copy, readwrite)   NSString  *manufacturer;
@property (nonatomic, assign, readwrite) NSInteger  gameCount;
@property (nonatomic, assign, readwrite) NSInteger  groupCount;
@end

@implementation RAPlatformItem
@end

// ---------------------------------------------------------------------------
// MARK: - RAGameEntry
// ---------------------------------------------------------------------------

@interface RAGameEntry()
@property (nonatomic, assign, readwrite)         NSInteger  gameId;
@property (nonatomic, assign, readwrite)         NSInteger  platformId;
@property (nonatomic, copy, readwrite)           NSString  *name;
@property (nonatomic, copy, nullable, readwrite) NSString  *localizedName;
@property (nonatomic, copy, nullable, readwrite) NSString  *localizationLanguage;
@property (nonatomic, assign, readwrite)         NSInteger  localizationSource;
@property (nonatomic, assign, readwrite, getter=isLocalizationReference) BOOL localizationReference;
@property (nonatomic, copy, nullable, readwrite) NSString  *groupName;
@property (nonatomic, assign, readwrite)         NSInteger  variantCount;
@property (nonatomic, assign, readwrite)         NSInteger  cheatCount;
@property (nonatomic, copy, nullable, readwrite) NSString  *developer;
@property (nonatomic, copy, nullable, readwrite) NSString  *publisher;
@property (nonatomic, assign, readwrite)         NSInteger  releaseYear;
@property (nonatomic, assign, readwrite)         NSInteger  releaseMonth;
@property (nonatomic, copy, nullable, readwrite) NSString  *genre;
@property (nonatomic, copy, nullable, readwrite) NSString  *region;
@property (nonatomic, copy, nullable, readwrite) NSString  *franchise;
@property (nonatomic, copy, nullable, readwrite) NSString  *gameDescription;
@property (nonatomic, copy, nullable, readwrite) NSString  *serial;
@property (nonatomic, assign, readwrite)         NSInteger  maxUsers;
@property (nonatomic, copy, nullable, readwrite) NSString  *romName;
@property (nonatomic, copy, nullable, readwrite) NSString  *crc32;
@property (nonatomic, copy, nullable, readwrite) NSString  *md5;
@property (nonatomic, copy, nullable, readwrite) NSString  *sha1;
@property (nonatomic, assign, readwrite)         NSInteger  fileSize;
@end

@implementation RAGameEntry
@end

// ---------------------------------------------------------------------------
// MARK: - RARDBManager (Private)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// MARK: - RARDBManager Implementation
// ---------------------------------------------------------------------------

@implementation RAGameRDBManager {
    NSString        *d_dbPath;
    sqlite3         *d_db;
    // A language pack attached as `lang` (game_name table); nil = English only.
    BOOL             d_hasLocalization;
    NSString        *d_languagePackPath;
    NSString        *d_languagePackLanguage;

    // All SQLite work runs on this serial queue for thread safety
    dispatch_queue_t d_dbQueue;
}

// MARK: Initialization

+ (instancetype)shared {
    static RAGameRDBManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion {
    NSString *path = [dbPath copy];
    [self p_ensureQueue];
    // Calling it again (after the prebuilt file was replaced) reopens the database.
    dispatch_async(d_dbQueue, ^{
        self->d_dbPath = path;
        [self p_openAndSetup];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

- (void)p_ensureQueue {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        self->d_dbQueue = dispatch_queue_create("com.retrogame.rardbs", DISPATCH_QUEUE_SERIAL);
    });
}

- (void)setLanguagePackPath:(nullable NSString *)path completion:(nullable void (^)(void))completion {
    NSString *next = [path copy];
    [self p_ensureQueue];
    dispatch_async(d_dbQueue, ^{
        self->d_languagePackPath = next;
        if (self->d_db) {
            [self p_attachLanguagePack];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

/// (Re)attaches d_languagePackPath as `lang`, replacing any attached pack.
/// Runs on d_dbQueue with the database open.
- (void)p_attachLanguagePack {
    if (d_hasLocalization) {
        sqlite3_exec(d_db, "DETACH DATABASE lang;", NULL, NULL, NULL);
        d_hasLocalization = NO;
    }
    d_languagePackLanguage = nil;
    NSString *path = d_languagePackPath;
    if (path.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }
    NSString *uri = [[[NSURL fileURLWithPath:path] absoluteString] stringByAppendingString:@"?mode=ro&immutable=1"];
    NSString *escaped = [uri stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
    NSString *sql = [NSString stringWithFormat:@"ATTACH DATABASE '%@' AS lang;", escaped];
    if (sqlite3_exec(d_db, sql.UTF8String, NULL, NULL, NULL) != SQLITE_OK) {
        RETROGO_LOGE(DATABASE, "Failed to attach language pack: %{public}s", sqlite3_errmsg(d_db));
        return;
    }
    NSString *language = RALanguagePackLanguage(d_db, "lang");
    if (!language) {
        sqlite3_exec(d_db, "DETACH DATABASE lang;", NULL, NULL, NULL);
        return;
    }
    sqlite3_exec(d_db, "PRAGMA lang.cache_size=-2048;", NULL, NULL, NULL);
    sqlite3_exec(d_db, "PRAGMA lang.mmap_size=67108864;", NULL, NULL, NULL);
    d_hasLocalization = YES;
    d_languagePackLanguage = language;
    RETROGO_LOGI(DATABASE, "Attached %{public}@ language pack to the game database", language);
}

- (void)dealloc {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
}

- (NSInteger)currentDBVersion {
    return 4;
}

// MARK: Platform queries

- (NSArray<RAPlatformItem *> *)allPlatforms {
    __block NSMutableArray<RAPlatformItem *> *result = [NSMutableArray array];
    dispatch_sync(d_dbQueue, ^{
        const char *sql =
            "SELECT id, rdb_name, display_name, manufacturer, game_count, group_count "
            "FROM platform "
            "ORDER BY display_name COLLATE NOCASE ASC;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                RAPlatformItem *item = [self p_platformItemFromStmt:stmt];
                [result addObject:item];
            }
        }
        sqlite3_finalize(stmt);
    });
    return [result copy];
}

// MARK: Offline export (DEBUG)

#if DEBUG
- (void)exportCombinedDatabaseToPath:(NSString *)destPath
                        fromRdbPaths:(NSArray<NSString *> *)rdbPaths
                          completion:(void (^)(NSInteger totalGames,
                                               NSError * _Nullable error))completion {
    // Use a separate utility queue and its own sqlite handle; never touch the runtime database d_db.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSInteger total = [self p_exportCombinedToPath:destPath
                                              rdbPaths:rdbPaths
                                                 error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(total, error);
        });
    });
}
#endif

// MARK: Paged queries

- (void)fetchGamesForPlatformId:(NSInteger)platformId
                         offset:(NSInteger)offset
                          limit:(NSInteger)limit
               knownTotalCount:(NSInteger)knownTotalCount
                     completion:(void (^)(NSArray<RAGameEntry *> *games,
                                          NSInteger totalCount,
                                          NSError * _Nullable error))completion {
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSMutableArray<RAGameEntry *> *games = [NSMutableArray array];

        // 1. Total: when knownTotalCount > 0 the caller provides it, saving a COUNT(*) query.
        NSInteger totalCount = knownTotalCount;
        if (totalCount <= 0) {
            const char *sql = "SELECT COUNT(*) FROM game WHERE platform_id = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    totalCount = (NSInteger)sqlite3_column_int64(stmt, 0);
                }
            } else {
                error = [self p_errorWithCode:RARDBErrorCodeQueryFailed
                                      reason:@"COUNT query prepare failed"];
            }
            sqlite3_finalize(stmt);
        }

        // 2. Paged query
        if (!error) {
            const char *sqlPlain =
                "SELECT id, platform_id, name, developer, publisher, "
                "       release_year, release_month, genre, region, "
                "       franchise, description, serial, max_users, "
                "       rom_name, crc32, md5, sha1, file_size "
                "FROM game "
                "WHERE platform_id = ? "
                "ORDER BY name COLLATE NOCASE ASC "
                "LIMIT ? OFFSET ?;";
            const char *sqlLoc =
                "SELECT g.id, g.platform_id, g.name, g.developer, g.publisher, "
                "       g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
                "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
                "FROM game g "
                "LEFT JOIN lang.game_name l ON l.platform_id = g.platform_id "
                "                          AND l.group_name = g.group_name "
                "WHERE g.platform_id = ? "
                "ORDER BY g.name COLLATE NOCASE ASC "
                "LIMIT ? OFFSET ?;";
            sqlite3_stmt *stmt = NULL;
            const char *sql = d_hasLocalization ? sqlLoc : sqlPlain;
            if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
                sqlite3_bind_int64(stmt, 2, (sqlite3_int64)limit);
                sqlite3_bind_int64(stmt, 3, (sqlite3_int64)offset);
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    RAGameEntry *entry = [self p_gameEntryFromStmt:stmt];
                    [games addObject:entry];
                }
            } else {
                error = [self p_errorWithCode:RARDBErrorCodeQueryFailed
                                      reason:@"fetchGames query prepare failed"];
            }
            sqlite3_finalize(stmt);
        }

        NSArray<RAGameEntry *> *result = [games copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, totalCount, error);
        });
    });
}

// MARK: Grouped paged queries

- (void)fetchGroupsForPlatformId:(NSInteger)platformId
                          offset:(NSInteger)offset
                           limit:(NSInteger)limit
                 knownTotalCount:(NSInteger)knownTotalCount
                      completion:(void (^)(NSArray<RAGameEntry *> *groups,
                                           NSInteger totalCount,
                                           NSError * _Nullable error))completion {
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSMutableArray<RAGameEntry *> *groups = [NSMutableArray array];

        // 1. Total: when knownTotalCount > 0 the caller provides it (from RAPlatformItem.groupCount),
        //    saving a COUNT(*).
        NSInteger totalCount = knownTotalCount;
        if (totalCount <= 0) {
            const char *sql = "SELECT COUNT(*) FROM game_group WHERE platform_id = ?;";
            sqlite3_stmt *stmt = NULL;
            if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
                if (sqlite3_step(stmt) == SQLITE_ROW) {
                    totalCount = (NSInteger)sqlite3_column_int64(stmt, 0);
                }
            } else {
                error = [self p_errorWithCode:RARDBErrorCodeQueryFailed
                                      reason:@"group COUNT query prepare failed"];
            }
            sqlite3_finalize(stmt);
        }

        // 2. Grouped paging: take the display fields of each group's representative variant; entry.name is the clean group name.
        if (!error) {
            const char *sqlPlain =
                "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size "
                "FROM game_group gg "
                "INNER JOIN game g ON g.id = gg.representative_game_id "
                "WHERE gg.platform_id = ? "
                "ORDER BY gg.group_name COLLATE NOCASE ASC "
                "LIMIT ? OFFSET ?;";
            const char *sqlLoc =
                "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
                "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
                "FROM game_group gg "
                "INNER JOIN game g ON g.id = gg.representative_game_id "
                "LEFT JOIN lang.game_name l ON l.platform_id = gg.platform_id "
                "                          AND l.group_name = gg.group_name "
                "WHERE gg.platform_id = ? "
                "ORDER BY gg.group_name COLLATE NOCASE ASC "
                "LIMIT ? OFFSET ?;";
            sqlite3_stmt *stmt = NULL;
            const char *sql = d_hasLocalization ? sqlLoc : sqlPlain;
            if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
                sqlite3_bind_int64(stmt, 2, (sqlite3_int64)limit);
                sqlite3_bind_int64(stmt, 3, (sqlite3_int64)offset);
                while (sqlite3_step(stmt) == SQLITE_ROW) {
                    [groups addObject:[self p_groupEntryFromStmt:stmt]];
                }
            } else {
                error = [self p_errorWithCode:RARDBErrorCodeQueryFailed
                                      reason:@"fetchGroups query prepare failed"];
            }
            sqlite3_finalize(stmt);
        }

        NSArray<RAGameEntry *> *result = [groups copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, totalCount, error);
        });
    });
}

- (void)fetchVariantsForPlatformId:(NSInteger)platformId
                         groupName:(NSString *)groupName
                        completion:(void (^)(NSArray<RAGameEntry *> *variants,
                                             NSError * _Nullable error))completion {
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSMutableArray<RAGameEntry *> *variants = [NSMutableArray array];

        const char *sqlPlain =
            "SELECT id, platform_id, name, developer, publisher, "
            "       release_year, release_month, genre, region, "
            "       franchise, description, serial, max_users, "
            "       rom_name, crc32, md5, sha1, file_size "
            "FROM game "
            "WHERE platform_id = ? AND group_name = ? "
            "ORDER BY name COLLATE NOCASE ASC;";
        const char *sqlLoc =
            "SELECT g.id, g.platform_id, g.name, g.developer, g.publisher, "
            "       g.release_year, g.release_month, g.genre, g.region, "
            "       g.franchise, g.description, g.serial, g.max_users, "
            "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
            "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
            "FROM game g "
            "LEFT JOIN lang.game_name l ON l.platform_id = g.platform_id "
            "                          AND l.group_name = g.group_name "
            "WHERE g.platform_id = ? AND g.group_name = ? "
            "ORDER BY g.name COLLATE NOCASE ASC;";
        sqlite3_stmt *stmt = NULL;
        const char *sql = d_hasLocalization ? sqlLoc : sqlPlain;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
            sqlite3_bind_text(stmt, 2, groupName.UTF8String, -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                RAGameEntry *entry = [self p_gameEntryFromStmt:stmt];
                // Variant rows are concrete game records, but the UI still needs
                // the original group key to append only the RDB variant suffix to
                // a localized group name.
                entry.groupName = groupName;
                [variants addObject:entry];
            }
        } else {
            error = [self p_errorWithCode:RARDBErrorCodeQueryFailed
                                  reason:@"fetchVariants query prepare failed"];
        }
        sqlite3_finalize(stmt);

        NSArray<RAGameEntry *> *result = [variants copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, error);
        });
    });
}

// MARK: Fuzzy search

- (void)searchGamesWithKeyword:(NSString *)keyword
                    platformId:(NSInteger)platformId
                    completion:(void (^)(NSArray<RAGameEntry *> *games,
                                         NSError * _Nullable error))completion {
    // Validate parameters on the main thread up front
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        completion(@[], nil);
        return;
    }

    dispatch_async(d_dbQueue, ^{
        NSString *ftsQuery = [self p_buildFTSQuery:trimmed];
        NSMutableArray<RAGameEntry *> *games = [NSMutableArray array];
        NSMutableSet<NSString *> *seenGroupKeys = [NSMutableSet set];
        NSError *error = nil;

        // Search hits are variant rows, but results are folded into groups: first aggregate the FTS hits by group,
        // take each group's best rank, then join back to game_group for the representative variant, sorted by best rank.
        const char *sql;
        if (platformId == -1) {
            sql = d_hasLocalization ?
                "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
                "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
                "FROM game_group gg "
                "INNER JOIN game g ON g.id = gg.representative_game_id "
                "LEFT JOIN lang.game_name l ON l.platform_id = gg.platform_id "
                "                          AND l.group_name = gg.group_name "
                "INNER JOIN ( "
                "   SELECT gg2.id AS gid, MIN(fts.rank) AS r "
                "   FROM game_fts fts "
                "   INNER JOIN game gm ON gm.id = fts.game_id "
                "   INNER JOIN game_group gg2 ON gg2.platform_id = gm.platform_id "
                "                            AND gg2.group_name  = gm.group_name "
                "   WHERE game_fts MATCH ? "
                "   GROUP BY gg2.id "
                ") m ON m.gid = gg.id "
                "ORDER BY m.r "
                "LIMIT 100;" :
                "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size "
                "FROM game_group gg "
                "INNER JOIN game g ON g.id = gg.representative_game_id "
                "INNER JOIN ( "
                "   SELECT gg2.id AS gid, MIN(fts.rank) AS r "
                "   FROM game_fts fts "
                "   INNER JOIN game gm ON gm.id = fts.game_id "
                "   INNER JOIN game_group gg2 ON gg2.platform_id = gm.platform_id "
                "                            AND gg2.group_name  = gm.group_name "
                "   WHERE game_fts MATCH ? "
                "   GROUP BY gg2.id "
                ") m ON m.gid = gg.id "
                "ORDER BY m.r "
                "LIMIT 100;";
        } else {
            sql = d_hasLocalization ?
                "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
                "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
                "FROM game_group gg "
                "INNER JOIN game g ON g.id = gg.representative_game_id "
                "LEFT JOIN lang.game_name l ON l.platform_id = gg.platform_id "
                "                          AND l.group_name = gg.group_name "
                "INNER JOIN ( "
                "   SELECT gg2.id AS gid, MIN(fts.rank) AS r "
                "   FROM game_fts fts "
                "   INNER JOIN game gm ON gm.id = fts.game_id "
                "   INNER JOIN game_group gg2 ON gg2.platform_id = gm.platform_id "
                "                            AND gg2.group_name  = gm.group_name "
                "   WHERE game_fts MATCH ? AND gm.platform_id = ? "
                "   GROUP BY gg2.id "
                ") m ON m.gid = gg.id "
                "ORDER BY m.r "
                "LIMIT 100;" :
                "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size "
                "FROM game_group gg "
                "INNER JOIN game g ON g.id = gg.representative_game_id "
                "INNER JOIN ( "
                "   SELECT gg2.id AS gid, MIN(fts.rank) AS r "
                "   FROM game_fts fts "
                "   INNER JOIN game gm ON gm.id = fts.game_id "
                "   INNER JOIN game_group gg2 ON gg2.platform_id = gm.platform_id "
                "                            AND gg2.group_name  = gm.group_name "
                "   WHERE game_fts MATCH ? AND gm.platform_id = ? "
                "   GROUP BY gg2.id "
                ") m ON m.gid = gg.id "
                "ORDER BY m.r "
                "LIMIT 100;";
        }

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, ftsQuery.UTF8String, -1, SQLITE_TRANSIENT);
            if (platformId != -1) {
                sqlite3_bind_int64(stmt, 2, (sqlite3_int64)platformId);
            }
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                RAGameEntry *entry = [self p_groupEntryFromStmt:stmt];
                [games addObject:entry];
                [seenGroupKeys addObject:[NSString stringWithFormat:@"%ld|%@",
                                          (long)entry.platformId, entry.groupName ?: @""]];
            }
        } else {
            error = [self p_errorWithCode:RARDBErrorCodeQueryFailed
                                  reason:@"searchGames FTS query prepare failed"];
        }
        sqlite3_finalize(stmt);

        if (!error && d_hasLocalization && games.count < 100) {
            NSString *norm = p_locNorm(trimmed);
            if (norm.length > 0) {
                NSString *pattern = [NSString stringWithFormat:@"%%%@%%", norm];
                const char *locSQLAll =
                    "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                    "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                    "       g.franchise, g.description, g.serial, g.max_users, "
                    "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
                    "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
                    "FROM lang.game_name l "
                    "INNER JOIN game_group gg ON gg.platform_id = l.platform_id AND gg.group_name = l.group_name "
                    "INNER JOIN game g ON g.id = gg.representative_game_id "
                    "WHERE l.name_norm LIKE ? "
                    "ORDER BY l.name COLLATE NOCASE ASC LIMIT ?;";
                const char *locSQLPlatform =
                    "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                    "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                    "       g.franchise, g.description, g.serial, g.max_users, "
                    "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
                    "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
                    "FROM lang.game_name l "
                    "INNER JOIN game_group gg ON gg.platform_id = l.platform_id AND gg.group_name = l.group_name "
                    "INNER JOIN game g ON g.id = gg.representative_game_id "
                    "WHERE l.platform_id = ? AND l.name_norm LIKE ? "
                    "ORDER BY l.name COLLATE NOCASE ASC LIMIT ?;";
                sqlite3_stmt *locStmt = NULL;
                const char *locSQL = platformId == -1 ? locSQLAll : locSQLPlatform;
                if (sqlite3_prepare_v2(d_db, locSQL, -1, &locStmt, NULL) == SQLITE_OK) {
                    NSInteger remaining = 100 - games.count;
                    if (platformId == -1) {
                        sqlite3_bind_text(locStmt, 1, pattern.UTF8String, -1, SQLITE_TRANSIENT);
                        sqlite3_bind_int64(locStmt, 2, (sqlite3_int64)remaining);
                    } else {
                        sqlite3_bind_int64(locStmt, 1, (sqlite3_int64)platformId);
                        sqlite3_bind_text(locStmt, 2, pattern.UTF8String, -1, SQLITE_TRANSIENT);
                        sqlite3_bind_int64(locStmt, 3, (sqlite3_int64)remaining);
                    }
                    while (sqlite3_step(locStmt) == SQLITE_ROW && games.count < 100) {
                        RAGameEntry *entry = [self p_groupEntryFromStmt:locStmt];
                        NSString *key = [NSString stringWithFormat:@"%ld|%@",
                                         (long)entry.platformId, entry.groupName ?: @""];
                        if (![seenGroupKeys containsObject:key]) {
                            [games addObject:entry];
                            [seenGroupKeys addObject:key];
                        }
                    }
                }
                sqlite3_finalize(locStmt);
            }
        }

        NSArray<RAGameEntry *> *result = [games copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, error);
        });
    });
}

// MARK: Exact CRC lookup

- (nullable RAGameEntry *)findGameByCRC32:(NSString *)crc32 {
    RAGameEntry *entry = nil;
    [self lookupGameByCRC32:crc32 game:&entry error:NULL];
    return entry;
}

- (BOOL)lookupGameByCRC32:(NSString *)crc32
                     game:(RAGameEntry * _Nullable * _Nonnull)game
                    error:(NSError **)error {
    *game = nil;
    if (!d_dbQueue) {
        if (error) {
            *error = [self p_errorWithCode:RARDBErrorCodeOpenFailed reason:@"game database is not initialized"];
        }
        return NO;
    }
    __block RAGameEntry *entry = nil;
    __block NSError *failure = nil;
    dispatch_sync(d_dbQueue, ^{
        if (!d_db) {
            failure = [self p_errorWithCode:RARDBErrorCodeOpenFailed reason:@"game database is not open"];
            return;
        }
        const char *sqlPlain =
            "SELECT id, platform_id, name, developer, publisher, "
            "       release_year, release_month, genre, region, "
            "       franchise, description, serial, max_users, "
            "       rom_name, crc32, md5, sha1, file_size, group_name "
            "FROM game "
            "WHERE crc32 = ? "
            "LIMIT 1;";
        const char *sqlLoc =
            "SELECT g.id, g.platform_id, g.name, g.developer, g.publisher, "
            "       g.release_year, g.release_month, g.genre, g.region, "
            "       g.franchise, g.description, g.serial, g.max_users, "
            "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, g.group_name, "
            "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
            "FROM game g "
            "LEFT JOIN lang.game_name l ON l.platform_id = g.platform_id "
            "                          AND l.group_name = g.group_name "
            "WHERE g.crc32 = ? "
            "LIMIT 1;";
        sqlite3_stmt *stmt = NULL;
        const char *sql = d_hasLocalization ? sqlLoc : sqlPlain;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            RETROGO_LOGE(DATABASE, "CRC32 lookup prepare failed: %{public}s", sqlite3_errmsg(d_db));
            failure = [self p_errorWithCode:RARDBErrorCodeQueryFailed reason:@"CRC32 lookup prepare failed"];
            return;
        }
        sqlite3_bind_text(stmt, 1, crc32.UTF8String, -1, SQLITE_TRANSIENT);
        int rc = sqlite3_step(stmt);
        if (rc == SQLITE_ROW) {
            entry = [self p_gameEntryFromStmt:stmt];
        } else if (rc != SQLITE_DONE) {
            RETROGO_LOGE(DATABASE, "CRC32 lookup step failed (%d): %{public}s", rc, sqlite3_errmsg(d_db));
            failure = [self p_errorWithCode:RARDBErrorCodeQueryFailed reason:@"CRC32 lookup failed"];
        }
        sqlite3_finalize(stmt);
    });
    if (failure) {
        if (error) { *error = failure; }
        return NO;
    }
    *game = entry;
    return YES;
}

// ===========================================================================
// MARK: - Private
// ===========================================================================

/// Opens the prebuilt game database **read-only + immutable** (called on dbQueue).
///
/// Convention: the sqlite in the App Store build is always a finished, offline prebuilt database (see exportCombinedDatabase…),
/// only queried at runtime, never written. So here:
///   - open with SQLITE_OPEN_READONLY: never create the file, never build tables/migrate, never write user_version;
///   - use the URI parameter immutable=1: tells SQLite the file never changes, so it **neither creates nor uses
///     -wal/-shm sidecars**, whatever the file's journal mode (the standard way to open a shipped read-only database,
///     which also rules out "opening an old WAL-mode database read-only spawns -wal/-shm");
///   - don't enable WAL / foreign keys (both only serve writes).
/// Building the DDL and writing user_version both happen in the offline export stage.
- (BOOL)p_openAndSetup {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
    d_hasLocalization = NO;
    d_languagePackLanguage = nil;
    // Use NSURL to build a properly percent-escaped file URI (required when the path has spaces, like "Application Support"),
    // then append immutable=1. Takes effect together with SQLITE_OPEN_URI.
    NSString *uri = [[[NSURL fileURLWithPath:d_dbPath] absoluteString]
                     stringByAppendingString:@"?immutable=1"];
    int rc = sqlite3_open_v2(uri.UTF8String, &d_db,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL);
    if (rc != SQLITE_OK) {
        // Normally OnDemandResourceLoader copies the prebuilt database into place before calling initialize;
        // getting here usually means the copy failed / the file is missing, so clear the handle and queries safely return empty results.
        RETROGO_LOGE(DATABASE, "Failed to open game database read-only (%d): %@", rc, d_dbPath);
        if (d_db) {
            sqlite3_close(d_db);
            d_db = NULL;
        }
        return NO;
    }

    // Read-mostly packaged databases: keep temporary work in memory and let
    // SQLite mmap read-only pages when the OS allows it.
    sqlite3_exec(d_db, "PRAGMA temp_store=MEMORY;", NULL, NULL, NULL);
    sqlite3_exec(d_db, "PRAGMA cache_size=-8192;", NULL, NULL, NULL);
    sqlite3_exec(d_db, "PRAGMA mmap_size=268435456;", NULL, NULL, NULL);

    // Check the version once in the log only, to catch a prebuilt database that doesn't match the code's schema; nothing is written.
    NSInteger storedVersion = [self p_readUserVersion];
    if (storedVersion != self.currentDBVersion) {
        RETROGO_LOGF(DATABASE, "Prebuilt game database user_version %ld does not match expected %ld; re-export the prebuilt database",
              (long)storedVersion, (long)self.currentDBVersion);
    }

    [self p_attachLanguagePack];
    sqlite3_exec(d_db, "PRAGMA query_only=ON;", NULL, NULL, NULL);
    return YES;
}

/// Reads user_version from the SQLite file header (0 for a new file)
- (NSInteger)p_readUserVersion {
    NSInteger version = 0;
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(d_db, "PRAGMA user_version;", -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            version = (NSInteger)sqlite3_column_int64(stmt, 0);
        }
    }
    sqlite3_finalize(stmt);
    return version;
}

/// Does the actual import (called on dbQueue) and returns the number of entries imported.
/// db can be any writable SQLite handle: the live import passes d_db,
/// the DEBUG offline export passes its own temporary handle so the runtime database stays clean.
- (NSInteger)p_doImportRdbAtPath:(NSString *)rdbPath
                         rdbName:(NSString *)rdbName
                        stableId:(NSInteger)stableId
                              db:(sqlite3 *)db
                           error:(NSError **)outError {
    // --- Parse displayName / manufacturer ---
    NSString *displayName  = rdbName;
    NSString *manufacturer = nil;
    NSRange range = [rdbName rangeOfString:@" - "];
    if (range.location != NSNotFound) {
        manufacturer = [rdbName substringToIndex:range.location];
        displayName  = [rdbName substringFromIndex:range.location + range.length];
    }

    // --- Open the rdb ---
    libretrodb_t        *rdb    = libretrodb_new();
    libretrodb_cursor_t *cursor = libretrodb_cursor_new();
    if (!rdb || !cursor) {
        if (rdb)    libretrodb_free(rdb);
        if (cursor) libretrodb_cursor_free(cursor);
        if (outError) *outError = [self p_errorWithCode:RARDBErrorCodeImportFailed
                                                 reason:@"libretrodb alloc failed"];
        return 0;
    }

    if (libretrodb_open(rdbPath.UTF8String, rdb, false) != 0) {
        libretrodb_cursor_free(cursor);
        libretrodb_free(rdb);
        if (outError) *outError = [self p_errorWithCode:RARDBErrorCodeImportFailed
                                                 reason:[NSString stringWithFormat:
                                                         @"libretrodb_open failed: %@", rdbPath]];
        return 0;
    }

    if (libretrodb_cursor_open(rdb, cursor, NULL) != 0) {
        libretrodb_cursor_close(cursor);
        libretrodb_cursor_free(cursor);
        libretrodb_close(rdb);
        libretrodb_free(rdb);
        if (outError) *outError = [self p_errorWithCode:RARDBErrorCodeImportFailed
                                                 reason:@"libretrodb_cursor_open failed"];
        return 0;
    }

    // --- Begin transaction ---
    sqlite3_exec(db, "BEGIN TRANSACTION;", NULL, NULL, NULL);

    // --- Insert the platform ---
    // When stableId > 0, set the id explicitly so platform_id stays stable across versions.
    NSInteger platformId = 0;
    {
        const char *sql = (stableId > 0)
            ? "INSERT INTO platform(id, rdb_name, display_name, manufacturer, game_count, imported_at) "
              "VALUES(?, ?, ?, ?, 0, ?);"
            : "INSERT INTO platform(rdb_name, display_name, manufacturer, game_count, imported_at) "
              "VALUES(?, ?, ?, 0, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            int col = 1;
            if (stableId > 0) {
                sqlite3_bind_int64(stmt, col++, (sqlite3_int64)stableId);
            }
            sqlite3_bind_text(stmt, col++, rdbName.UTF8String,     -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, col++, displayName.UTF8String, -1, SQLITE_TRANSIENT);
            if (manufacturer) {
                sqlite3_bind_text(stmt, col++, manufacturer.UTF8String, -1, SQLITE_TRANSIENT);
            } else {
                sqlite3_bind_null(stmt, col++);
            }
            sqlite3_bind_int64(stmt, col, (sqlite3_int64)[[NSDate date] timeIntervalSince1970]);
            sqlite3_step(stmt);
            platformId = (stableId > 0) ? stableId : (NSInteger)sqlite3_last_insert_rowid(db);
        }
        sqlite3_finalize(stmt);
    }

    if (platformId == 0) {
        sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
        libretrodb_cursor_close(cursor);
        libretrodb_cursor_free(cursor);
        libretrodb_close(rdb);
        libretrodb_free(rdb);
        if (outError) *outError = [self p_errorWithCode:RARDBErrorCodeImportFailed
                                                 reason:@"Insert platform failed"];
        return 0;
    }

    // --- Prepare the game / fts insert statements ---
    const char *gameSQL =
        "INSERT INTO game("
        "  platform_id, name, group_name, developer, publisher, "
        "  release_year, release_month, genre, region, "
        "  franchise, description, serial, max_users, "
        "  rom_name, crc32, md5, sha1, file_size"
        ") VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);";
    const char *ftsSQL =
        "INSERT INTO game_fts(name, developer, publisher, game_id) "
        "VALUES(?,?,?,?);";

    sqlite3_stmt *gameStmt = NULL;
    sqlite3_stmt *ftsStmt  = NULL;
    sqlite3_prepare_v2(db, gameSQL, -1, &gameStmt, NULL);
    sqlite3_prepare_v2(db, ftsSQL,  -1, &ftsStmt,  NULL);

    // --- Read the rdb entry by entry and write ---
    NSInteger count = 0;
    struct rmsgpack_dom_value item;

    while (libretrodb_cursor_read_item(cursor, &item) == 0) {
        if (item.type == RDT_MAP) {
            // Extract the fields from the map
            NSString *name         = nil;
            NSString *developer    = nil;
            NSString *publisher    = nil;
            NSString *genre        = nil;
            NSString *region       = nil;
            NSString *franchise    = nil;
            NSString *description  = nil;
            NSString *serial       = nil;
            NSString *romName      = nil;
            NSString *crc32        = nil;
            NSString *md5          = nil;
            NSString *sha1         = nil;
            NSInteger releaseYear  = 0;
            NSInteger releaseMonth = 0;
            NSInteger maxUsers     = 0;
            NSInteger fileSize     = 0;

            for (uint32_t i = 0; i < item.val.map.len; i++) {
                struct rmsgpack_dom_value *key = &item.val.map.items[i].key;
                struct rmsgpack_dom_value *val = &item.val.map.items[i].value;
                if (!key || !val) continue;
                if (key->type != RDT_STRING) continue;

                const char *k = key->val.string.buff;

                if (strcmp(k, "name") == 0 && val->type == RDT_STRING) {
                    name = p_str(val);
                } else if (strcmp(k, "developer") == 0 && val->type == RDT_STRING) {
                    developer = p_str(val);
                } else if (strcmp(k, "publisher") == 0 && val->type == RDT_STRING) {
                    publisher = p_str(val);
                } else if (strcmp(k, "genre") == 0 && val->type == RDT_STRING) {
                    genre = p_str(val);
                } else if (strcmp(k, "region") == 0 && val->type == RDT_STRING) {
                    region = p_str(val);
                } else if (strcmp(k, "franchise") == 0 && val->type == RDT_STRING) {
                    franchise = p_str(val);
                } else if (strcmp(k, "description") == 0 && val->type == RDT_STRING) {
                    description = p_str(val);
                } else if (strcmp(k, "serial") == 0 && val->type == RDT_STRING) {
                    serial = p_str(val);
                } else if (strcmp(k, "rom_name") == 0 && val->type == RDT_STRING) {
                    romName = p_str(val);
                } else if (strcmp(k, "releaseyear") == 0 && val->type == RDT_UINT) {
                    releaseYear = (NSInteger)val->val.uint_;
                } else if (strcmp(k, "releasemonth") == 0 && val->type == RDT_UINT) {
                    releaseMonth = (NSInteger)val->val.uint_;
                } else if (strcmp(k, "users") == 0 && val->type == RDT_UINT) {
                    maxUsers = (NSInteger)val->val.uint_;
                } else if (strcmp(k, "size") == 0 && val->type == RDT_UINT) {
                    fileSize = (NSInteger)val->val.uint_;
                } else if (strcmp(k, "crc") == 0 && val->type == RDT_BINARY) {
                    crc32 = p_crc32HexString(val);
                } else if (strcmp(k, "md5") == 0 && val->type == RDT_BINARY) {
                    md5 = p_binaryHexString(val);
                } else if (strcmp(k, "sha1") == 0 && val->type == RDT_BINARY) {
                    sha1 = p_binaryHexString(val);
                }
            }

            // name is required; skip entries without one
            if (name.length > 0 && gameStmt && ftsStmt) {
                // Insert into game
                sqlite3_reset(gameStmt);
                sqlite3_bind_int64(gameStmt,  1, (sqlite3_int64)platformId);
                p_bindText(gameStmt,  2, name);
                p_bindText(gameStmt,  3, p_groupName(name));
                p_bindText(gameStmt,  4, developer);
                p_bindText(gameStmt,  5, publisher);
                p_bindInt64(gameStmt, 6, releaseYear);
                p_bindInt64(gameStmt, 7, releaseMonth);
                p_bindText(gameStmt,  8, genre);
                p_bindText(gameStmt,  9, region);
                p_bindText(gameStmt, 10, franchise);
                p_bindText(gameStmt, 11, description);
                p_bindText(gameStmt, 12, serial);
                p_bindInt64(gameStmt,13, maxUsers);
                p_bindText(gameStmt, 14, romName);
                p_bindText(gameStmt, 15, crc32);
                p_bindText(gameStmt, 16, md5);
                p_bindText(gameStmt, 17, sha1);
                p_bindInt64(gameStmt,18, fileSize);
                sqlite3_step(gameStmt);

                NSInteger gameId = (NSInteger)sqlite3_last_insert_rowid(db);

                // Insert into game_fts
                sqlite3_reset(ftsStmt);
                p_bindText(ftsStmt, 1, name);
                p_bindText(ftsStmt, 2, developer);
                p_bindText(ftsStmt, 3, publisher);
                sqlite3_bind_int64(ftsStmt, 4, (sqlite3_int64)gameId);
                sqlite3_step(ftsStmt);

                count++;
            }
        }

        rmsgpack_dom_value_free(&item);
    }

    sqlite3_finalize(gameStmt);
    sqlite3_finalize(ftsStmt);

    // Update game_count
    {
        const char *sql = "UPDATE platform SET game_count = ? WHERE id = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (sqlite3_int64)count);
            sqlite3_bind_int64(stmt, 2, (sqlite3_int64)platformId);
            sqlite3_step(stmt);
        }
        sqlite3_finalize(stmt);
    }

    sqlite3_exec(db, "COMMIT;", NULL, NULL, NULL);

    // Close the rdb
    libretrodb_cursor_close(cursor);
    libretrodb_cursor_free(cursor);
    libretrodb_close(rdb);
    libretrodb_free(rdb);

    return count;
}

#if DEBUG
/// DEBUG offline export: builds a finished merged database from a set of .rdb files.
/// The output is identical to the import on the device (same schema, same user_version, FTS5 already built);
/// it ends with a checkpoint + WAL off + VACUUM and is written as a single .db file ready to bundle.
- (NSInteger)p_exportCombinedToPath:(NSString *)destPath
                           rdbPaths:(NSArray<NSString *> *)rdbPaths
                              error:(NSError **)outError {
    NSFileManager *fm = NSFileManager.defaultManager;
    // Remove the old output and its WAL/SHM sidecars to start from scratch
    for (NSString *suffix in @[@"", @"-wal", @"-shm"]) {
        [fm removeItemAtPath:[destPath stringByAppendingString:suffix] error:NULL];
    }

    sqlite3 *db = NULL;
    if (sqlite3_open(destPath.UTF8String, &db) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        if (outError) *outError = [self p_errorWithCode:RARDBErrorCodeOpenFailed
                                                 reason:@"export: open failed"];
        return 0;
    }

    // Only the export (build) stage uses WAL for faster bulk writes and foreign keys for data integrity;
    // the wrap-up checkpoints and switches back to the DELETE journal, so the final output is a clean single file.
    // (Note: the prebuilt database is opened read-only at runtime and uses neither.)
    sqlite3_exec(db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL);

    // Build tables / indexes / FTS / the group table. Runtime is read-only and never builds tables, so the DDL only runs in this export stage.
    const char *ddls[] = {
        kDDL_Platform,
        kDDL_Game,
        kDDL_GameGroup,
        kDDL_GameIndexPlatform,
        kDDL_GameIndexCRC32,
        kDDL_GameIndexName,
        kDDL_GameIndexGroup,
        kDDL_GroupIndexPlatform,
        kDDL_GameFTS,
        NULL
    };
    for (int i = 0; ddls[i] != NULL; i++) {
        char *errMsg = NULL;
        if (sqlite3_exec(db, ddls[i], NULL, NULL, &errMsg) != SQLITE_OK) {
            NSString *reason = [NSString stringWithFormat:@"export DDL failed: %s",
                                errMsg ? errMsg : "unknown"];
            sqlite3_free(errMsg);
            sqlite3_close(db);
            if (outError) *outError = [self p_errorWithCode:RARDBErrorCodeCreateFailed
                                                     reason:reason];
            return 0;
        }
    }

    // Align user_version so opening at runtime skips the DDL
    NSString *uv = [NSString stringWithFormat:@"PRAGMA user_version = %ld;",
                    (long)self.currentDBVersion];
    sqlite3_exec(db, uv.UTF8String, NULL, NULL, NULL);

    // rdb_name → stable platform_id. Ids of released versions never change; new platforms count up from max+1.
    // To add a platform, just append it here; never change existing entries.
    NSDictionary<NSString *, NSNumber *> *stablePlatformIds = @{
        @"DOS":                                             @1,
        @"Nintendo - Family Computer Disk System":          @2,
        @"Nintendo - Game Boy":                             @3,
        @"Nintendo - Game Boy Advance":                     @4,
        @"Nintendo - Game Boy Color":                       @5,
        @"MAME":                                            @6,
        @"Nintendo - Nintendo 64":                          @7,
        @"Nintendo - Nintendo DS":                          @8,
        @"Nintendo - Nintendo Entertainment System":        @9,
        @"Sony - PlayStation":                              @10,
        @"Sony - PlayStation Portable":                     @11,
        @"Sega - Saturn":                                   @12,
        @"Nintendo - Super Nintendo Entertainment System":  @13,
        @"Sega - 32X":                                      @14,
        @"Sega - Game Gear":                                @15,
        @"Sega - Master System - Mark III":                 @16,
        @"Sega - Mega Drive - Genesis":                     @17,
        @"Sega - Mega-CD - Sega CD":                        @18,
        @"Sega - PICO":                                     @19,
        @"Sega - Dreamcast":                                @20,
        @"Sega - Naomi":                                    @21,
        @"Sega - Naomi 2":                                  @22,
        @"Atomiswave":                                      @23,
        @"Sega - SG-1000":                                  @24,
    };

    // Import each .rdb (reusing exactly the same import core as the live path)
    NSInteger total = 0;
    for (NSString *rdbPath in rdbPaths) {
        NSString *rdbName = [[rdbPath lastPathComponent] stringByDeletingPathExtension];
        NSNumber *sid = stablePlatformIds[rdbName];
        NSError *impErr = nil;
        NSInteger c = [self p_doImportRdbAtPath:rdbPath rdbName:rdbName
                                      stableId:sid ? sid.integerValue : 0
                                            db:db error:&impErr];
        if (impErr) {
            RETROGO_LOGE(DATABASE, "Debug export: failed to import %{public}@: %@", rdbName, impErr.localizedDescription);
        } else {
            RETROGO_LOGD(DATABASE, "Debug export: imported %{public}@ (id=%{public}@): %ld entries", rdbName, sid ?: @"auto", (long)c);
            total += c;
        }
    }

    // ── Materialized group table ──────────────────────────────────────────
    // Each (platform_id, group_name) forms one group:
    //   representative_game_id: the group's representative variant, by region priority USA>World>Europe>Japan>other,
    //                           smallest id on ties; used for list covers and metadata.
    //   variant_count: number of variants in the group.
    {
        // A single pass with window functions (sorting game only once) avoids the
        // O(groups × rows) blowup of a per-group correlated subquery:
        //   ROW_NUMBER orders by "region priority + id", so rn=1 is the representative variant;
        //   COUNT(*) OVER (no ORDER BY) gives the whole group's variant count.
        const char *sql =
            "INSERT INTO game_group(platform_id, group_name, representative_game_id, variant_count) "
            "SELECT platform_id, group_name, id, cnt FROM ( "
            "  SELECT id, platform_id, group_name, "
            "         COUNT(*) OVER (PARTITION BY platform_id, group_name) AS cnt, "
            "         ROW_NUMBER() OVER (PARTITION BY platform_id, group_name "
            "                            ORDER BY (CASE region "
            "                                        WHEN 'USA' THEN 0 WHEN 'World' THEN 1 "
            "                                        WHEN 'Europe' THEN 2 WHEN 'Japan' THEN 3 "
            "                                        ELSE 4 END), id) AS rn "
            "  FROM game "
            "  WHERE group_name IS NOT NULL "
            ") WHERE rn = 1;";
        char *errMsg = NULL;
        if (sqlite3_exec(db, sql, NULL, NULL, &errMsg) != SQLITE_OK) {
            RETROGO_LOGE(DATABASE, "Debug export: failed to build group table: %{public}s", errMsg ? errMsg : "unknown");
            sqlite3_free(errMsg);
        }
    }

    // Backfill each platform's group_count (number of deduplicated groups, for list paging)
    sqlite3_exec(db,
        "UPDATE platform SET group_count = "
        "  (SELECT COUNT(*) FROM game_group WHERE game_group.platform_id = platform.id);",
        NULL, NULL, NULL);

    // Wrap-up: merge WAL → single file, switch back to the DELETE journal, VACUUM to compact.
    // Order: checkpoint first to fold -wal into the main database, then switch to DELETE mode, then VACUUM.
    sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", NULL, NULL, NULL);
    sqlite3_exec(db, "VACUUM;", NULL, NULL, NULL);

    sqlite3_close(db);

    // Fallback: after switching to DELETE mode and closing, SQLite usually deletes -wal/-shm itself,
    // but -shm can sometimes linger. By now neither sidecar holds any data of its own
    // (-wal has been checkpointed into the main database, -shm is only the WAL index), so delete them explicitly
    // to keep the export a clean single file ready to bundle.
    for (NSString *suffix in @[@"-wal", @"-shm"]) {
        [fm removeItemAtPath:[destPath stringByAppendingString:suffix] error:NULL];
    }

    return total;
}
#endif

// MARK: - Result set conversion

- (RAPlatformItem *)p_platformItemFromStmt:(sqlite3_stmt *)stmt {
    RAPlatformItem *item  = [[RAPlatformItem alloc] init];
    item.platformId       = (NSInteger)sqlite3_column_int64(stmt, 0);
    item.rdbName          = p_colText(stmt, 1) ?: @"";
    item.displayName      = p_colText(stmt, 2) ?: @"";
    item.manufacturer     = p_colText(stmt, 3) ?: @"";
    item.gameCount        = (NSInteger)sqlite3_column_int64(stmt, 4);
    item.groupCount       = (NSInteger)sqlite3_column_int64(stmt, 5);
    return item;
}

- (RAGameEntry *)p_gameEntryFromStmt:(sqlite3_stmt *)stmt {
    RAGameEntry *entry    = [[RAGameEntry alloc] init];
    entry.gameId          = (NSInteger)sqlite3_column_int64(stmt,  0);
    entry.platformId      = (NSInteger)sqlite3_column_int64(stmt,  1);
    entry.name            = p_colText(stmt,  2) ?: @"";
    entry.developer       = p_colText(stmt,  3);
    entry.publisher       = p_colText(stmt,  4);
    entry.releaseYear     = (NSInteger)sqlite3_column_int64(stmt,  5);
    entry.releaseMonth    = (NSInteger)sqlite3_column_int64(stmt,  6);
    entry.genre           = p_colText(stmt,  7);
    entry.region          = p_colText(stmt,  8);
    entry.franchise       = p_colText(stmt,  9);
    entry.gameDescription = p_colText(stmt, 10);
    entry.serial          = p_colText(stmt, 11);
    entry.maxUsers        = (NSInteger)sqlite3_column_int64(stmt, 12);
    entry.romName         = p_colText(stmt, 13);
    entry.crc32           = p_colText(stmt, 14);
    entry.md5             = p_colText(stmt, 15);
    entry.sha1            = p_colText(stmt, 16);
    entry.fileSize        = (NSInteger)sqlite3_column_int64(stmt, 17);
    int columnCount = sqlite3_column_count(stmt);
    if (columnCount == 19 || columnCount >= 21) {
        entry.groupName = p_colText(stmt, 18);
    }
    if (columnCount == 20) {
        entry.localizedName = p_colText(stmt, 18);
        entry.localizationSource = (NSInteger)sqlite3_column_int64(stmt, 19);
        entry.localizationReference = entry.localizationSource == 5;
    } else if (columnCount >= 21) {
        entry.localizedName = p_colText(stmt, 19);
        entry.localizationSource = (NSInteger)sqlite3_column_int64(stmt, 20);
        entry.localizationReference = entry.localizationSource == 5;
    }
    if (entry.localizedName) {
        entry.localizationLanguage = d_languagePackLanguage;
    }
    return entry;
}

/// Group result row → RAGameEntry: gameId/metadata come from the representative variant,
/// name is the clean group name (for list display and cover matching), along with groupName / variantCount.
/// See fetchGroups / the folded search query for the column order.
- (RAGameEntry *)p_groupEntryFromStmt:(sqlite3_stmt *)stmt {
    RAGameEntry *entry    = [[RAGameEntry alloc] init];
    entry.gameId          = (NSInteger)sqlite3_column_int64(stmt,  0);
    entry.platformId      = (NSInteger)sqlite3_column_int64(stmt,  1);
    NSString *group       = p_colText(stmt, 2) ?: @"";
    entry.name            = group;
    entry.groupName       = group;
    entry.variantCount    = (NSInteger)sqlite3_column_int64(stmt,  3);
    entry.developer       = p_colText(stmt,  4);
    entry.publisher       = p_colText(stmt,  5);
    entry.releaseYear     = (NSInteger)sqlite3_column_int64(stmt,  6);
    entry.releaseMonth    = (NSInteger)sqlite3_column_int64(stmt,  7);
    entry.genre           = p_colText(stmt,  8);
    entry.region          = p_colText(stmt,  9);
    entry.franchise       = p_colText(stmt, 10);
    entry.gameDescription = p_colText(stmt, 11);
    entry.serial          = p_colText(stmt, 12);
    entry.maxUsers        = (NSInteger)sqlite3_column_int64(stmt, 13);
    entry.romName         = p_colText(stmt, 14);
    entry.crc32           = p_colText(stmt, 15);
    entry.md5             = p_colText(stmt, 16);
    entry.sha1            = p_colText(stmt, 17);
    entry.fileSize        = (NSInteger)sqlite3_column_int64(stmt, 18);
    if (sqlite3_column_count(stmt) > 20) {
        entry.localizedName = p_colText(stmt, 19);
        entry.localizationSource = (NSInteger)sqlite3_column_int64(stmt, 20);
        entry.localizationReference = entry.localizationSource == 5;
    }
    if (entry.localizedName) {
        entry.localizationLanguage = d_languagePackLanguage;
    }
    return entry;
}

// MARK: - FTS query building

/// "super mario" → "super* mario*" (FTS5 prefix matching)
- (NSString *)p_buildFTSQuery:(NSString *)keyword {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSArray<NSString *> *words = [keyword componentsSeparatedByCharactersInSet:ws];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *word in words) {
        NSString *w = [word stringByTrimmingCharactersInSet:ws];
        // Simple escaping of FTS5 special characters (avoids MATCH syntax errors)
        w = [w stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        if (w.length > 0) {
            [tokens addObject:[w stringByAppendingString:@"*"]];
        }
    }
    return [tokens componentsJoinedByString:@" "];
}

// MARK: - Error building

- (NSError *)p_errorWithCode:(RARDBErrorCode)code reason:(NSString *)reason {
    return [NSError errorWithDomain:kRARDBErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

// ===========================================================================
// MARK: - Static helpers (file-internal)
// ===========================================================================

/// Safely builds an NSString from an rmsgpack_dom_value (RDT_STRING)
static inline NSString * _Nullable p_str(struct rmsgpack_dom_value *val) {
    if (!val || val->type != RDT_STRING || !val->val.string.buff || val->val.string.len == 0)
        return nil;
    return [[NSString alloc] initWithBytes:val->val.string.buff
                                    length:val->val.string.len
                                  encoding:NSUTF8StringEncoding];
}

/// Converts a binary field to a lowercase hex string (shared by md5 / sha1)
static inline NSString * _Nullable p_binaryHexString(struct rmsgpack_dom_value *val) {
    if (!val || val->type != RDT_BINARY || !val->val.binary.buff || val->val.binary.len == 0)
        return nil;
    NSMutableString *hex = [NSMutableString stringWithCapacity:val->val.binary.len * 2];
    unsigned char *bytes = (unsigned char *)val->val.binary.buff;
    for (uint32_t i = 0; i < val->val.binary.len; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return [hex copy];
}

/// Converts a crc binary (4 bytes, stored big-endian) to 8-digit lowercase hex
static inline NSString * _Nullable p_crc32HexString(struct rmsgpack_dom_value *val) {
    if (!val || val->type != RDT_BINARY || !val->val.binary.buff) return nil;
    switch (val->val.binary.len) {
        case 4: {
            // The rdb stores CRC big-endian; CFSwapInt32BigToHost handles the byte order
            uint32_t raw = *(uint32_t *)val->val.binary.buff;
            uint32_t crc = CFSwapInt32BigToHost(raw);
            return [NSString stringWithFormat:@"%08x", crc];
        }
        default:
            return p_binaryHexString(val);
    }
}

/// Safely reads a TEXT column from a sqlite3_stmt (may be NULL)
static inline NSString * _Nullable p_colText(sqlite3_stmt *stmt, int col) {
    const unsigned char *text = sqlite3_column_text(stmt, col);
    return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

/// Binds a nullable TEXT to a sqlite3_stmt (nil → SQL NULL)
static inline void p_bindText(sqlite3_stmt *stmt, int col, NSString * _Nullable val) {
    if (val) {
        sqlite3_bind_text(stmt, col, val.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, col);
    }
}

/// Binds an INTEGER to a sqlite3_stmt (also bound when the value is 0, never as NULL)
static inline void p_bindInt64(sqlite3_stmt *stmt, int col, NSInteger val) {
    sqlite3_bind_int64(stmt, col, (sqlite3_int64)val);
}

static NSString *p_locNorm(NSString *s) {
    return RALanguagePackSearchNorm(s);
}

@end
