//
//  RAArchiveReader.h
//  RetroGo
//
//  Created by haharsw on 2026/9/26.
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

// A case starting with a digit ("7z") stops Swift from stripping the common
// "RAArchiveFormat" prefix, so the Swift names are given explicitly.
typedef NS_ENUM(NSInteger, RAArchiveFormat) {
    RAArchiveFormatUnknown NS_SWIFT_NAME(unknown) = 0,
    RAArchiveFormatZip NS_SWIFT_NAME(zip),
    RAArchiveFormat7z NS_SWIFT_NAME(sevenZip),
};

FOUNDATION_EXPORT NSErrorDomain const RAArchiveErrorDomain;

typedef NS_ERROR_ENUM(RAArchiveErrorDomain, RAArchiveErrorCode) {
    /// Path extension is neither zip nor 7z.
    RAArchiveErrorUnsupportedFormat = 1,
    /// The archive could not be opened or its directory could not be parsed.
    RAArchiveErrorOpenFailed = 2,
    /// Zip64 entries or compression methods other than stored/deflate.
    RAArchiveErrorUnsupportedEntry = 3,
    RAArchiveErrorEntryNotFound = 4,
    RAArchiveErrorDecompressFailed = 5,
    RAArchiveErrorCRCMismatch = 6,
    RAArchiveErrorWriteFailed = 7,
};

/// One file inside a zip/7z archive. Directory entries are never reported.
@interface RAArchiveEntry : NSObject

/// Name as stored in the archive, including any folder prefix ("sub/a.bin").
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) uint64_t size;
/// Only meaningful when `hasCRC` is YES.
@property (nonatomic, assign, readonly) uint32_t crc32;
/// Always YES for zip. For 7z, NO when the archive did not record a CRC for
/// this entry; callers should then fall back to matching by name + size.
@property (nonatomic, assign, readonly) BOOL hasCRC;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Stateless reader over libretro-common `file/archive_file.h` (zip + 7z).
///
/// Every call opens and closes the archive on its own and keeps no shared state,
/// so different threads may call it concurrently. All methods do blocking file
/// I/O and must not run on the main thread for large archives.
///
/// Limits inherited from libretro-common:
/// - zip: 32-bit sizes only; zip64 archives/entries are reported as errors.
/// - 7z: entries larger than 4 GiB are not supported. Extracting from a solid
///   archive decompresses the whole solid block in memory; prefer the batch
///   method so a block is decompressed only once.
@interface RAArchiveReader : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// Format by path extension (zip / 7z, case-insensitive). No file access.
+ (RAArchiveFormat)formatOfArchiveAtPath:(NSString *)path;

/// Lists entries without decompressing anything (zip central directory / 7z header).
+ (nullable NSArray<RAArchiveEntry *> *)entriesOfArchiveAtPath:(NSString *)path
                                                         error:(NSError * _Nullable * _Nullable)error;

/// Extracts one entry, matched by exact name, to `destination`.
/// Intermediate directories are created and an existing file is replaced.
/// The data is CRC-verified before it is written.
+ (BOOL)extractEntry:(NSString *)entryName
   fromArchiveAtPath:(NSString *)path
              toPath:(NSString *)destination
               error:(NSError * _Nullable * _Nullable)error;

/// Extracts several entries in a single pass over the archive.
/// `destinations` maps entry name (exact) -> destination file path.
/// Stops at the first failure; files written before the failure are left in place.
+ (BOOL)extractEntries:(NSDictionary<NSString *, NSString *> *)destinations
     fromArchiveAtPath:(NSString *)path
                 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
