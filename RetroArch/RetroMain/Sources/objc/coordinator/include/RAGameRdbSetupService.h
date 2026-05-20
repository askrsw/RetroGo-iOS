//
//  RAGameRdbSetupService.h
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
// MARK: - Error Domain
// ---------------------------------------------------------------------------

/// NSError domain for RAGameRdbSetupService errors.
FOUNDATION_EXPORT NSErrorDomain const RAGameRdbSetupErrorDomain;

typedef NS_ERROR_ENUM(RAGameRdbSetupErrorDomain, RAGameRdbSetupError) {
    /// Archive file could not be opened or parsed.
    RAGameRdbSetupErrorArchiveOpenFailed   = 1001,
    /// No .rdb files were found inside the zip archive.
    RAGameRdbSetupErrorNoRdbFilesFound     = 1002,
    /// Extraction directory could not be created.
    RAGameRdbSetupErrorDirectoryCreateFailed = 1003,
    /// One or more .rdb files failed to extract.
    RAGameRdbSetupErrorExtractionFailed    = 1004,
    /// SQLite import failed for one or more platforms.
    RAGameRdbSetupErrorImportFailed        = 1005,
};

// ---------------------------------------------------------------------------
// MARK: - RAGameRdbSetupService
// ---------------------------------------------------------------------------

/**
 * RAGameRdbSetupService
 *
 * Bridges RetroArch's C archive API and RAGameRDBManager to provide a
 * single-shot pipeline:
 *
 *   1. Extract all .rdb files from a zip archive (using RetroArch's
 *      internal zlib backend — no extra dependencies).
 *   2. Import each extracted .rdb into the shared RAGameRDBManager SQLite
 *      database, skipping platforms already present (idempotent).
 *
 * Typical call site (Swift, on first-launch after ODR download):
 *
 *   let zipPath  = "…/rdb.zip"          // ODR resource, already in Documents
 *   let rdbDir   = "…/Documents/rdb/"   // extraction destination
 *   RAGameRdbSetupService.shared().setup(
 *       rdbZipPath: zipPath,
 *       extractionDirectory: rdbDir,
 *       progress: { done, total in … },
 *       completion: { imported, error in … }
 *   )
 *
 * Thread model:
 *   - All file I/O and SQLite work happen on an internal serial background
 *     queue.  The progress and completion callbacks are dispatched to the
 *     **main thread**.
 */
@interface RAGameRdbSetupService : NSObject

+ (instancetype)shared;
- (instancetype)init NS_UNAVAILABLE;

/**
 * One-shot setup: extract every .rdb from the zip, then import each into
 * SQLite via RAGameRDBManager.
 *
 * - Extraction is skipped for individual .rdb files whose platform is
 *   already present in the database (idempotent per-platform).
 * - The zip file is NOT deleted after extraction; the caller owns it.
 *
 * @param zipPath            Full path to the rdb .zip archive (e.g. in
 *                           Documents after being copied from the ODR bundle).
 * @param extractionDirectory Directory where .rdb files will be written.
 *                           Created automatically if it does not exist.
 * @param progress           Called on the main thread after each .rdb
 *                           platform finishes importing.
 *                           `completed` = platforms done so far,
 *                           `total`     = total platforms found in the zip.
 * @param completion         Called on the main thread when the full pipeline
 *                           finishes.
 *                           `totalImported` = cumulative game rows written,
 *                           `error`         = first fatal error, or nil.
 */
- (void)setupWithRdbZipPath:(NSString *)zipPath
         extractionDirectory:(NSString *)extractionDirectory
                    progress:(nullable void (^)(NSInteger completed,
                                                NSInteger total))progress
                  completion:(void (^)(NSInteger totalImported,
                                       NSError * _Nullable error))completion;

/**
 * Synchronously extract all .rdb files from a zip archive to a directory.
 *
 * Uses RetroArch's internal zlib backend — no additional dependencies.
 * Safe to call from a background thread; blocks until extraction is done.
 *
 * @param zipPath   Full path to the .zip file.
 * @param directory Destination directory (created if absent).
 * @param error     On failure, populated with a RAGameRdbSetupErrorDomain error.
 * @return          Array of full paths to the extracted .rdb files, or nil on
 *                  error.
 */
- (nullable NSArray<NSString *> *)extractRdbsFromZipAtPath:(NSString *)zipPath
                                               toDirectory:(NSString *)directory
                                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
