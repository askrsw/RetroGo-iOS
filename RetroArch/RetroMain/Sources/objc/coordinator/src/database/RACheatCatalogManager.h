//
//  RACheatCatalogManager.h
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

#import <Foundation/Foundation.h>
#import "RAGameRDBManager.h"
#import "../function/RetroArchX+Cheat.h"

NS_ASSUME_NONNULL_BEGIN

/// Read-only catalog over cheat.sqlite (English) plus, when one is given, the
/// language pack of the App language attached for translated game names and
/// cheat descriptions. It deliberately returns the app-wide
/// RAGameEntry/RACheatItem models so callers can pass data across database,
/// Swift UI, and RetroArch cheat-application code without adapter objects.
@interface RACheatCatalogManager : NSObject

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

/// meta.db_version of the open cheat.sqlite (0 when closed). Template bindings
/// store it so that a rebuilt catalog triggers one fresh lookup.
@property (nonatomic, assign, readonly) NSInteger currentDBVersion;
@property (nonatomic, assign, readonly, getter=isDatabaseReady) BOOL databaseReady;

/// Opens cheat.sqlite and attaches `languagePackPath` (nil = English only).
/// Reopens when either path changed or the file at a path was replaced; a
/// cheat.sqlite of an older schema, or one that cannot be read, leaves the
/// catalog not ready.
- (void)initializeWithCheatPath:(NSString *)cheatPath
               languagePackPath:(nullable NSString *)languagePackPath
                     completion:(nullable void (^)(void))completion
    NS_SWIFT_NAME(initialize(withCheatPath:languagePackPath:completion:));

/// Closes the catalog. Call after cheat.sqlite is replaced or deleted; the next
/// initialize reopens it.
- (void)closeDatabase;

/// Full integrity scan (quick_check) of the catalog file at `path`, on a
/// private connection. Takes a few seconds on device, so it runs once per
/// installed file: right after a download, or in the background at launch for
/// a file installed by an older version. Synchronous; never on the main thread.
+ (BOOL)verifyCatalogFileAtPath:(NSString *)path NS_SWIFT_NAME(verifyCatalogFile(atPath:));

/// Whether the file currently at `path` already passed verifyCatalogFileAtPath:.
+ (BOOL)isCatalogFileVerifiedAtPath:(NSString *)path NS_SWIFT_NAME(isCatalogFileVerified(atPath:));

/// Page of catalog games on the given platforms, optionally filtered by a
/// keyword matched against the English name, the group name and the
/// translated name. Pass knownTotalCount > 0 to skip the COUNT(*).
- (void)fetchGamesForPlatformIds:(NSArray<NSNumber *> *)platformIds
                          keyword:(NSString *)keyword
                           offset:(NSInteger)offset
                            limit:(NSInteger)limit
                  knownTotalCount:(NSInteger)knownTotalCount
                       completion:(void (^)(NSArray<RAGameEntry *> *games,
                                            NSInteger totalCount,
                                            NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchGames(forPlatformIds:keyword:offset:limit:knownTotalCount:completion:));

/// All cheats of one catalog game, in cht order.
- (void)fetchCheatsForGameId:(NSInteger)gameId
                  completion:(void (^)(NSArray<RACheatItem *> *cheats,
                                       NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchCheats(forGameId:completion:));

/// Resolves a curated "popular games" list to fully populated RAGameEntry rows
/// (cheat count + localized name), preserving the order of `gameNames` and
/// skipping names that no longer exist. The featured catalog section keys on
/// (platform_id, exact game_name) so it survives cheat.sqlite rebuilds as long
/// as the title spelling is stable.
- (void)fetchFeaturedGamesForPlatformIds:(NSArray<NSNumber *> *)platformIds
                               gameNames:(NSArray<NSString *> *)gameNames
                              completion:(void (^)(NSArray<RAGameEntry *> *games,
                                                   NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchFeaturedGames(forPlatformIds:gameNames:completion:));

/// cheat_index of the given cheat ids, limited to one catalog game. Used once
/// to re-key template switches that were stored by cheat id.
- (nullable NSDictionary<NSNumber *, NSNumber *> *)cheatIndexesForCheatIds:(NSArray<NSNumber *> *)cheatIds
                                                                    gameId:(NSInteger)gameId
                                                                     error:(NSError **)error
    NS_SWIFT_NAME(cheatIndexes(forCheatIds:gameId:));

/// Synchronous lookup for launch-time auto binding. The caller passes the
/// authoritative full English name from gamerdb, not a Discover group name.
/// Matching tries exact full name first, then a conservative same-group region
/// fallback; *game stays nil if it still maps to several templates. Returns
/// NO only when a query failed, so a read failure is never recorded as a
/// no-match binding.
- (BOOL)lookupGameForPlatformIds:(NSArray<NSNumber *> *)platformIds
                     englishName:(NSString *)englishName
                            game:(RAGameEntry * _Nullable * _Nonnull)game
                           error:(NSError **)error
    NS_SWIFT_NAME(lookupGame(forPlatformIds:englishName:game:));

/// Exact (platform_id, game_name) lookup, used to re-locate a persisted
/// binding after the catalog is rebuilt. NO only when the query failed.
- (BOOL)lookupGameForPlatformId:(NSInteger)platformId
                      exactName:(NSString *)gameName
                           game:(RAGameEntry * _Nullable * _Nonnull)game
                          error:(NSError **)error
    NS_SWIFT_NAME(lookupGame(platformId:exactName:game:));

/// NO only when the query failed; a missing game is YES with *game = nil.
- (BOOL)lookupGameForGameId:(NSInteger)gameId
                       game:(RAGameEntry * _Nullable * _Nonnull)game
                      error:(NSError **)error
    NS_SWIFT_NAME(lookupGame(gameId:game:));

@end

NS_ASSUME_NONNULL_END
