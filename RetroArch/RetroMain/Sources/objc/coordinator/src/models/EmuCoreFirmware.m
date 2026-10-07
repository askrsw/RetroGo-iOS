//
//  EmuCoreFirmware.m
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

#import "EmuCoreFirmware.h"
#import <CommonCrypto/CommonDigest.h>
#include <utils/retrogo_log.h>

NS_ASSUME_NONNULL_BEGIN

@implementation EmuCoreFirmware

- (instancetype)initWithPath:(NSString *)path desc:(nullable NSString *)desc optional:(BOOL)optional md5:(nullable NSString *)md5 {
    self = [super init];
    if(self != nil) {
        _path = path;
        _desc = desc;
        _optional = optional;
        _md5 = md5;

        _name = [_path lastPathComponent];
    }
    return self;
}

- (NSString *)fullPath {
    NSString *filePath = _path;

    if ([filePath hasPrefix:@"~"]) {
        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        filePath = [filePath stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:docsPath];
    }

    return filePath;
}

- (BOOL)fileExists {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filePath = self.fullPath;
    BOOL isDirectory = NO;
    BOOL exists = [fileManager fileExistsAtPath:filePath isDirectory:&isDirectory];
    return (exists && !isDirectory);
}

- (BOOL)isValid {
    // 1. Check whether the file exists
    if (![self fileExists]) {
        return NO;
    }

    // 2. If md5 is empty, return YES as required
    if (_md5 == nil || _md5.length == 0) {
        return YES;
    }


    // 3. Compute the actual file's MD5
    NSString *actualMD5 = [self calculateFileMD5];

    // 4. Compare case-insensitively
    return [[actualMD5 lowercaseString] isEqualToString:[_md5 lowercaseString]];
}

- (BOOL)copyFile:(NSURL *)url {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *destPath = self.fullPath;

    // 1. Make sure the destination folder exists
    NSString *folderPath = [destPath stringByDeletingLastPathComponent];
    if (![fileManager fileExistsAtPath:folderPath]) {
        [fileManager createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // 2. Start security-scoped access (required, or files outside the sandbox can't be read)
    BOOL accessGranted = [url startAccessingSecurityScopedResource];

    // 3. Copy, replacing the existing file
    if ([fileManager fileExistsAtPath:destPath]) {
        [fileManager removeItemAtPath:destPath error:nil];
    }

    NSError *error = nil;
    BOOL success = [fileManager copyItemAtPath:url.path toPath:destPath error:&error];

    // 4. Release the access
    if (accessGranted) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!success) {
        RETROGO_LOGE(IMPORT, "Firmware copy failed: %@", error.localizedDescription);
    }

    return success;
}

- (BOOL)deleteFile {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *destPath = self.fullPath;

    // 1. Check whether the file exists (optional, to avoid errors on a missing file)
    if (![fileManager fileExistsAtPath:destPath]) {
        RETROGO_LOGN(IMPORT, "Firmware delete skipped: file not found at %@", destPath);
        return YES;
    }

    // 2. Delete it
    NSError *error = nil;
    BOOL success = [fileManager removeItemAtPath:destPath error:&error];

    if (!success) {
        RETROGO_LOGE(IMPORT, "Failed to delete firmware %@: %@", destPath, error.localizedDescription);
        return NO;
    }

    return YES;
}

// Helper: compute a file's MD5 efficiently
- (NSString *)calculateFileMD5 {
    NSString *filePath = self.fullPath;

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!handle) return nil;

    CC_MD5_CTX md5;
    CC_MD5_Init(&md5);

    BOOL done = NO;
    while (!done) {
        @autoreleasepool {
            NSData *fileData = [handle readDataOfLength:256 * 1024]; // Read 256KB at a time
            if (fileData.length > 0) {
                CC_MD5_Update(&md5, fileData.bytes, (CC_LONG)fileData.length);
            } else {
                done = YES;
            }
        }
    }
    [handle closeFile];

    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5_Final(digest, &md5);

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

@end

NS_ASSUME_NONNULL_END
