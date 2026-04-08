//
//  NSFileManager+Extension.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFileManager (Extension)
@property(nonatomic, copy, readonly) NSString *documentFolder;
@property(nonatomic, copy, readonly) NSURL *documentFolderUrl;
@property(nonatomic, copy, readonly) NSString *libraryFolder;
@property(nonatomic, copy, readonly) NSURL *libraryFolderUrl;
@property(nonatomic, copy, readonly) NSString *applicationSupportFolder;
@property(nonatomic, copy, readonly) NSURL *applicationSupportFolderUrl;

- (BOOL)pathIsDirectory:(NSString *)path;
- (BOOL)urlIsDirectory:(NSURL *)url;
- (BOOL)pathIsFile:(NSString *)path;
- (BOOL)urlIsFile:(NSURL *)url;

- (BOOL)createDirectoryIfNotExistsAtPath:(NSString *)path;
- (BOOL)createDirectoryIfNotExistsAtURL:(NSURL *)url;

- (nullable NSString *)md5ForFileAtPath:(NSString *)filePath;
- (nullable NSString *)sha256ForFileAtPath:(NSString *)filePath;
@end

NS_ASSUME_NONNULL_END
