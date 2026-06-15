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

@interface RAPlatformItem : NSObject
@property (nonatomic, assign, readonly) NSInteger  platformId;
@property (nonatomic, copy, readonly)   NSString  *rdbName;
@property (nonatomic, copy, readonly)   NSString  *displayName;
@property (nonatomic, copy, readonly)   NSString  *manufacturer;
@property (nonatomic, assign, readonly) NSInteger  gameCount;   // 变体总数
@property (nonatomic, assign, readonly) NSInteger  groupCount;  // 去重分组数(列表分页用)
@end

// ---------------------------------------------------------------------------
// MARK: - RAGameEntry
// ---------------------------------------------------------------------------

@interface RAGameEntry : NSObject
@property (nonatomic, assign, readonly)         NSInteger  gameId;
@property (nonatomic, assign, readonly)         NSInteger  platformId;
@property (nonatomic, copy, readonly)           NSString  *name;
/// 当前中文本地化名（若已 attach gameloc.sqlite 且有命中）。英文权威名仍在 name。
@property (nonatomic, copy, nullable, readonly) NSString  *localizedName;
/// gameloc source 枚举：1=en-cjk, 2=wikidata, 3=deepseek-chat, 4=deepseek-chat-pass2, 5=deepseek-loose。
@property (nonatomic, assign, readonly)         NSInteger  localizationSource;
/// YES 表示 source=5(deepseek-loose)，UI 应显示"仅供参考"标记。
@property (nonatomic, assign, readonly, getter=isLocalizationReference) BOOL localizationReference;
/// 分组键(第一个括号前的前缀)。分组查询和 CRC 精确查询会赋值。
@property (nonatomic, copy, nullable, readonly) NSString  *groupName;
/// 该组变体数。仅分组查询结果会赋值；逐条查询时为 0。
@property (nonatomic, assign, readonly)         NSInteger  variantCount;
/// 该游戏在 cheat.sqlite 中的作弊条数。普通游戏库查询为 0，仅作弊库目录查询赋值。
@property (nonatomic, assign, readonly)         NSInteger  cheatCount;
@property (nonatomic, copy, nullable, readonly) NSString  *developer;
@property (nonatomic, copy, nullable, readonly) NSString  *publisher;
@property (nonatomic, assign, readonly)         NSInteger  releaseYear;
@property (nonatomic, assign, readonly)         NSInteger  releaseMonth;
@property (nonatomic, copy, nullable, readonly) NSString  *genre;
@property (nonatomic, copy, nullable, readonly) NSString  *region;
@property (nonatomic, copy, nullable, readonly) NSString  *franchise;
@property (nonatomic, copy, nullable, readonly) NSString  *gameDescription;
@property (nonatomic, copy, nullable, readonly) NSString  *serial;
@property (nonatomic, assign, readonly)         NSInteger  maxUsers;
@property (nonatomic, copy, nullable, readonly) NSString  *romName;
@property (nonatomic, copy, nullable, readonly) NSString  *crc32;
@property (nonatomic, copy, nullable, readonly) NSString  *md5;
@property (nonatomic, copy, nullable, readonly) NSString  *sha1;
@property (nonatomic, assign, readonly)         NSInteger  fileSize;
@end

// ---------------------------------------------------------------------------
// MARK: - RAGameRDBManager
// ---------------------------------------------------------------------------

@interface RAGameRDBManager : NSObject

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

/// 以只读方式打开预制游戏数据库（成品 sqlite，运行时只查不写）。
- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion;
- (NSArray<RAPlatformItem *> *)allPlatforms;

#if DEBUG
/// DEBUG 专用：从一组 .rdb 文件离线构建成品合并数据库，落地为单个 .db 文件。
/// 产物与设备端逐个 import 的结果完全一致（同 schema、同 user_version、含已建好的 FTS5），
/// 用于打包进 App 作为预制库，从而免去用户端再解析 .rdb。
- (void)exportCombinedDatabaseToPath:(NSString *)destPath
                        fromRdbPaths:(NSArray<NSString *> *)rdbPaths
                          completion:(void (^)(NSInteger totalGames, NSError * _Nullable error))completion;
#endif
/// Fetches a page of games.
/// Pass knownTotalCount > 0 (e.g. from RAPlatformItem.gameCount) to skip the
/// internal COUNT(*) query — useful when the total is already available to the caller.
- (void)fetchGamesForPlatformId:(NSInteger)platformId
                         offset:(NSInteger)offset
                          limit:(NSInteger)limit
               knownTotalCount:(NSInteger)knownTotalCount
                     completion:(void (^)(NSArray<RAGameEntry *> *games, NSInteger totalCount, NSError * _Nullable error))completion;

/// Fetches a page of de-duplicated game *groups* (one row per distinct group_name).
/// Each returned RAGameEntry is the group's representative variant, with `name` set to
/// the clean group name plus `groupName` / `variantCount`. Pass knownTotalCount > 0
/// (e.g. RAPlatformItem.groupCount) to skip the internal COUNT(*).
- (void)fetchGroupsForPlatformId:(NSInteger)platformId
                          offset:(NSInteger)offset
                           limit:(NSInteger)limit
                 knownTotalCount:(NSInteger)knownTotalCount
                      completion:(void (^)(NSArray<RAGameEntry *> *groups, NSInteger totalCount, NSError * _Nullable error))completion;

/// Fetches all individual variants of one group (real names), sorted by name.
/// Used to let the user pick a specific region/revision within a group.
- (void)fetchVariantsForPlatformId:(NSInteger)platformId
                         groupName:(NSString *)groupName
                        completion:(void (^)(NSArray<RAGameEntry *> *variants, NSError * _Nullable error))completion;

/// FTS5 search. Results are collapsed to groups (one representative per matched group).
- (void)searchGamesWithKeyword:(NSString *)keyword platformId:(NSInteger)platformId completion:(void (^)(NSArray<RAGameEntry *> *games, NSError  * _Nullable    error))completion;
- (nullable RAGameEntry *)findGameByCRC32:(NSString *)crc32 NS_SWIFT_NAME(findGame(byCRC32:));
@end

NS_ASSUME_NONNULL_END
