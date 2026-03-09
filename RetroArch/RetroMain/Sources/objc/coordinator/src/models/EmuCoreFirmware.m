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
    // 1. 检查文件是否存在
    if (![self fileExists]) {
        return NO;
    }

    // 2. 如果 md5 为空，按要求直接返回 YES
    if (_md5 == nil || _md5.length == 0) {
        return YES;
    }


    // 3. 计算实际文件的 MD5
    NSString *actualMD5 = [self calculateFileMD5];

    // 4. 忽略大小写进行比较
    return [[actualMD5 lowercaseString] isEqualToString:[_md5 lowercaseString]];
}

- (BOOL)copyFile:(NSURL *)url {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *destPath = self.fullPath;

    // 1. 确保目标文件夹存在
    NSString *folderPath = [destPath stringByDeletingLastPathComponent];
    if (![fileManager fileExistsAtPath:folderPath]) {
        [fileManager createDirectoryAtPath:folderPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    // 2. 开启安全访问权限 (必须，否则无法读取沙盒外文件)
    BOOL accessGranted = [url startAccessingSecurityScopedResource];

    // 3. 执行替换式拷贝
    if ([fileManager fileExistsAtPath:destPath]) {
        [fileManager removeItemAtPath:destPath error:nil];
    }

    NSError *error = nil;
    BOOL success = [fileManager copyItemAtPath:url.path toPath:destPath error:&error];

    // 4. 释放权限
    if (accessGranted) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!success) {
        NSLog(@"[Firmware] Copy failed: %@", error.localizedDescription);
    }

    return success;
}

- (BOOL)deleteFile {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *destPath = self.fullPath;

    // 1. 检查文件是否存在 (可选，为了防止对不存在的文件报错)
    if (![fileManager fileExistsAtPath:destPath]) {
        NSLog(@"Delete skipped: File not found at %@", destPath);
        return YES;
    }

    // 2. 执行删除
    NSError *error = nil;
    BOOL success = [fileManager removeItemAtPath:destPath error:&error];

    if (!success) {
        NSLog(@"Failed to delete file: %@, Error: %@", destPath, error.localizedDescription);
        return NO;
    }

    return YES;
}

// 辅助方法：高效计算文件 MD5
- (NSString *)calculateFileMD5 {
    NSString *filePath = self.fullPath;

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!handle) return nil;

    CC_MD5_CTX md5;
    CC_MD5_Init(&md5);

    BOOL done = NO;
    while (!done) {
        @autoreleasepool {
            NSData *fileData = [handle readDataOfLength:256 * 1024]; // 每次读取 256KB
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
