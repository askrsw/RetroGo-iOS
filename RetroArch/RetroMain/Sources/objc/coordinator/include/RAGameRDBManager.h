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
@property (nonatomic, assign, readonly) NSInteger  gameCount;   // Total number of variants
@property (nonatomic, assign, readonly) NSInteger  groupCount;  // Number of deduplicated groups (for list paging)
@end

// ---------------------------------------------------------------------------
// MARK: - RAGameEntry
// ---------------------------------------------------------------------------

@interface RAGameEntry : NSObject
@property (nonatomic, assign, readonly)         NSInteger  gameId;
@property (nonatomic, assign, readonly)         NSInteger  platformId;
@property (nonatomic, copy, readonly)           NSString  *name;
/// Name from the attached language pack (game_name), when it has one. The
/// authoritative English name stays in `name`.
@property (nonatomic, copy, nullable, readonly) NSString  *localizedName;
/// BCP-47 language of the pack `localizedName` came from (e.g. "zh-Hans");
/// nil when there is no localized name. UI shows the name only while this
/// matches the language pack of the current App language.
@property (nonatomic, copy, nullable, readonly) NSString  *localizationLanguage;
/// language pack game_name.source values: 1=en-cjk, 2=wikidata, 3=deepseek-chat, 4=deepseek-chat-pass2, 5=deepseek-loose.
@property (nonatomic, assign, readonly)         NSInteger  localizationSource;
/// YES means source=5 (deepseek-loose); the UI should show a "for reference only" mark.
@property (nonatomic, assign, readonly, getter=isLocalizationReference) BOOL localizationReference;
/// Group key (the prefix before the first parenthesis). Set by group queries and the exact CRC lookup.
@property (nonatomic, copy, nullable, readonly) NSString  *groupName;
/// Number of variants in the group. Set only for group query results; 0 for per-entry queries.
@property (nonatomic, assign, readonly)         NSInteger  variantCount;
/// Number of cheats this game has in cheat.sqlite. 0 for regular game library queries; set only by cheat catalog queries.
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

/// Opens the prebuilt game database read-only (a finished sqlite, only queried at runtime, never written).
- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion;
- (NSArray<RAPlatformItem *> *)allPlatforms;

/// Attaches the language pack at `path` (nil = English only) for localized
/// names and localized search, replacing the previous one. Takes effect for
/// queries issued after it; may be called before or after initialize.
- (void)setLanguagePackPath:(nullable NSString *)path
                 completion:(nullable void (^)(void))completion
    NS_SWIFT_NAME(setLanguagePack(path:completion:));

#if DEBUG
/// DEBUG only: builds a finished merged database offline from a set of .rdb files, written as a single .db file.
/// The output is identical to importing each file on the device (same schema, same user_version, FTS5 already built),
/// and is bundled in the App as the prebuilt database, so users no longer have to parse .rdb files.
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

/// Like findGameByCRC32:, but tells "no such game" (YES, *game = nil) apart
/// from a failed query (NO + error). Synchronous; never call on the main thread.
- (BOOL)lookupGameByCRC32:(NSString *)crc32
                     game:(RAGameEntry * _Nullable * _Nonnull)game
                    error:(NSError **)error
    NS_SWIFT_NAME(lookupGame(byCRC32:game:));
@end

NS_ASSUME_NONNULL_END
