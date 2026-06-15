//
//  RAGameLocalizationManager.h
//  RetroMain
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

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RAGameNameLocalizationSource) {
    RAGameNameLocalizationSourceUnknown = 0,
    RAGameNameLocalizationSourceOriginalCJK = 1,
    RAGameNameLocalizationSourceWikidata = 2,
    RAGameNameLocalizationSourceDeepSeekChat = 3,
    RAGameNameLocalizationSourceDeepSeekChatPass2 = 4,
    RAGameNameLocalizationSourceDeepSeekLoose = 5,
};

@interface RAGameLocalizedName : NSObject
@property (nonatomic, assign, readonly) NSInteger platformId;
@property (nonatomic, copy, readonly) NSString *groupName;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) NSInteger source;
@property (nonatomic, assign, readonly, getter=isReference) BOOL reference;
@end

@interface RAGameLocalizationManager : NSObject

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion;

- (void)localizedNameForPlatformId:(NSInteger)platformId
                         groupName:(NSString *)groupName
                        completion:(void (^)(RAGameLocalizedName * _Nullable name,
                                             NSError * _Nullable error))completion;

- (void)localizedNamesForPlatformId:(NSInteger)platformId
                         groupNames:(NSArray<NSString *> *)groupNames
                         completion:(void (^)(NSDictionary<NSString *, RAGameLocalizedName *> *names,
                                              NSError * _Nullable error))completion;

- (void)searchLocalizedNamesWithKeyword:(NSString *)keyword
                              platformId:(NSInteger)platformId
                                  limit:(NSInteger)limit
                             completion:(void (^)(NSArray<RAGameLocalizedName *> *names,
                                                  NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
