//
//  RAGameLocalizationManager.m
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

#import "RAGameLocalizationManager.h"

#include <sqlite3.h>

static NSString * const kRALocErrorDomain = @"com.retrogame.gameloc";
static NSString * const kRALocLanguage = @"zh";

static NSString * _Nullable p_colText(sqlite3_stmt *stmt, int col);
static NSString *p_locNorm(NSString *s);

@interface RAGameLocalizedName()
@property (nonatomic, assign, readwrite) NSInteger platformId;
@property (nonatomic, copy, readwrite) NSString *groupName;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, assign, readwrite) NSInteger source;
@property (nonatomic, assign, readwrite, getter=isReference) BOOL reference;
@end

@implementation RAGameLocalizedName
@end

@implementation RAGameLocalizationManager
{
    NSString *d_dbPath;
    sqlite3 *d_db;
    dispatch_queue_t d_dbQueue;
}

+ (instancetype)shared {
    static RAGameLocalizationManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        d_dbQueue = dispatch_queue_create("com.retrogame.gameloc", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)initialize:(NSString *)dbPath completion:(nullable void (^)(void))completion {
    d_dbPath = [dbPath copy];
    dispatch_async(d_dbQueue, ^{
        [self p_open];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

- (void)dealloc {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
}

- (void)localizedNameForPlatformId:(NSInteger)platformId
                         groupName:(NSString *)groupName
                        completion:(void (^)(RAGameLocalizedName * _Nullable name,
                                             NSError * _Nullable error))completion {
    if (groupName.length == 0) {
        completion(nil, nil);
        return;
    }
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        RAGameLocalizedName *name = [self p_lookupPlatformId:platformId groupName:groupName error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(name, error);
        });
    });
}

- (void)localizedNamesForPlatformId:(NSInteger)platformId
                         groupNames:(NSArray<NSString *> *)groupNames
                         completion:(void (^)(NSDictionary<NSString *, RAGameLocalizedName *> *names,
                                              NSError * _Nullable error))completion {
    NSArray<NSString *> *unique = [[NSOrderedSet orderedSetWithArray:groupNames] array];
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSMutableDictionary<NSString *, RAGameLocalizedName *> *result = [NSMutableDictionary dictionary];
        for (NSString *groupName in unique) {
            if (groupName.length == 0) continue;
            RAGameLocalizedName *name = [self p_lookupPlatformId:platformId groupName:groupName error:&error];
            if (name) result[groupName] = name;
            if (error) break;
        }
        NSDictionary *copy = [result copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, error);
        });
    });
}

- (void)searchLocalizedNamesWithKeyword:(NSString *)keyword
                              platformId:(NSInteger)platformId
                                  limit:(NSInteger)limit
                             completion:(void (^)(NSArray<RAGameLocalizedName *> *names,
                                                  NSError * _Nullable error))completion {
    NSString *norm = p_locNorm(keyword);
    if (norm.length == 0) {
        completion(@[], nil);
        return;
    }
    dispatch_async(d_dbQueue, ^{
        NSError *error = nil;
        NSMutableArray<RAGameLocalizedName *> *names = [NSMutableArray array];
        NSString *pattern = [NSString stringWithFormat:@"%%%@%%", norm];
        const char *sqlAll =
            "SELECT platform_id, group_name, name, source "
            "FROM name_loc "
            "WHERE lang = ? AND is_primary = 1 AND name_norm LIKE ? "
            "ORDER BY name COLLATE NOCASE ASC LIMIT ?;";
        const char *sqlPlatform =
            "SELECT platform_id, group_name, name, source "
            "FROM name_loc "
            "WHERE lang = ? AND is_primary = 1 AND platform_id = ? AND name_norm LIKE ? "
            "ORDER BY name COLLATE NOCASE ASC LIMIT ?;";
        sqlite3_stmt *stmt = NULL;
        const char *sql = platformId == -1 ? sqlAll : sqlPlatform;
        if (d_db && sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, kRALocLanguage.UTF8String, -1, SQLITE_TRANSIENT);
            if (platformId == -1) {
                sqlite3_bind_text(stmt, 2, pattern.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int64(stmt, 3, (sqlite3_int64)MAX(limit, 1));
            } else {
                sqlite3_bind_int64(stmt, 2, (sqlite3_int64)platformId);
                sqlite3_bind_text(stmt, 3, pattern.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_int64(stmt, 4, (sqlite3_int64)MAX(limit, 1));
            }
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                [names addObject:[self p_nameFromStmt:stmt]];
            }
        } else {
            error = [self p_error:@"search localized names prepare failed"];
        }
        sqlite3_finalize(stmt);
        NSArray *copy = [names copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(copy, error);
        });
    });
}

- (BOOL)p_open {
    if (d_db) {
        sqlite3_close(d_db);
        d_db = NULL;
    }
    NSString *uri = [[[NSURL fileURLWithPath:d_dbPath] absoluteString]
                     stringByAppendingString:@"?immutable=1"];
    int rc = sqlite3_open_v2(uri.UTF8String, &d_db,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL);
    if (rc != SQLITE_OK) {
        NSLog(@"[RAGameLocalizationManager] SQLite open failed(%d): %@", rc, d_dbPath);
        if (d_db) {
            sqlite3_close(d_db);
            d_db = NULL;
        }
        return NO;
    }
    return YES;
}

- (RAGameLocalizedName *)p_lookupPlatformId:(NSInteger)platformId
                                  groupName:(NSString *)groupName
                                      error:(NSError **)error {
    const char *sql =
        "SELECT platform_id, group_name, name, source "
        "FROM name_loc "
        "WHERE platform_id = ? AND group_name = ? AND lang = ? AND is_primary = 1 "
        "LIMIT 1;";
    sqlite3_stmt *stmt = NULL;
    RAGameLocalizedName *name = nil;
    if (d_db && sqlite3_prepare_v2(d_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)platformId);
        sqlite3_bind_text(stmt, 2, groupName.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, kRALocLanguage.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            name = [self p_nameFromStmt:stmt];
        }
    } else if (error) {
        *error = [self p_error:@"localized name query prepare failed"];
    }
    sqlite3_finalize(stmt);
    return name;
}

- (RAGameLocalizedName *)p_nameFromStmt:(sqlite3_stmt *)stmt {
    RAGameLocalizedName *name = [[RAGameLocalizedName alloc] init];
    name.platformId = (NSInteger)sqlite3_column_int64(stmt, 0);
    name.groupName = p_colText(stmt, 1) ?: @"";
    name.name = p_colText(stmt, 2) ?: @"";
    name.source = (NSInteger)sqlite3_column_int64(stmt, 3);
    name.reference = name.source == RAGameNameLocalizationSourceDeepSeekLoose;
    return name;
}

- (NSError *)p_error:(NSString *)reason {
    return [NSError errorWithDomain:kRALocErrorDomain
                               code:1001
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

static NSString * _Nullable p_colText(sqlite3_stmt *stmt, int col) {
    const unsigned char *text = sqlite3_column_text(stmt, col);
    return text ? [NSString stringWithUTF8String:(const char *)text] : nil;
}

static NSString *p_locNorm(NSString *s) {
    static NSCharacterSet *keep = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet decimalDigitCharacterSet];
        [set formUnionWithCharacterSet:[NSCharacterSet lowercaseLetterCharacterSet]];
        [set formUnionWithCharacterSet:[NSCharacterSet uppercaseLetterCharacterSet]];
        [set addCharactersInRange:NSMakeRange(0x4E00, 0x9FFF - 0x4E00 + 1)];
        [set addCharactersInRange:NSMakeRange(0x3400, 0x4DBF - 0x3400 + 1)];
        keep = [set copy];
    });
    NSMutableString *out = [NSMutableString string];
    NSString *lower = s.lowercaseString ?: @"";
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([keep characterIsMember:c]) {
            [out appendFormat:@"%C", c];
        }
    }
    return out;
}

@end
