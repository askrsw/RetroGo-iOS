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

/// One row of the platform table, representing a game platform (one .rdb file).
@interface RAPlatformItem : NSObject

/// Database primary key
@property (nonatomic, assign, readonly) NSInteger  platformId;

/// rdb file name (without path or extension), e.g. "Nintendo - Game Boy Advance"
@property (nonatomic, copy, readonly)   NSString  *rdbName;

/// Platform display name, the part of rdbName after the first " - ", e.g. "Game Boy Advance"
@property (nonatomic, copy, readonly)   NSString  *displayName;

/// Manufacturer name, the part of rdbName before the first " - ", e.g. "Nintendo"
@property (nonatomic, copy, readonly)   NSString  *manufacturer;

/// Total number of games (variants) imported for this platform
@property (nonatomic, assign, readonly) NSInteger  gameCount;

/// Number of deduplicated groups for this platform (for list paging)
@property (nonatomic, assign, readonly) NSInteger  groupCount;

@end

// ---------------------------------------------------------------------------
// MARK: - RAGameEntry
// ---------------------------------------------------------------------------

/// One row of the game table, representing a game entry.
@interface RAGameEntry : NSObject

/// Database primary key
@property (nonatomic, assign, readonly)         NSInteger  gameId;

/// Owning platform id (matches RAPlatformItem.platformId)
@property (nonatomic, assign, readonly)         NSInteger  platformId;

/// Standard game name from the rdb, following No-Intro / Redump naming, e.g. "Super Mario World (USA)".
/// Note: for representative entries returned by group queries (fetchGroups / search), this is the clean group name (e.g. "Super Mario World").
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

/// Group key (the prefix of the game name before the first parenthesis). Set only for group query results; nil for per-entry queries.
@property (nonatomic, copy, nullable, readonly) NSString  *groupName;

/// Number of variants in the group. Set only for group query results; 0 for per-entry queries.
@property (nonatomic, assign, readonly)         NSInteger  variantCount;

/// Number of cheats this game has in cheat.sqlite. 0 for regular game library queries; set only by cheat catalog queries.
@property (nonatomic, assign, readonly)         NSInteger  cheatCount;

/// Developer; multiple developers in the rdb are separated by "|"
@property (nonatomic, copy, nullable, readonly) NSString  *developer;

/// Publisher
@property (nonatomic, copy, nullable, readonly) NSString  *publisher;

/// Release year, 0 if unknown
@property (nonatomic, assign, readonly)         NSInteger  releaseYear;

/// Release month, 0 if unknown
@property (nonatomic, assign, readonly)         NSInteger  releaseMonth;

/// Genre, e.g. "RPG", "Action"
@property (nonatomic, copy, nullable, readonly) NSString  *genre;

/// Region, e.g. "USA", "Japan", "Europe"
@property (nonatomic, copy, nullable, readonly) NSString  *region;

/// Franchise, e.g. "Mario", "Final Fantasy"
@property (nonatomic, copy, nullable, readonly) NSString  *franchise;

/// Game description (most rdb entries don't have one)
@property (nonatomic, copy, nullable, readonly) NSString  *gameDescription;

/// Serial number, common on platforms such as PS1/PS2
@property (nonatomic, copy, nullable, readonly) NSString  *serial;

/// Maximum number of players, 0 if unknown
@property (nonatomic, assign, readonly)         NSInteger  maxUsers;

/// Original ROM file name recorded in the rdb
@property (nonatomic, copy, nullable, readonly) NSString  *romName;

/// CRC32 as an 8-digit lowercase hex string, e.g. "a3f2c1b0"; used for ROM matching
@property (nonatomic, copy, nullable, readonly) NSString  *crc32;

/// MD5 as a 32-digit hex string
@property (nonatomic, copy, nullable, readonly) NSString  *md5;

/// SHA1 as a 40-digit hex string
@property (nonatomic, copy, nullable, readonly) NSString  *sha1;

/// ROM file size in bytes, 0 if unknown
@property (nonatomic, assign, readonly)         NSInteger  fileSize;

@end

// ---------------------------------------------------------------------------
// MARK: - RAGameRDBManager
// ---------------------------------------------------------------------------

/**
 * RARDBManager
 *
 * Imports libretro-database .rdb files into a local SQLite database
 * and provides paged queries and fuzzy search.
 *
 * Threading model:
 *   - All SQLite work runs on a private internal serial queue; callers don't need to care about thread safety.
 *   - Completion blocks of async methods are always called on the main thread.
 *   - findGameByCRC32: is synchronous; callers must make sure not to call it on the main thread.
 *
 * Typical usage (Swift side):
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
 * The SQLite schema version the current code expects.
 * Used only to: (1) write user_version into the file header when exporting the prebuilt database offline; (2) check
 * the version when opening the prebuilt database at runtime (only logs a warning, no migration). Currently 1.
 */
@property (nonatomic, assign, readonly) NSInteger currentDBVersion;

/**
 * Opens the prebuilt game database **read-only**.
 *
 * Convention: the sqlite in the App Store build is always a finished, offline prebuilt database (see exportCombinedDatabaseToPath…),
 * only queried at runtime, never written — so no file is created, no tables are built, no migration runs and WAL is not enabled.
 *
 * @param dbPath Full path of the prebuilt sqlite (passed in after the Swift side has copied it into place).
 *               If the file doesn't exist, opening fails and later queries safely return empty results.
 */
- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion;

// MARK: Platform queries

/**
 * Returns all platforms sorted alphabetically by displayName.
 * Runs synchronously and can be called on the main thread (the data is small, so it is very fast).
 */
- (NSArray<RAPlatformItem *> *)allPlatforms;

/// Attaches the language pack at `path` (nil = English only) for localized
/// names and localized search, replacing the previous one. Takes effect for
/// queries issued after it; may be called before or after initialize.
- (void)setLanguagePackPath:(nullable NSString *)path
                 completion:(nullable void (^)(void))completion
    NS_SWIFT_NAME(setLanguagePack(path:completion:));

#if DEBUG
// MARK: Offline export (DEBUG)

/**
 * DEBUG only: builds a finished merged database offline from a set of .rdb files, written as a single .db file.
 *
 * - The output is identical to importing each file on the device: same schema, same user_version,
 *   FTS5 index already built, so findGameByCRC32 / FTS search / paged queries work as usual.
 * - Ends with wal_checkpoint(TRUNCATE) + journal_mode=DELETE + VACUUM to merge
 *   into a single compacted file that can be bundled in the App as the prebuilt database.
 * - Uses its own sqlite handle and leaves the runtime database untouched.
 *
 * @param destPath   Full path of the output .db (overwritten if it exists, along with its -wal/-shm sidecars)
 * @param rdbPaths   Full paths of the source .rdb files
 * @param completion totalGames: number of games written; error: the failure reason (called on the main thread)
 */
- (void)exportCombinedDatabaseToPath:(NSString *)destPath
                        fromRdbPaths:(NSArray<NSString *> *)rdbPaths
                          completion:(void (^)(NSInteger totalGames,
                                               NSError * _Nullable error))completion;
#endif

// MARK: Paged queries

/**
 * Fetches a page of games for a platform, sorted by game name in ascending order.
 *
 * @param platformId      Target platform id (from RAPlatformItem.platformId)
 * @param offset          Page offset, starting from 0
 * @param limit           Entries per page, 50 recommended
 * @param knownTotalCount If the caller already knows the total game count (e.g. from RAPlatformItem.gameCount),
 *                        passing it skips the internal COUNT(*) query and saves one SQLite query per page.
 *                        Pass 0 if unknown and COUNT(*) runs internally.
 * @param completion      games: games on this page; totalCount: total game count; error: the failure reason
 */
- (void)fetchGamesForPlatformId:(NSInteger)platformId
                         offset:(NSInteger)offset
                          limit:(NSInteger)limit
               knownTotalCount:(NSInteger)knownTotalCount
                     completion:(void (^)(NSArray<RAGameEntry *> *games,
                                          NSInteger               totalCount,
                                          NSError  * _Nullable    error))completion;

// MARK: Grouped paged queries

/**
 * Fetches a page of "deduplicated groups" for a platform (one row per distinct group_name).
 *
 * Each returned RAGameEntry is the group's representative variant, but its name is the clean group name,
 * and it carries groupName / variantCount, ready for list display and cover matching.
 *
 * @param platformId      Target platform id
 * @param offset/limit    Paging parameters
 * @param knownTotalCount A known total group count (e.g. RAPlatformItem.groupCount) skips COUNT(*); pass 0 if unknown
 * @param completion      groups: groups on this page; totalCount: total group count; error: the failure reason
 */
- (void)fetchGroupsForPlatformId:(NSInteger)platformId
                          offset:(NSInteger)offset
                           limit:(NSInteger)limit
                 knownTotalCount:(NSInteger)knownTotalCount
                      completion:(void (^)(NSArray<RAGameEntry *> *groups,
                                           NSInteger               totalCount,
                                           NSError  * _Nullable    error))completion;

/**
 * Fetches all variants in a group (real names, with region/version), sorted by name in ascending order.
 * Lets the user pick a specific variant within a group.
 *
 * @param platformId Platform id
 * @param groupName  Group key (from RAGameEntry.groupName)
 * @param completion variants: all variants in the group; error: the failure reason
 */
- (void)fetchVariantsForPlatformId:(NSInteger)platformId
                         groupName:(NSString *)groupName
                        completion:(void (^)(NSArray<RAGameEntry *> *variants,
                                             NSError  * _Nullable    error))completion;

// MARK: Fuzzy search

/**
 * Fuzzy-searches game names, developers and publishers using the SQLite FTS5 full-text index.
 * Supports prefix matching: "mario" matches "Super Mario Bros" and "Mario Kart 64".
 * With several words, each word matches independently (AND): "super mario" matches entries containing both super and mario.
 *
 * @param keyword    Search keywords, several words allowed (space separated)
 * @param platformId Platform id to limit the search to; pass -1 to search all platforms
 * Results are folded into groups (one representative variant per matching group), consistent with the list.
 *
 * @param completion games: matching group representatives (at most 100, sorted by best relevance); error: the failure reason
 */
- (void)searchGamesWithKeyword:(NSString *)keyword
                    platformId:(NSInteger)platformId
                    completion:(void (^)(NSArray<RAGameEntry *> *games,
                                         NSError  * _Nullable    error))completion;

// MARK: Exact CRC lookup

/**
 * Finds a game entry by exact CRC32, used for matching after a ROM import.
 * Uses the idx_game_crc32 index, so it is very fast.
 *
 * Synchronous; callers must make sure not to call it directly on the main thread.
 *
 * @param crc32 8-digit lowercase hex string, e.g. "a3f2c1b0"
 * @return The matching game entry, or nil if none. The result carries the English name and English groupName.
 */
- (nullable RAGameEntry *)findGameByCRC32:(NSString *)crc32 NS_SWIFT_NAME(findGame(byCRC32:));

/// Like findGameByCRC32:, but tells "no such game" (YES, *game = nil) apart
/// from a failed query (NO + error). Synchronous; never call on the main thread.
- (BOOL)lookupGameByCRC32:(NSString *)crc32
                     game:(RAGameEntry * _Nullable * _Nonnull)game
                    error:(NSError **)error
    NS_SWIFT_NAME(lookupGame(byCRC32:game:));

@end

NS_ASSUME_NONNULL_END
