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

#include <sqlite3.h>
#include <CoreFoundation/CoreFoundation.h>

#include <libretrodb.h>
#include <rmsgpack_dom.h>

// ---------------------------------------------------------------------------
// MARK: - 内部常量
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
    "  game_count   INTEGER NOT NULL DEFAULT 0,"   // 该平台游戏(变体)总数
    "  group_count  INTEGER NOT NULL DEFAULT 0,"   // 该平台去重分组后的数量(列表分页用)
    "  imported_at  INTEGER NOT NULL"
    ");";

// game 表保存每个 ROM 变体(CRC32/md5/sha1 按变体匹配，绝不可去重)。
// group_name 为「分组键」：取游戏名第一个 ( 或 [ 之前的前缀，导入时算好。
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

// 物化的分组表：每个 (platform_id, group_name) 一行，记录代表变体与变体数。
// 列表/分页直接读这张小表，避免在 5 万行的 game 上现算 GROUP BY。
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

// 支持「按 (platform_id, group_name) 取某组全部变体」的等值查找（BINARY 比较，
// 故索引不加 COLLATE NOCASE，保证 group_name = ? 能命中索引）。
static const char * const kDDL_GameIndexGroup =
    "CREATE INDEX IF NOT EXISTS idx_game_group ON game(platform_id, group_name);";

// 支持分组列表按 group_name 排序分页。
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
// MARK: - 分组键
// ---------------------------------------------------------------------------

/// 由游戏名计算「分组键」：取第一个 '(' 或 '[' 之前的前缀并去除尾随空白。
/// 例：
///   "1 on 1 Government (Japan)"              → "1 on 1 Government"
///   "10 X 10 (Barcrest) (MPU4) (N25 0.3 AD)" → "10 X 10"
///   "005"                                    → "005"
/// 前缀为空(名字以括号开头)时回退为原名，保证分组键非空。
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
    BOOL             d_hasLocalization;

    // 所有 SQLite 操作在此串行队列执行，保证线程安全
    dispatch_queue_t d_dbQueue;
}

// MARK: 初始化

+ (instancetype)shared {
    static RAGameRDBManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion {
    d_dbPath  = [dbPath copy];
    d_dbQueue = dispatch_queue_create("com.retrogame.rardbs", DISPATCH_QUEUE_SERIAL);

    dispatch_async(d_dbQueue, ^{
        [self p_openAndSetup];
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

- (NSInteger)currentDBVersion {
    return 2;
}

// MARK: 平台查询

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

// MARK: 离线导出（DEBUG）

#if DEBUG
- (void)exportCombinedDatabaseToPath:(NSString *)destPath
                        fromRdbPaths:(NSArray<NSString *> *)rdbPaths
                          completion:(void (^)(NSInteger totalGames,
                                               NSError * _Nullable error))completion {
    // 用独立的 utility 队列，使用独立的 sqlite 句柄，不触碰运行库 d_db。
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

// MARK: 分页查询

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

        // 1. 总数：knownTotalCount > 0 时由调用方提供，省去一次 COUNT(*) 查询。
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

        // 2. 分页查询
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
                "LEFT JOIN loc.name_loc l ON l.platform_id = g.platform_id "
                "                         AND l.group_name = g.group_name "
                "                         AND l.lang = 'zh' AND l.is_primary = 1 "
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

// MARK: 分组分页查询

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

        // 1. 总数：knownTotalCount > 0 时由调用方提供（来自 RAPlatformItem.groupCount），
        //    省去一次 COUNT(*)。
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

        // 2. 分组分页：每组取代表变体的展示字段；entry.name 为干净的分组名。
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
                "LEFT JOIN loc.name_loc l ON l.platform_id = gg.platform_id "
                "                         AND l.group_name = gg.group_name "
                "                         AND l.lang = 'zh' AND l.is_primary = 1 "
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
            "LEFT JOIN loc.name_loc l ON l.platform_id = g.platform_id "
            "                         AND l.group_name = g.group_name "
            "                         AND l.lang = 'zh' AND l.is_primary = 1 "
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

// MARK: 模糊搜索

- (void)searchGamesWithKeyword:(NSString *)keyword
                    platformId:(NSInteger)platformId
                    completion:(void (^)(NSArray<RAGameEntry *> *games,
                                         NSError * _Nullable error))completion {
    // 提前在主线程做参数校验
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

        // 搜索命中的是变体行，但结果折叠成「分组」返回：先在 FTS 命中里按分组聚合、
        // 取每组最佳 rank，再连回 game_group 取代表变体，按最佳 rank 排序。
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
                "LEFT JOIN loc.name_loc l ON l.platform_id = gg.platform_id "
                "                         AND l.group_name = gg.group_name "
                "                         AND l.lang = 'zh' AND l.is_primary = 1 "
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
                "LEFT JOIN loc.name_loc l ON l.platform_id = gg.platform_id "
                "                         AND l.group_name = gg.group_name "
                "                         AND l.lang = 'zh' AND l.is_primary = 1 "
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
                    "FROM loc.name_loc l "
                    "INNER JOIN game_group gg ON gg.platform_id = l.platform_id AND gg.group_name = l.group_name "
                    "INNER JOIN game g ON g.id = gg.representative_game_id "
                    "WHERE l.lang = 'zh' AND l.is_primary = 1 AND l.name_norm LIKE ? "
                    "ORDER BY l.name COLLATE NOCASE ASC LIMIT ?;";
                const char *locSQLPlatform =
                    "SELECT gg.representative_game_id, gg.platform_id, gg.group_name, gg.variant_count, "
                    "       g.developer, g.publisher, g.release_year, g.release_month, g.genre, g.region, "
                    "       g.franchise, g.description, g.serial, g.max_users, "
                    "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size, "
                    "       l.name AS loc_name, COALESCE(l.source, 0) AS loc_source "
                    "FROM loc.name_loc l "
                    "INNER JOIN game_group gg ON gg.platform_id = l.platform_id AND gg.group_name = l.group_name "
                    "INNER JOIN game g ON g.id = gg.representative_game_id "
                    "WHERE l.lang = 'zh' AND l.is_primary = 1 AND l.platform_id = ? AND l.name_norm LIKE ? "
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

// MARK: CRC 精确查询

- (nullable RAGameEntry *)findGameByCRC32:(NSString *)crc32 {
    __block RAGameEntry *entry = nil;
    dispatch_sync(d_dbQueue, ^{
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
            "LEFT JOIN loc.name_loc l ON l.platform_id = g.platform_id "
            "                         AND l.group_name = g.group_name "
            "                         AND l.lang = 'zh' AND l.is_primary = 1 "
            "WHERE g.crc32 = ? "
            "LIMIT 1;";
        sqlite3_stmt *stmt = NULL;
        const char *sql = d_hasLocalization ? sqlLoc : sqlPlain;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, crc32.UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                entry = [self p_gameEntryFromStmt:stmt];
            }
        }
        sqlite3_finalize(stmt);
    });
    return entry;
}

// ===========================================================================
// MARK: - Private
// ===========================================================================

/// 以【只读 + immutable】方式打开预制游戏数据库（在 dbQueue 上调用）。
///
/// 约定：App Store 包内的 sqlite 一律是离线预制好的成品（见 exportCombinedDatabase…），
/// 运行时只查不写。因此这里：
///   - 用 SQLITE_OPEN_READONLY 打开，绝不创建文件、绝不建表/迁移、绝不写 user_version；
///   - 用 URI 参数 immutable=1：告诉 SQLite 文件不可变，**完全不创建也不使用
///     -wal/-shm 边车**，无论该文件的 journal 模式是什么（这是发包只读库的标准开法，
///     也彻底杜绝了"只读打开一个 WAL 模式旧库反而生出 -wal/-shm"的问题）；
///   - 不启用 WAL / 外键约束（都只服务于写操作）。
/// 建库 DDL 与 user_version 的写入都集中在离线导出阶段完成。
- (BOOL)p_openAndSetup {
    d_hasLocalization = NO;
    // 用 NSURL 生成正确百分号转义的 file URI（路径含空格如 "Application Support" 时必需），
    // 再追加 immutable=1。配合 SQLITE_OPEN_URI 生效。
    NSString *uri = [[[NSURL fileURLWithPath:d_dbPath] absoluteString]
                     stringByAppendingString:@"?immutable=1"];
    int rc = sqlite3_open_v2(uri.UTF8String, &d_db,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL);
    if (rc != SQLITE_OK) {
        // 正常流程下 OnDemandResourceLoader 会先把预制库拷贝就位再调用 initialize；
        // 走到这里通常意味着拷贝失败 / 文件缺失，置空句柄，查询将安全地返回空结果。
        NSLog(@"[RAGameRDBManager] SQLite 只读打开失败(%d): %@", rc, d_dbPath);
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

    // 仅做一次版本核对日志，便于发现预制库与代码 schema 期望不一致；不做任何写入。
    NSInteger storedVersion = [self p_readUserVersion];
    if (storedVersion != self.currentDBVersion) {
        NSLog(@"[RAGameRDBManager] ⚠️ 预制库 user_version=%ld 与期望 %ld 不一致，请重新导出预制库",
              (long)storedVersion, (long)self.currentDBVersion);
    }

    NSString *locPath = [[d_dbPath stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"gameloc.sqlite"];
    if ([NSFileManager.defaultManager fileExistsAtPath:locPath]) {
        NSString *locURI = [[[NSURL fileURLWithPath:locPath] absoluteString]
                            stringByAppendingString:@"?mode=ro&immutable=1"];
        NSString *escaped = [locURI stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
        NSString *sql = [NSString stringWithFormat:@"ATTACH DATABASE '%@' AS loc;", escaped];
        if (sqlite3_exec(d_db, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK) {
            d_hasLocalization = YES;
            sqlite3_exec(d_db, "PRAGMA loc.cache_size=-2048;", NULL, NULL, NULL);
            sqlite3_exec(d_db, "PRAGMA loc.mmap_size=67108864;", NULL, NULL, NULL);
            NSLog(@"[RAGameRDBManager] ✅ 已 attach 游戏名本地化库");
        } else {
            NSLog(@"[RAGameRDBManager] ⚠️ attach 游戏名本地化库失败: %@", locPath);
        }
    }
    sqlite3_exec(d_db, "PRAGMA query_only=ON;", NULL, NULL, NULL);
    return YES;
}

/// 读取 SQLite 文件头中的 user_version（新建文件返回 0）
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

/// 执行实际导入（在 dbQueue 上调用），返回导入条数。
/// db 参数允许写入任意 SQLite 句柄：线上导入传入 d_db，
/// DEBUG 离线导出时传入独立的临时句柄，从而不污染运行库。
- (NSInteger)p_doImportRdbAtPath:(NSString *)rdbPath
                         rdbName:(NSString *)rdbName
                              db:(sqlite3 *)db
                           error:(NSError **)outError {
    // --- 解析 displayName / manufacturer ---
    NSString *displayName  = rdbName;
    NSString *manufacturer = nil;
    NSRange range = [rdbName rangeOfString:@" - "];
    if (range.location != NSNotFound) {
        manufacturer = [rdbName substringToIndex:range.location];
        displayName  = [rdbName substringFromIndex:range.location + range.length];
    }

    // --- 打开 rdb ---
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

    // --- 开启事务 ---
    sqlite3_exec(db, "BEGIN TRANSACTION;", NULL, NULL, NULL);

    // --- 插入 platform ---
    NSInteger platformId = 0;
    {
        const char *sql =
            "INSERT INTO platform(rdb_name, display_name, manufacturer, game_count, imported_at) "
            "VALUES(?, ?, ?, 0, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, rdbName.UTF8String,     -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, displayName.UTF8String, -1, SQLITE_TRANSIENT);
            if (manufacturer) {
                sqlite3_bind_text(stmt, 3, manufacturer.UTF8String, -1, SQLITE_TRANSIENT);
            } else {
                sqlite3_bind_null(stmt, 3);
            }
            sqlite3_bind_int64(stmt, 4, (sqlite3_int64)[[NSDate date] timeIntervalSince1970]);
            sqlite3_step(stmt);
            platformId = (NSInteger)sqlite3_last_insert_rowid(db);
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

    // --- 预编译 game / fts 插入语句 ---
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

    // --- 逐条读取 rdb 并写入 ---
    NSInteger count = 0;
    struct rmsgpack_dom_value item;

    while (libretrodb_cursor_read_item(cursor, &item) == 0) {
        if (item.type == RDT_MAP) {
            // 从 map 中提取各字段
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

            // name 是必须字段，没有则跳过
            if (name.length > 0 && gameStmt && ftsStmt) {
                // 插入 game
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

                // 插入 game_fts
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

    // 更新 game_count
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

    // 关闭 rdb
    libretrodb_cursor_close(cursor);
    libretrodb_cursor_free(cursor);
    libretrodb_close(rdb);
    libretrodb_free(rdb);

    return count;
}

#if DEBUG
/// DEBUG 离线导出：从一组 .rdb 文件构建一个成品合并库，
/// 产物与设备端 import 结果完全一致（同 schema、同 user_version、含已建好的 FTS5），
/// 末尾 checkpoint + 关 WAL + VACUUM，落地为单个可直接打包的 .db 文件。
- (NSInteger)p_exportCombinedToPath:(NSString *)destPath
                           rdbPaths:(NSArray<NSString *> *)rdbPaths
                              error:(NSError **)outError {
    NSFileManager *fm = NSFileManager.defaultManager;
    // 清掉旧产物及其 WAL/SHM 边车，保证从零开始
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

    // 仅导出（建库）阶段用 WAL 提升批量写入性能、用外键约束保证数据完整；
    // 收尾会 checkpoint 并切回 DELETE journal，最终产物是干净的单文件。
    // （注意：运行时打开预制库是只读的，不会再用到这两项。）
    sqlite3_exec(db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL);

    // 建表 / 建索引 / 建 FTS / 建分组表。运行时只读不建表，故 DDL 只在此导出阶段执行。
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

    // 对齐 user_version，使运行时 open 时跳过 DDL
    NSString *uv = [NSString stringWithFormat:@"PRAGMA user_version = %ld;",
                    (long)self.currentDBVersion];
    sqlite3_exec(db, uv.UTF8String, NULL, NULL, NULL);

    // 逐个导入 .rdb（复用与线上完全相同的导入核心）
    NSInteger total = 0;
    for (NSString *rdbPath in rdbPaths) {
        NSString *rdbName = [[rdbPath lastPathComponent] stringByDeletingPathExtension];
        NSError *impErr = nil;
        NSInteger c = [self p_doImportRdbAtPath:rdbPath rdbName:rdbName db:db error:&impErr];
        if (impErr) {
            NSLog(@"[RAGameRDBManager] export 导入失败 %@: %@", rdbName, impErr.localizedDescription);
        } else {
            NSLog(@"[RAGameRDBManager] export 导入 %@ : %ld 条", rdbName, (long)c);
            total += c;
        }
    }

    // ── 物化分组表 ────────────────────────────────────────────────────────
    // 每个 (platform_id, group_name) 归为一组：
    //   representative_game_id：组内代表变体——按地区优先级 USA>World>Europe>Japan>其它，
    //                           同级取 id 最小者；用于列表封面与元数据展示。
    //   variant_count：组内变体数。
    {
        // 用窗口函数单趟扫描（对 game 仅排序一次），避免按组的关联子查询造成的
        // O(分组数 × 行数) 爆炸：
        //   ROW_NUMBER 按「地区优先级 + id」排序，rn=1 即代表变体；
        //   COUNT(*) OVER(无 ORDER BY) 取整组的变体数。
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
            NSLog(@"[RAGameRDBManager] export 建分组表失败: %s", errMsg ? errMsg : "unknown");
            sqlite3_free(errMsg);
        }
    }

    // 回填每个平台的 group_count（去重后的分组数，供列表分页用）
    sqlite3_exec(db,
        "UPDATE platform SET group_count = "
        "  (SELECT COUNT(*) FROM game_group WHERE game_group.platform_id = platform.id);",
        NULL, NULL, NULL);

    // 收尾：合并 WAL → 单文件、切回 DELETE journal、VACUUM 瘦身。
    // 顺序：先 checkpoint 把 -wal 内容并入主库，再切 DELETE 模式，最后 VACUUM。
    sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", NULL, NULL, NULL);
    sqlite3_exec(db, "VACUUM;", NULL, NULL, NULL);

    sqlite3_close(db);

    // 兜底：切 DELETE 模式 + 关库后 SQLite 通常会自动删除 -wal/-shm，
    // 但某些情况下 -shm 仍会残留。此时这两个边车已不含任何独有数据
    // （-wal 已 checkpoint 入主库，-shm 只是 WAL 索引），显式删除，
    // 保证导出产物是干净的单文件，可直接打包。
    for (NSString *suffix in @[@"-wal", @"-shm"]) {
        [fm removeItemAtPath:[destPath stringByAppendingString:suffix] error:NULL];
    }

    return total;
}
#endif

// MARK: - 结果集转换

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
    return entry;
}

/// 分组结果行 → RAGameEntry：gameId/元数据取自代表变体，
/// name 用干净的分组名（供列表展示与封面匹配），并带上 groupName / variantCount。
/// 列顺序见 fetchGroups / 搜索折叠查询。
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
    return entry;
}

// MARK: - FTS 查询构造

/// "super mario" → "super* mario*"（FTS5 前缀匹配）
- (NSString *)p_buildFTSQuery:(NSString *)keyword {
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSArray<NSString *> *words = [keyword componentsSeparatedByCharactersInSet:ws];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *word in words) {
        NSString *w = [word stringByTrimmingCharactersInSet:ws];
        // 对 FTS5 特殊字符做简单转义（避免 MATCH 语法错误）
        w = [w stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        if (w.length > 0) {
            [tokens addObject:[w stringByAppendingString:@"*"]];
        }
    }
    return [tokens componentsJoinedByString:@" "];
}

// MARK: - 错误构造

- (NSError *)p_errorWithCode:(RARDBErrorCode)code reason:(NSString *)reason {
    return [NSError errorWithDomain:kRARDBErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

// ===========================================================================
// MARK: - 静态工具函数（文件内部使用）
// ===========================================================================

/// 从 rmsgpack_dom_value (RDT_STRING) 中安全地构造 NSString
static inline NSString * _Nullable p_str(struct rmsgpack_dom_value *val) {
    if (!val || val->type != RDT_STRING || !val->val.string.buff || val->val.string.len == 0)
        return nil;
    return [[NSString alloc] initWithBytes:val->val.string.buff
                                    length:val->val.string.len
                                  encoding:NSUTF8StringEncoding];
}

/// 将 binary 字段转换为小写 hex 字符串（md5 / sha1 通用）
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

/// 将 crc binary（4字节，big-endian 存储）转换为 8位小写 hex
static inline NSString * _Nullable p_crc32HexString(struct rmsgpack_dom_value *val) {
    if (!val || val->type != RDT_BINARY || !val->val.binary.buff) return nil;
    switch (val->val.binary.len) {
        case 4: {
            // rdb 中 CRC 以 big-endian 存储，CFSwapInt32BigToHost 处理字节序
            uint32_t raw = *(uint32_t *)val->val.binary.buff;
            uint32_t crc = CFSwapInt32BigToHost(raw);
            return [NSString stringWithFormat:@"%08x", crc];
        }
        default:
            return p_binaryHexString(val);
    }
}

/// 从 sqlite3_stmt 中安全读取 TEXT 列（可能为 NULL）
static inline NSString * _Nullable p_colText(sqlite3_stmt *stmt, int col) {
    const unsigned char *text = sqlite3_column_text(stmt, col);
    return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

/// 向 sqlite3_stmt 绑定可空 TEXT（nil → SQL NULL）
static inline void p_bindText(sqlite3_stmt *stmt, int col, NSString * _Nullable val) {
    if (val) {
        sqlite3_bind_text(stmt, col, val.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, col);
    }
}

/// 向 sqlite3_stmt 绑定 INTEGER（值为 0 时也绑定，不绑定 NULL）
static inline void p_bindInt64(sqlite3_stmt *stmt, int col, NSInteger val) {
    sqlite3_bind_int64(stmt, col, (sqlite3_int64)val);
}

static NSString *p_locNorm(NSString *s) {
    static NSCharacterSet *keep = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet decimalDigitCharacterSet];
        [set formUnionWithCharacterSet:[NSCharacterSet lowercaseLetterCharacterSet]];
        [set formUnionWithCharacterSet:[NSCharacterSet uppercaseLetterCharacterSet]];
        [set addCharactersInRange:NSMakeRange(0x4E00, 0x9FFF - 0x4E00 + 1)];
        [set addCharactersInRange:NSMakeRange(0x3400, 0x4DBF - 0x3400 + 1)];
        keep = [set copy];
    });
    NSMutableString *out = [NSMutableString string];
    NSString *lower = s.lowercaseString ?: @"";
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([keep characterIsMember:c]) {
            [out appendFormat:@"%C", c];
        }
    }
    return out;
}

@end
