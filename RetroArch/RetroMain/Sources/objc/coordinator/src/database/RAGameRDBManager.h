//
//  RAGameRDBManager.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// MARK: - RAPlatformItem
// ---------------------------------------------------------------------------

/// 对应 platform 表的一条记录，代表一个游戏平台（一个 .rdb 文件）。
@interface RAPlatformItem : NSObject

/// 数据库主键
@property (nonatomic, assign, readonly) NSInteger  platformId;

/// rdb 文件名（不含路径和扩展名），如 "Nintendo - Game Boy Advance"
@property (nonatomic, copy, readonly)   NSString  *rdbName;

/// 平台显示名，取 rdbName 中第一个 " - " 之后的部分，如 "Game Boy Advance"
@property (nonatomic, copy, readonly)   NSString  *displayName;

/// 厂商名，取 rdbName 中第一个 " - " 之前的部分，如 "Nintendo"
@property (nonatomic, copy, readonly)   NSString  *manufacturer;

/// 该平台已导入的游戏数量
@property (nonatomic, assign, readonly) NSInteger  gameCount;

@end

// ---------------------------------------------------------------------------
// MARK: - RAGameEntry
// ---------------------------------------------------------------------------

/// 对应 game 表的一条记录，代表一个游戏条目。
@interface RAGameEntry : NSObject

/// 数据库主键
@property (nonatomic, assign, readonly)         NSInteger  gameId;

/// 所属平台 id（关联 RAPlatformItem.platformId）
@property (nonatomic, assign, readonly)         NSInteger  platformId;

/// 游戏标准名称，来自 rdb，No-Intro / Redump 规范，如 "Super Mario World (USA)"
@property (nonatomic, copy, readonly)           NSString  *name;

/// 开发商，rdb 中多个开发商用 "|" 分隔
@property (nonatomic, copy, nullable, readonly) NSString  *developer;

/// 发行商
@property (nonatomic, copy, nullable, readonly) NSString  *publisher;

/// 发行年份，0 表示未知
@property (nonatomic, assign, readonly)         NSInteger  releaseYear;

/// 发行月份，0 表示未知
@property (nonatomic, assign, readonly)         NSInteger  releaseMonth;

/// 游戏类型，如 "RPG"、"Action"
@property (nonatomic, copy, nullable, readonly) NSString  *genre;

/// 地区，如 "USA"、"Japan"、"Europe"
@property (nonatomic, copy, nullable, readonly) NSString  *region;

/// 系列名，如 "Mario"、"Final Fantasy"
@property (nonatomic, copy, nullable, readonly) NSString  *franchise;

/// 游戏简介（rdb 中大多数条目没有此字段）
@property (nonatomic, copy, nullable, readonly) NSString  *gameDescription;

/// 序列号，PS1/PS2 等平台常见
@property (nonatomic, copy, nullable, readonly) NSString  *serial;

/// 最大玩家数，0 表示未知
@property (nonatomic, assign, readonly)         NSInteger  maxUsers;

/// rdb 中记录的原始 ROM 文件名
@property (nonatomic, copy, nullable, readonly) NSString  *romName;

/// CRC32，8 位小写 hex 字符串，如 "a3f2c1b0"；用于 ROM 匹配
@property (nonatomic, copy, nullable, readonly) NSString  *crc32;

/// MD5，32 位 hex 字符串
@property (nonatomic, copy, nullable, readonly) NSString  *md5;

/// SHA1，40 位 hex 字符串
@property (nonatomic, copy, nullable, readonly) NSString  *sha1;

/// ROM 文件大小（字节），0 表示未知
@property (nonatomic, assign, readonly)         NSInteger  fileSize;

@end

// ---------------------------------------------------------------------------
// MARK: - RAGameRDBManager
// ---------------------------------------------------------------------------

/**
 * RARDBManager
 *
 * 负责将 libretro-database 的 .rdb 文件导入本地 SQLite 数据库，
 * 并提供分页查询和模糊搜索接口。
 *
 * 线程模型：
 *   - 所有 SQLite 操作在内部私有串行队列执行，调用方无需关心线程安全。
 *   - 异步方法的 completion block 均在主线程回调。
 *   - findGameByCRC32: 是同步方法，调用方需自行确保不在主线程调用。
 *
 * 典型使用流程（Swift 侧）：
 *   let dbPath = // Documents/retrogame_rdb.db
 *   let manager = RARDBManager(databasePath: dbPath)
 *   manager.importRdb(atPath: rdbPath) { count, error in ... }
 *   manager.fetchGames(forPlatformId: 1, offset: 0, limit: 50) { games, total, error in ... }
 *   manager.searchGames(withKeyword: "mario", platformId: -1) { games, error in ... }
 */
@interface RAGameRDBManager : NSObject

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

/**
 * 当前代码期望的 SQLite schema 版本号。
 * SQLite 文件中存储的 user_version 与此值不一致时，才会执行建表/建索引操作。
 * 当前值为 1；后续 schema 变更时递增此值并在 p_openAndSetup 中添加迁移逻辑。
 */
@property (nonatomic, assign, readonly) NSInteger currentDBVersion;

/**
 * 初始化 SQLite 连接，并在版本不匹配时创建所需的表结构和索引。
 * 版本一致时直接跳过 DDL，启动速度极快。
 *
 * @param dbPath SQLite 文件的完整路径，由 Swift 侧传入，通常位于 Documents 目录。
 *               若文件不存在会自动创建。
 */
- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion;

// MARK: 平台查询

/**
 * 返回所有已导入的平台列表，按 displayName 字母顺序排列。
 * 同步执行，可在主线程调用（数据量小，速度极快）。
 */
- (NSArray<RAPlatformItem *> *)allPlatforms;

/**
 * 检查某个 rdb 是否已经导入过（幂等导入的前置检查）。
 *
 * @param rdbName rdb 文件名，不含路径和 .rdb 后缀，
 *                如 "Nintendo - Game Boy Advance"
 */
- (BOOL)isPlatformImported:(NSString *)rdbName;

// MARK: 导入

/**
 * 将指定 .rdb 文件的所有游戏条目导入 SQLite。
 *
 * - 幂等：若该平台已存在，直接以 importedCount=0 回调，不会重复导入。
 * - 在后台串行队列执行（大型 rdb 可能需要 1~3 秒）。
 * - completion 在主线程回调。
 *
 * @param rdbPath   .rdb 文件的完整路径
 * @param completion importedCount：实际写入的游戏条数；error：失败原因
 */
- (void)importRdbAtPath:(NSString *)rdbPath
             completion:(void (^)(NSInteger importedCount,
                                  NSError  * _Nullable error))completion;

// MARK: 分页查询

/**
 * 按平台分页获取游戏列表，按游戏名字母升序排列。
 *
 * @param platformId      目标平台 id（来自 RAPlatformItem.platformId）
 * @param offset          分页偏移量，从 0 开始
 * @param limit           每页条数，建议 50
 * @param knownTotalCount 若调用方已知游戏总数（如来自 RAPlatformItem.gameCount），
 *                        传入该值可跳过内部的 COUNT(*) 查询，每页节省一次 SQLite 查询。
 *                        传 0 表示未知，由内部执行 COUNT(*)。
 * @param completion      games：当页游戏列表；totalCount：游戏总数；error：失败原因
 */
- (void)fetchGamesForPlatformId:(NSInteger)platformId
                         offset:(NSInteger)offset
                          limit:(NSInteger)limit
               knownTotalCount:(NSInteger)knownTotalCount
                     completion:(void (^)(NSArray<RAGameEntry *> *games,
                                          NSInteger               totalCount,
                                          NSError  * _Nullable    error))completion;

// MARK: 模糊搜索

/**
 * 对游戏名、开发商、发行商进行模糊搜索，使用 SQLite FTS5 全文索引。
 * 支持前缀匹配，如输入 "mario" 可匹配 "Super Mario Bros"、"Mario Kart 64"。
 * 多词输入时各词独立匹配（AND 关系），如 "super mario" 匹配含 super 且含 mario 的条目。
 *
 * @param keyword    搜索关键词，支持多词（空格分隔）
 * @param platformId 限定搜索范围的平台 id；传 -1 表示跨所有平台搜索
 * @param completion games：匹配结果（最多 100 条，按相关度排序）；error：失败原因
 */
- (void)searchGamesWithKeyword:(NSString *)keyword
                    platformId:(NSInteger)platformId
                    completion:(void (^)(NSArray<RAGameEntry *> *games,
                                         NSError  * _Nullable    error))completion;

// MARK: CRC 精确查询

/**
 * 根据 CRC32 精确查找游戏条目，用于 ROM 导入后的匹配。
 * 走 idx_game_crc32 索引，速度极快。
 *
 * 同步方法，调用方需确保不在主线程直接调用。
 *
 * @param crc32 8 位小写 hex 字符串，如 "a3f2c1b0"
 * @return 匹配到的游戏条目；若无匹配返回 nil
 */
- (nullable RAGameEntry *)findGameByCRC32:(NSString *)crc32;

@end

NS_ASSUME_NONNULL_END
