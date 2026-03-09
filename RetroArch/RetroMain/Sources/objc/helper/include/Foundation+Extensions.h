//
//  Foundation+Extensions.h
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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBundle (Extension)
+ (NSArray<NSArray<NSString *> *> *)languages;
+ (NSString *)currentLanguage;
+ (NSString *)currentSimpleLanguageKey;
+ (NSString *)systemLanguage;
+ (BOOL)setLanguage:(NSString *)language storeKey:(BOOL)storeKey;
+ (void)setLanguageFollowSystem;

+ (NSString *)localizedStringForKey:(NSString *)key;
+ (NSString *)localizedStringForKey:(NSString *)key count:(NSInteger)count;
@end

@interface NSDateFormatter (Extension)
+ (NSDateFormatter *)yyyyMMddHHmmss;
+ (NSDateFormatter *)hhColonMm;
+ (NSDateFormatter *)cnFullDateFormatter;
+ (NSDateFormatter *)cnSimpleDateFormatter;
+ (NSDateFormatter *)enFullDateFormatter;
+ (NSDateFormatter *)enSimpleDateFormatter;
@end

@interface NSCalendar (Extension)
- (BOOL)isDateInDayBeforeYesterday:(NSDate *)date;
@end

@interface NSString (Extension)
- (CGSize)renderedSizeWithFont:(UIFont *)font constrainedToSize:(CGSize)constrainedSize;
+ (NSString *)randomString:(NSInteger)count caseInsensitive:(BOOL)caseInsensitive;
@end

@interface NSAttributedString (Extension)
- (CGSize)calculateDrawingSizeWithWidth:(CGFloat)width height:(CGFloat)height option:(NSStringDrawingOptions)option;
@end

@interface NSData (Extension)
- (NSString *)sha256Hash;
@end

@interface NSFileManager (Extension)
@property(nonatomic, copy, readonly) NSString *documentFolder;
@property(nonatomic, copy, readonly) NSURL *documentFolderUrl;

- (BOOL)pathIsDirectory:(NSString *)path;
- (BOOL)urlIsDirectory:(NSURL *)url;
- (BOOL)pathIsFile:(NSString *)path;
- (BOOL)urlIsFile:(NSURL *)url;

- (BOOL)createDirectoryIfNotExistsAtPath:(NSString *)path;
- (BOOL)createDirectoryIfNotExistsAtURL:(NSURL *)url;

- (nullable NSString *)md5ForFileAtPath:(NSString *)filePath;
- (nullable NSString *)sha256ForFileAtPath:(NSString *)filePath;
@end

@interface NSURL (Extension)
- (nullable NSString *)computeSHA256String:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
