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
    "  game_count   INTEGER NOT NULL DEFAULT 0,"
    "  imported_at  INTEGER NOT NULL"
    ");";

static const char * const kDDL_Game =
    "CREATE TABLE IF NOT EXISTS game ("
    "  id            INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  platform_id   INTEGER NOT NULL REFERENCES platform(id) ON DELETE CASCADE,"
    "  name          TEXT    NOT NULL,"
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

static const char * const kDDL_GameIndexPlatform =
    "CREATE INDEX IF NOT EXISTS idx_game_platform_id ON game(platform_id);";

static const char * const kDDL_GameIndexCRC32 =
    "CREATE INDEX IF NOT EXISTS idx_game_crc32 ON game(crc32);";

static const char * const kDDL_GameIndexName =
    "CREATE INDEX IF NOT EXISTS idx_game_name ON game(name COLLATE NOCASE);";

static const char * const kDDL_GameFTS =
    "CREATE VIRTUAL TABLE IF NOT EXISTS game_fts USING fts5("
    "  name,"
    "  developer,"
    "  publisher,"
    "  game_id  UNINDEXED,"
    "  tokenize = 'unicode61'"
    ");";

// ---------------------------------------------------------------------------
// MARK: - RAPlatformItem
// ---------------------------------------------------------------------------

@interface RAPlatformItem()
@property (nonatomic, assign, readwrite) NSInteger  platformId;
@property (nonatomic, copy, readwrite)   NSString  *rdbName;
@property (nonatomic, copy, readwrite)   NSString  *displayName;
@property (nonatomic, copy, readwrite)   NSString  *manufacturer;
@property (nonatomic, assign, readwrite) NSInteger  gameCount;
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
    return 1;
}

// MARK: 平台查询

- (NSArray<RAPlatformItem *> *)allPlatforms {
    __block NSMutableArray<RAPlatformItem *> *result = [NSMutableArray array];
    dispatch_sync(d_dbQueue, ^{
        const char *sql =
            "SELECT id, rdb_name, display_name, manufacturer, game_count "
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

- (BOOL)isPlatformImported:(NSString *)rdbName {
    __block BOOL found = NO;
    dispatch_sync(d_dbQueue, ^{
        const char *sql = "SELECT 1 FROM platform WHERE rdb_name = ? LIMIT 1;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, rdbName.UTF8String, -1, SQLITE_TRANSIENT);
            found = (sqlite3_step(stmt) == SQLITE_ROW);
        }
        sqlite3_finalize(stmt);
    });
    return found;
}

// MARK: 导入

- (void)importRdbAtPath:(NSString *)rdbPath
             completion:(void (^)(NSInteger importedCount, NSError * _Nullable error))completion {
    dispatch_async(d_dbQueue, ^{
        NSString *rdbName = [[rdbPath lastPathComponent]
                             stringByDeletingPathExtension];

        // 幂等：已导入则直接返回
        if ([self p_isPlatformImportedSync:rdbName]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(0, nil); });
            return;
        }

        NSError *error = nil;
        NSInteger count = [self p_doImportRdbAtPath:rdbPath
                                            rdbName:rdbName
                                              error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(count, error);
        });
    });
}

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
            const char *sql =
                "SELECT id, platform_id, name, developer, publisher, "
                "       release_year, release_month, genre, region, "
                "       franchise, description, serial, max_users, "
                "       rom_name, crc32, md5, sha1, file_size "
                "FROM game "
                "WHERE platform_id = ? "
                "ORDER BY name COLLATE NOCASE ASC "
                "LIMIT ? OFFSET ?;";
            sqlite3_stmt *stmt = NULL;
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
        NSError *error = nil;

        const char *sql;
        if (platformId == -1) {
            sql =
                "SELECT g.id, g.platform_id, g.name, g.developer, g.publisher, "
                "       g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size "
                "FROM game_fts fts "
                "INNER JOIN game g ON g.id = fts.game_id "
                "WHERE game_fts MATCH ? "
                "ORDER BY rank "
                "LIMIT 100;";
        } else {
            sql =
                "SELECT g.id, g.platform_id, g.name, g.developer, g.publisher, "
                "       g.release_year, g.release_month, g.genre, g.region, "
                "       g.franchise, g.description, g.serial, g.max_users, "
                "       g.rom_name, g.crc32, g.md5, g.sha1, g.file_size "
                "FROM game_fts fts "
                "INNER JOIN game g ON g.id = fts.game_id "
                "WHERE game_fts MATCH ? AND g.platform_id = ? "
                "ORDER BY rank "
                "LIMIT 100;";
        }

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, ftsQuery.UTF8String, -1, SQLITE_TRANSIENT);
            if (platformId != -1) {
                sqlite3_bind_int64(stmt, 2, (sqlite3_int64)platformId);
            }
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                RAGameEntry *entry = [self p_gameEntryFromStmt:stmt];
                [games addObject:entry];
            }
        } else {
            error = [self p_errorWithCode:RARDBErrorCodeQueryFailed
                                  reason:@"searchGames FTS query prepare failed"];
        }
        sqlite3_finalize(stmt);

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
        const char *sql =
            "SELECT id, platform_id, name, developer, publisher, "
            "       release_year, release_month, genre, region, "
            "       franchise, description, serial, max_users, "
            "       rom_name, crc32, md5, sha1, file_size "
            "FROM game "
            "WHERE crc32 = ? "
            "LIMIT 1;";
        sqlite3_stmt *stmt = NULL;
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

/// 打开 SQLite 并建表（在 dbQueue 上调用）
- (BOOL)p_openAndSetup {
    if (sqlite3_open(d_dbPath.UTF8String, &d_db) != SQLITE_OK) {
        NSLog(@"[RAGameRDBManager] SQLite open failed: %@", d_dbPath);
        return NO;
    }

    // WAL 模式：读写并发性能更好
    sqlite3_exec(d_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
    // 开启外键约束
    sqlite3_exec(d_db, "PRAGMA foreign_keys=ON;", NULL, NULL, NULL);

    // ── 版本检查 ──────────────────────────────────────────────────────────
    // SQLite PRAGMA user_version 存储在文件头，新建文件默认为 0。
    // 只有版本不一致时才执行 DDL，避免每次启动都扫描 schema。
    NSInteger storedVersion = [self p_readUserVersion];
    NSInteger targetVersion = self.currentDBVersion;

    if (storedVersion == targetVersion) {
        return YES;
    }

    NSLog(@"[RAGameRDBManager] Schema version mismatch: stored=%ld target=%ld — running DDL",
          (long)storedVersion, (long)targetVersion);

    // ── 建表 & 建索引 ─────────────────────────────────────────────────────
    // 所有 DDL 均使用 CREATE ... IF NOT EXISTS，多次执行安全。
    // 未来 storedVersion > 0 时在此处根据版本差执行迁移语句。
    char *errMsg = NULL;
    const char *ddls[] = {
        kDDL_Platform,
        kDDL_Game,
        kDDL_GameIndexPlatform,
        kDDL_GameIndexCRC32,
        kDDL_GameIndexName,
        kDDL_GameFTS,
        NULL
    };
    for (int i = 0; ddls[i] != NULL; i++) {
        if (sqlite3_exec(d_db, ddls[i], NULL, NULL, &errMsg) != SQLITE_OK) {
            NSLog(@"[RAGameRDBManager] DDL failed: %s", errMsg);
            sqlite3_free(errMsg);
            return NO;
        }
    }

    // DDL 全部成功后写入新版本号
    [self p_writeUserVersion:targetVersion];
    NSLog(@"[RAGameRDBManager] Schema created at version %ld", (long)targetVersion);
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

/// 将版本号写入 SQLite 文件头（PRAGMA user_version 不支持参数绑定，使用格式化 SQL）
- (void)p_writeUserVersion:(NSInteger)version {
    NSString *sql = [NSString stringWithFormat:@"PRAGMA user_version = %ld;", (long)version];
    sqlite3_exec(d_db, sql.UTF8String, NULL, NULL, NULL);
}

/// 内部同步版 isPlatformImported，必须在 dbQueue 上调用
- (BOOL)p_isPlatformImportedSync:(NSString *)rdbName {
    const char *sql = "SELECT 1 FROM platform WHERE rdb_name = ? LIMIT 1;";
    sqlite3_stmt *stmt = NULL;
    BOOL found = NO;
    if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, rdbName.UTF8String, -1, SQLITE_TRANSIENT);
        found = (sqlite3_step(stmt) == SQLITE_ROW);
    }
    sqlite3_finalize(stmt);
    return found;
}

/// 执行实际导入（在 dbQueue 上调用），返回导入条数
- (NSInteger)p_doImportRdbAtPath:(NSString *)rdbPath
                         rdbName:(NSString *)rdbName
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
    sqlite3_exec(d_db, "BEGIN TRANSACTION;", NULL, NULL, NULL);

    // --- 插入 platform ---
    NSInteger platformId = 0;
    {
        const char *sql =
            "INSERT INTO platform(rdb_name, display_name, manufacturer, game_count, imported_at) "
            "VALUES(?, ?, ?, 0, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, rdbName.UTF8String,     -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, displayName.UTF8String, -1, SQLITE_TRANSIENT);
            if (manufacturer) {
                sqlite3_bind_text(stmt, 3, manufacturer.UTF8String, -1, SQLITE_TRANSIENT);
            } else {
                sqlite3_bind_null(stmt, 3);
            }
            sqlite3_bind_int64(stmt, 4, (sqlite3_int64)[[NSDate date] timeIntervalSince1970]);
            sqlite3_step(stmt);
            platformId = (NSInteger)sqlite3_last_insert_rowid(d_db);
        }
        sqlite3_finalize(stmt);
    }

    if (platformId == 0) {
        sqlite3_exec(d_db, "ROLLBACK;", NULL, NULL, NULL);
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
        "  platform_id, name, developer, publisher, "
        "  release_year, release_month, genre, region, "
        "  franchise, description, serial, max_users, "
        "  rom_name, crc32, md5, sha1, file_size"
        ") VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);";
    const char *ftsSQL =
        "INSERT INTO game_fts(name, developer, publisher, game_id) "
        "VALUES(?,?,?,?);";

    sqlite3_stmt *gameStmt = NULL;
    sqlite3_stmt *ftsStmt  = NULL;
    sqlite3_prepare_v2(d_db, gameSQL, -1, &gameStmt, NULL);
    sqlite3_prepare_v2(d_db, ftsSQL,  -1, &ftsStmt,  NULL);

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
                p_bindText(gameStmt,  3, developer);
                p_bindText(gameStmt,  4, publisher);
                p_bindInt64(gameStmt, 5, releaseYear);
                p_bindInt64(gameStmt, 6, releaseMonth);
                p_bindText(gameStmt,  7, genre);
                p_bindText(gameStmt,  8, region);
                p_bindText(gameStmt,  9, franchise);
                p_bindText(gameStmt, 10, description);
                p_bindText(gameStmt, 11, serial);
                p_bindInt64(gameStmt,12, maxUsers);
                p_bindText(gameStmt, 13, romName);
                p_bindText(gameStmt, 14, crc32);
                p_bindText(gameStmt, 15, md5);
                p_bindText(gameStmt, 16, sha1);
                p_bindInt64(gameStmt,17, fileSize);
                sqlite3_step(gameStmt);

                NSInteger gameId = (NSInteger)sqlite3_last_insert_rowid(d_db);

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
        if (sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, (sqlite3_int64)count);
            sqlite3_bind_int64(stmt, 2, (sqlite3_int64)platformId);
            sqlite3_step(stmt);
        }
        sqlite3_finalize(stmt);
    }

    sqlite3_exec(d_db, "COMMIT;", NULL, NULL, NULL);

    // 关闭 rdb
    libretrodb_cursor_close(cursor);
    libretrodb_cursor_free(cursor);
    libretrodb_close(rdb);
    libretrodb_free(rdb);

    return count;
}

// MARK: - 结果集转换

- (RAPlatformItem *)p_platformItemFromStmt:(sqlite3_stmt *)stmt {
    RAPlatformItem *item  = [[RAPlatformItem alloc] init];
    item.platformId       = (NSInteger)sqlite3_column_int64(stmt, 0);
    item.rdbName          = p_colText(stmt, 1) ?: @"";
    item.displayName      = p_colText(stmt, 2) ?: @"";
    item.manufacturer     = p_colText(stmt, 3) ?: @"";
    item.gameCount        = (NSInteger)sqlite3_column_int64(stmt, 4);
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

@end
