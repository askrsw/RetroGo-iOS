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
@property (nonatomic, assign, readonly) NSInteger  gameCount;
@end

// ---------------------------------------------------------------------------
// MARK: - RAGameEntry
// ---------------------------------------------------------------------------

@interface RAGameEntry : NSObject
@property (nonatomic, assign, readonly)         NSInteger  gameId;
@property (nonatomic, assign, readonly)         NSInteger  platformId;
@property (nonatomic, copy, readonly)           NSString  *name;
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

- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion;
- (NSArray<RAPlatformItem *> *)allPlatforms;
- (BOOL)isPlatformImported:(NSString *)rdbName;
- (void)importRdbAtPath:(NSString *)rdbPath completion:(void (^)(NSInteger importedCount, NSError  * _Nullable error))completion;
/// Fetches a page of games.
/// Pass knownTotalCount > 0 (e.g. from RAPlatformItem.gameCount) to skip the
/// internal COUNT(*) query — useful when the total is already available to the caller.
- (void)fetchGamesForPlatformId:(NSInteger)platformId
                         offset:(NSInteger)offset
                          limit:(NSInteger)limit
               knownTotalCount:(NSInteger)knownTotalCount
                     completion:(void (^)(NSArray<RAGameEntry *> *games, NSInteger totalCount, NSError * _Nullable error))completion;
- (void)searchGamesWithKeyword:(NSString *)keyword platformId:(NSInteger)platformId completion:(void (^)(NSArray<RAGameEntry *> *games, NSError  * _Nullable    error))completion;
- (nullable RAGameEntry *)findGameByCRC32:(NSString *)crc32;
@end

NS_ASSUME_NONNULL_END
