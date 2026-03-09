//
//  NSURL+Extension.m
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

#import "NSURL+Extension.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation NSURL (SHA256)

- (nullable NSString *)computeSHA256String:(NSError **)error {
    // 确保是文件 URL
    if (!self.isFileURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"NSURLSHA256ErrorDomain" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"URL must be a file URL"}];
        }
        return nil;
    }

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:self error:error];
    if (!fileHandle) {
        return nil;
    }

    // 初始化 SHA256 上下文
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);

    // 1MB 缓冲区
    const NSUInteger bufferSize = 1024 * 1024;
    BOOL done = NO;

    while (!done) {
        @autoreleasepool {
            NSData *data = [fileHandle readDataOfLength:bufferSize];
            if (data.length == 0) {
                done = YES;
            } else {
                CC_SHA256_Update(&ctx, data.bytes, (CC_LONG)data.length);
            }
        }
    }

    [fileHandle closeFile];

    // 获取最终摘要
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);

    // 转为 Hex String
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }

    return [output copy];
}

@end
