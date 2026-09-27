//
//  RAZipWriter.h
//  RetroGo
//
//  Created by haharsw on 2026/9/27.
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
#import "RAArchiveReader.h"

NS_ASSUME_NONNULL_BEGIN

/// Writes a new zip archive entry by entry. Used to rebuild MAME sets from files
/// gathered from several archives.
///
/// - Entries taken from a zip keep their compressed data (stored/deflate): it is copied
///   as is, while being inflated on the side to verify its CRC and size.
/// - Entries from 7z archives and raw data are deflated (stored when that is smaller).
/// - Output is written to `<path>.partial.zip` and moved to `path` only by a successful
///   `finish`, after the written directory has been read back and checked. Any failure
///   leaves an existing file at `path` untouched; call `cancel` (or let the writer go)
///   to remove the partial file.
/// - No zip64: every entry and the whole archive must stay below 4 GiB, fewer than
///   65535 entries. Timestamps are fixed (1980-01-01) so identical input gives an
///   identical file.
///
/// Not thread-safe; use one writer from one thread.
@interface RAZipWriter : NSObject

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, assign, readonly) NSUInteger entryCount;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;

/// Adds `entry` (as listed by `+[RAArchiveReader entriesOfArchiveAtPath:error:]` for
/// `archivePath`) under `name`. Names must be unique within the new archive.
- (BOOL)addEntry:(RAArchiveEntry *)entry
fromArchiveAtPath:(NSString *)archivePath
          asName:(NSString *)name
           error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(add(_:fromArchiveAtPath:asName:));

/// Adds several entries of one archive under the given names (same order and count).
/// 7z entries are extracted in a single pass, so a solid block is decompressed once
/// instead of once per entry.
- (BOOL)addEntries:(NSArray<RAArchiveEntry *> *)entries
 fromArchiveAtPath:(NSString *)archivePath
           asNames:(NSArray<NSString *> *)names
             error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(add(_:fromArchiveAtPath:asNames:));

/// Adds `data`, deflated, under `name`.
- (BOOL)addData:(NSData *)data name:(NSString *)name error:(NSError * _Nullable * _Nullable)error;

/// Writes the central directory, verifies the result and moves it to `path`.
- (BOOL)finish:(NSError * _Nullable * _Nullable)error;

/// Abandons the archive and removes the partial file. `path` is left untouched.
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
