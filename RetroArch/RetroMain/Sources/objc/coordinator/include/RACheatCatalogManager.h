//
//  RACheatCatalogManager.h
//  RetroMain
//
//  Created by haharsw on 2026/6/11.
//  Copyright © 2026 haharsw. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RAGameRDBManager.h"
#import "RetroArchX+Cheat.h"

NS_ASSUME_NONNULL_BEGIN

/// Read-only catalog over cheat.sqlite. It deliberately returns the app-wide
/// RAGameEntry/RACheatItem models so callers can pass data across database,
/// Swift UI, and RetroArch cheat-application code without adapter objects.
@interface RACheatCatalogManager : NSObject

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

/// `PRAGMA user_version` from cheat.sqlite. Auto-binding stores this alongside
/// no-match rows so a future repacked cheat DB can trigger one fresh lookup.
@property (nonatomic, assign, readonly) NSInteger currentDBUserVersion;
@property (nonatomic, assign, readonly, getter=isDatabaseReady) BOOL databaseReady;

- (void)initializeWithCheatPath:(NSString *)cheatPath
               localizationPath:(nullable NSString *)localizationPath
                     completion:(nullable void (^)(void))completion
    NS_SWIFT_NAME(initialize(withCheatPath:localizationPath:completion:));

- (void)fetchGamesForPlatformId:(NSInteger)platformId
                         offset:(NSInteger)offset
                          limit:(NSInteger)limit
                knownTotalCount:(NSInteger)knownTotalCount
                     completion:(void (^)(NSArray<RAGameEntry *> *games,
                                          NSInteger totalCount,
                                          NSError * _Nullable error))completion;

- (void)fetchGamesForPlatformIds:(NSArray<NSNumber *> *)platformIds
                          keyword:(NSString *)keyword
                           offset:(NSInteger)offset
                            limit:(NSInteger)limit
                  knownTotalCount:(NSInteger)knownTotalCount
                       completion:(void (^)(NSArray<RAGameEntry *> *games,
                                            NSInteger totalCount,
                                            NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchGames(forPlatformIds:keyword:offset:limit:knownTotalCount:completion:));

- (void)fetchCheatsForPlatformId:(NSInteger)platformId
                       groupName:(NSString *)groupName
                      completion:(void (^)(NSArray<RACheatItem *> *cheats,
                                           NSError * _Nullable error))completion;

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

/// Synchronous lookup for launch-time auto binding. The caller passes the
/// authoritative full English name from gamerdb, not a Discover group name.
/// Matching tries exact full name first, then a conservative same-group region
/// fallback; returns nil if it still maps to multiple concrete templates.
- (nullable RAGameEntry *)findGameForPlatformIds:(NSArray<NSNumber *> *)platformIds
                                     englishName:(NSString *)englishName
    NS_SWIFT_NAME(findGame(forPlatformIds:englishName:));

/// Legacy group lookup. Returns nil when a group contains multiple concrete
/// templates; persisted bindings should prefer `findGameForGameId:`.
- (nullable RAGameEntry *)findGameForPlatformId:(NSInteger)platformId
                                      groupName:(NSString *)groupName
    NS_SWIFT_NAME(findGame(platformId:groupName:));

- (nullable RAGameEntry *)findGameForGameId:(NSInteger)gameId
    NS_SWIFT_NAME(findGame(gameId:));

@end

NS_ASSUME_NONNULL_END
