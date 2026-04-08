//
//  NSFileManager+Extension.m
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

#import "NSFileManager+Extension.h"
#include <CommonCrypto/CommonDigest.h>

@implementation NSFileManager (Extension)

- (NSString *)documentFolder {
    return [[self documentFolderUrl] path];
}

- (NSURL *)documentFolderUrl {
    return [[self URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
}

- (NSString *)libraryFolder {
    return [[self libraryFolderUrl] path];
}

- (NSURL *)libraryFolderUrl {
    return [[self URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] firstObject];
}

- (NSString *)applicationSupportFolder {
    return [[self applicationSupportFolderUrl] path];
}

- (NSURL *)applicationSupportFolderUrl {
    return [[self URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
}

- (BOOL)pathIsDirectory:(NSString *)path {
    BOOL isDirectory = NO;
    BOOL exists = [self fileExistsAtPath:path isDirectory:&isDirectory];
    return exists && isDirectory;
}

- (BOOL)urlIsDirectory:(NSURL *)url {
    NSString *path = [url path];
    return [self pathIsDirectory:path];
}

- (BOOL)pathIsFile:(NSString *)path {
    BOOL isDirectory = NO;
    BOOL exists = [self fileExistsAtPath:path isDirectory:&isDirectory];
    return exists && !isDirectory;
}

- (BOOL)urlIsFile:(NSURL *)url {
    NSString *path = [url path];
    return [self pathIsFile:path];
}

- (BOOL)createDirectoryIfNotExistsAtPath:(NSString *)path {
    if (![self fileExistsAtPath:path]) {
        NSError *error = nil;
        BOOL success = [self createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
        if (!success) {
            NSLog(@"Failed to create directory at path: %@, error: %@", path, error);
        }
        return success;
    }
    return [self pathIsDirectory:path];
}

- (BOOL)createDirectoryIfNotExistsAtURL:(NSURL *)url {
    NSString *path = [url path];
    return [self createDirectoryIfNotExistsAtPath:path];
}

- (nullable NSString *)md5ForFileAtPath:(NSString *)filePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!fileHandle) return nil;

    CC_MD5_CTX ctx;
    unsigned char result[16];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5_Init(&ctx);
#pragma clang diagnostic pop

    @try {
        while (true) {
            @autoreleasepool {
                NSData *data = [fileHandle readDataOfLength:1024 * 1024]; // 1MB per chunk
                if (data.length == 0) break;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                CC_MD5_Update(&ctx, data.bytes, (CC_LONG)data.length);
#pragma clang diagnostic pop
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Exception occurred while reading file: %@", exception);
        return nil;
    } @finally {
        if (fileHandle) {
            [fileHandle closeFile];
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5_Final(result, &ctx);
#pragma clang diagnostic pop
    
    NSMutableString *md5String = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 16; i++) {
        [md5String appendFormat:@"%02x", result[i]];
    }
    return md5String;
}

- (nullable NSString *)sha256ForFileAtPath:(NSString *)filePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
    if (!fileHandle) return nil;

    CC_SHA256_CTX ctx;
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Init(&ctx);

    @try {
        while (true) {
            @autoreleasepool {
                NSData *data = [fileHandle readDataOfLength:1024 * 1024]; // 1MB per chunk
                if (data.length == 0) break;
                CC_SHA256_Update(&ctx, data.bytes, (CC_LONG)data.length);
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"Exception occurred while reading file: %@", exception);
        return nil;
    } @finally {
        if (fileHandle) {
            [fileHandle closeFile];
        }
    }

    CC_SHA256_Final(result, &ctx);

    NSMutableString *sha256String = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [sha256String appendFormat:@"%02x", result[i]];
    }
    return sha256String;
}

@end
