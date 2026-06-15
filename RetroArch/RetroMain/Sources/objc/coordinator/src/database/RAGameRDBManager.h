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

/// 该平台已导入的游戏(变体)总数
@property (nonatomic, assign, readonly) NSInteger  gameCount;

/// 该平台去重分组后的数量(列表分页用)
@property (nonatomic, assign, readonly) NSInteger  groupCount;

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

/// 游戏标准名称，来自 rdb，No-Intro / Redump 规范，如 "Super Mario World (USA)"。
/// 注意：分组查询(fetchGroups / 搜索)返回的代表条目，此字段为干净的分组名(如 "Super Mario World")。
@property (nonatomic, copy, readonly)           NSString  *name;

/// 当前中文本地化名（若已 attach gameloc.sqlite 且有命中）。英文权威名仍在 name。
@property (nonatomic, copy, nullable, readonly) NSString  *localizedName;

/// gameloc source 枚举：1=en-cjk, 2=wikidata, 3=deepseek-chat, 4=deepseek-chat-pass2, 5=deepseek-loose。
@property (nonatomic, assign, readonly)         NSInteger  localizationSource;

/// YES 表示 source=5(deepseek-loose)，UI 应显示"仅供参考"标记。
@property (nonatomic, assign, readonly, getter=isLocalizationReference) BOOL localizationReference;

/// 分组键(游戏名第一个括号前的前缀)。仅分组查询结果赋值，逐条查询时为 nil。
@property (nonatomic, copy, nullable, readonly) NSString  *groupName;

/// 该组变体数。仅分组查询结果赋值，逐条查询时为 0。
@property (nonatomic, assign, readonly)         NSInteger  variantCount;

/// 该游戏在 cheat.sqlite 中的作弊条数。普通游戏库查询为 0，仅作弊库目录查询赋值。
@property (nonatomic, assign, readonly)         NSInteger  cheatCount;

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
 * 仅用于：①离线导出预制库时写入文件头 user_version；②运行时打开预制库时
 * 核对版本是否一致（仅日志告警，不做迁移）。当前值为 1。
 */
@property (nonatomic, assign, readonly) NSInteger currentDBVersion;

/**
 * 以【只读】方式打开预制游戏数据库。
 *
 * 约定：App Store 包内的 sqlite 一律是离线预制好的成品（见 exportCombinedDatabaseToPath…），
 * 运行时只查不写——因此不会创建文件、不建表、不迁移、不启用 WAL。
 *
 * @param dbPath 预制 sqlite 的完整路径（由 Swift 侧拷贝就位后传入）。
 *               文件不存在时打开失败，后续查询安全地返回空结果。
 */
- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion;

// MARK: 平台查询

/**
 * 返回所有平台列表，按 displayName 字母顺序排列。
 * 同步执行，可在主线程调用（数据量小，速度极快）。
 */
- (NSArray<RAPlatformItem *> *)allPlatforms;

#if DEBUG
// MARK: 离线导出（DEBUG）

/**
 * DEBUG 专用：从一组 .rdb 文件离线构建成品合并数据库，落地为单个 .db 文件。
 *
 * - 产物与设备端逐个 import 的结果完全一致：同 schema、同 user_version、
 *   含已建好的 FTS5 索引，因此 findGameByCRC32 / FTS 搜索 / 分页查询照常工作。
 * - 末尾执行 wal_checkpoint(TRUNCATE) + journal_mode=DELETE + VACUUM，
 *   合并成单个文件并瘦身，可直接打包进 App 作为预制库。
 * - 使用独立 sqlite 句柄，不影响运行库。
 *
 * @param destPath   产物 .db 的完整路径（已存在会被覆盖，连同 -wal/-shm 边车）
 * @param rdbPaths   源 .rdb 文件完整路径数组
 * @param completion totalGames：写入的游戏总条数；error：失败原因（主线程回调）
 */
- (void)exportCombinedDatabaseToPath:(NSString *)destPath
                        fromRdbPaths:(NSArray<NSString *> *)rdbPaths
                          completion:(void (^)(NSInteger totalGames,
                                               NSError * _Nullable error))completion;
#endif

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

// MARK: 分组分页查询

/**
 * 按平台分页获取「去重分组」列表（每个不同的 group_name 一行）。
 *
 * 每条返回的 RAGameEntry 是该组的代表变体，但 name 为干净的分组名，
 * 并带有 groupName / variantCount，可直接用于列表展示与封面匹配。
 *
 * @param platformId      目标平台 id
 * @param offset/limit    分页参数
 * @param knownTotalCount 已知分组总数（如 RAPlatformItem.groupCount）可跳过 COUNT(*)，传 0 表示未知
 * @param completion      groups：当页分组；totalCount：分组总数；error：失败原因
 */
- (void)fetchGroupsForPlatformId:(NSInteger)platformId
                          offset:(NSInteger)offset
                           limit:(NSInteger)limit
                 knownTotalCount:(NSInteger)knownTotalCount
                      completion:(void (^)(NSArray<RAGameEntry *> *groups,
                                           NSInteger               totalCount,
                                           NSError  * _Nullable    error))completion;

/**
 * 获取某个分组下的全部变体（真实名称，含地区/版本），按名称升序。
 * 用于让用户在一组内选择具体的某个变体。
 *
 * @param platformId 平台 id
 * @param groupName  分组键（来自 RAGameEntry.groupName）
 * @param completion variants：该组全部变体；error：失败原因
 */
- (void)fetchVariantsForPlatformId:(NSInteger)platformId
                         groupName:(NSString *)groupName
                        completion:(void (^)(NSArray<RAGameEntry *> *variants,
                                             NSError  * _Nullable    error))completion;

// MARK: 模糊搜索

/**
 * 对游戏名、开发商、发行商进行模糊搜索，使用 SQLite FTS5 全文索引。
 * 支持前缀匹配，如输入 "mario" 可匹配 "Super Mario Bros"、"Mario Kart 64"。
 * 多词输入时各词独立匹配（AND 关系），如 "super mario" 匹配含 super 且含 mario 的条目。
 *
 * @param keyword    搜索关键词，支持多词（空格分隔）
 * @param platformId 限定搜索范围的平台 id；传 -1 表示跨所有平台搜索
 * 结果会折叠成「分组」返回（每个命中分组一条代表变体），与列表保持一致。
 *
 * @param completion games：匹配的分组代表（最多 100 条，按最佳相关度排序）；error：失败原因
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
 * @return 匹配到的游戏条目；若无匹配返回 nil。返回值包含英文 name 与英文 groupName。
 */
- (nullable RAGameEntry *)findGameByCRC32:(NSString *)crc32 NS_SWIFT_NAME(findGame(byCRC32:));

@end

NS_ASSUME_NONNULL_END
