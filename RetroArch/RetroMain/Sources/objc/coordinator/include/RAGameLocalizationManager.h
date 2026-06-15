//
//  RAGameLocalizationManager.h
//  RetroMain
//
//  Created by haharsw on 2026/6/11.
//  Copyright © 2026 haharsw. All rights reserved.
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
