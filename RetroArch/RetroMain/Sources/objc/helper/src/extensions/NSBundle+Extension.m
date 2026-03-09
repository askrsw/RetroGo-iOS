//
//  NSBundle+Extension.m
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

#import "NSBundle+Extension.h"
#import <objc/runtime.h>

static const char *kLocalBundleKey = "localized_bundle_key";
static NSString *kUserSetLanguageKey = @"user_set_language";

@implementation NSBundle (Extension)

+ (NSArray<NSArray<NSString *> *> *)languages {
    static NSArray *sLanguages = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sLanguages = @[
            @[@"en", @"English"],
            @[@"zh-Hans", @"简体中文"],
        ];
    });
    return sLanguages;
}

+ (void)initialize {
    NSString *languageKey = [[NSUserDefaults standardUserDefaults] objectForKey:kUserSetLanguageKey];
    BOOL validLanguage = NO;
    for(NSArray *language in [NSBundle languages]) {
        if([languageKey isEqualToString:language[0]]) {
            validLanguage = YES;
            break;
        }
    }

    if(!validLanguage) {
        languageKey = [NSBundle systemLanguage];
    }

    [NSBundle setLanguage:languageKey storeKey:NO];
}

+ (NSBundle *)localizedBundle {
    return objc_getAssociatedObject(self, kLocalBundleKey);
}

+ (void)setLocalizedBundle:(NSBundle *)bundle {
    objc_setAssociatedObject(self, kLocalBundleKey, bundle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (NSString *)currentLanguage {
    NSBundle *localizedBundle = [self localizedBundle];
    if (localizedBundle) {
        NSArray *components1 = [localizedBundle.bundlePath componentsSeparatedByString:@"/"];
        NSArray *components2 = [components1.lastObject componentsSeparatedByString:@"."];
        return components2.firstObject;
    }
    return [[NSLocale currentLocale] languageCode] ?: @"en";
}

+ (NSString *)currentSimpleLanguageKey {
    NSString *key = [NSBundle currentLanguage];
    if([key hasPrefix:@"zh"]) {
        return @"zh";
    } else {
        return @"en";
    }
}

+ (NSString *)systemLanguage {
    NSString *systemLanguage = [[NSLocale preferredLanguages] firstObject];
    if([systemLanguage hasPrefix:@"zh"]) {
        return @"zh-Hans";
    } else {
        return @"en";
    }
}

+ (BOOL)setLanguage:(NSString *)language storeKey:(BOOL)storeKey {
    NSString *path = [[NSBundle mainBundle] pathForResource:language ofType:@"lproj"];
    if (path) {
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        [self setLocalizedBundle: bundle];
        if(storeKey == YES) {
            [[NSUserDefaults standardUserDefaults] setObject:language forKey:kUserSetLanguageKey];
        }
        return YES;
    } else {
        [self setLocalizedBundle: nil];
        return NO;
    }
}

+ (void)setLanguageFollowSystem {
    NSString *languageKey = [[NSUserDefaults standardUserDefaults] objectForKey:kUserSetLanguageKey];
    if(languageKey != nil) {
        [[NSUserDefaults standardUserDefaults] setObject:nil forKey:kUserSetLanguageKey];
        NSString *languageKey = [NSBundle systemLanguage];
        [NSBundle setLanguage:languageKey storeKey:NO];
    }
}

+ (NSString *)localizedStringForKey:(NSString *)key {
    return [[NSBundle localizedBundle] localizedStringForKey:key value:nil table:nil];
}

+ (NSString *)localizedStringForKey:(NSString *)key count:(NSInteger)count {
    // 1. 获取手动指定的 Bundle
    NSBundle *bundle = [self localizedBundle];
    if (!bundle) {
        return key; // 退回 key 本身
    }

    // 2. 获取格式化模板
    NSString *format = [bundle localizedStringForKey:key value:nil table:nil];

    // 3. 获取对应语言的 Locale
    // 这一点至关重要：即使系统是中文，如果你切到了英文，locale 必须是 en
    // 优化：缓存 Locale，只有当语言切换时才更新
    static NSLocale *cachedLocale = nil;
    static NSString *cachedLang = nil;
    @synchronized (self) {
        NSString *currentLang = [self currentLanguage];
        if (!cachedLocale || ![currentLang isEqualToString:cachedLang]) {
            cachedLocale = [NSLocale localeWithLocaleIdentifier:currentLang];
            cachedLang = [currentLang copy];
        }
    }

    // 4. 格式化
    // 使用变量参数列表的初始化方法，确保 count 能被正确填入 %d 位置
    return [[NSString alloc] initWithFormat:format locale:cachedLocale, (long)count];
}

@end
